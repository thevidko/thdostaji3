import 'dart:isolate';
import 'dart:typed_data';
import '../models/grid_model.dart' as gm; // Alias for MaterialType

// --- Komunikační modely ---

class WorkerInitCommand {
  final SendPort sendPort;
  final int size;
  final Float64List initialTemps;
  final Uint8List materials;
  final Int32List zoneIds;
  final Map<int, double> zoneTargetTemps;

  WorkerInitCommand({
    required this.sendPort,
    required this.size,
    required this.initialTemps,
    required this.materials,
    required this.zoneIds,
    required this.zoneTargetTemps,
  });
}

class WorkerUpdateMapCommand {
  final Float64List temps;
  final Uint8List materials;
  final Int32List zoneIds;
  final Map<int, double> zoneTargetTemps;

  WorkerUpdateMapCommand({
    required this.temps,
    required this.materials,
    required this.zoneIds,
    required this.zoneTargetTemps,
  });
}

class WorkerStepCommand {
  final double virtualDtSec;
  final int timeMultiplier;
  final double outdoorTemp;

  WorkerStepCommand({
    required this.virtualDtSec,
    required this.timeMultiplier,
    required this.outdoorTemp,
  });
}

// Zpáteční zpráva
class WorkerResponse {
  final Float64List temps;
  WorkerResponse(this.temps);
}

// --- Izolát ---

void runSimulationWorker(WorkerInitCommand initCmd) {
  final ReceivePort receivePort = ReceivePort();

  // Odeslat ReceivePort do UI pro obousměrnou komunikaci
  initCmd.sendPort.send(receivePort.sendPort);

  // Instancovat interního engine writera
  final worker = SimulationWorkerState(initCmd);

  // Naslouchat příkazům
  receivePort.listen((message) {
    if (message is WorkerUpdateMapCommand) {
      worker.updateMap(message);
    } else if (message is WorkerStepCommand) {
      final response = worker.step(message);
      // Předáme zkopírovaný temps Float64List zpět do UI (malá alokace 20KB)
      initCmd.sendPort.send(response);
    }
  });
}

class SimulationWorkerState {
  int size;
  Float64List temps;
  Float64List nextTemps;
  Uint8List materials;
  Int32List zoneIds;
  Map<int, double> zoneTargetTemps;

  // Precalculated O(n) maps pro O(1) přístupy do radiátorů
  final Map<int, List<int>> zoneThermostats = {};
  final Map<int, List<int>> zoneHeaters = {};

  final List<double> conds;
  final List<double> caps;

  SimulationWorkerState(WorkerInitCommand initCmd)
    : size = initCmd.size,
      temps = initCmd.initialTemps,
      nextTemps = Float64List(initCmd.size * initCmd.size),
      materials = initCmd.materials,
      zoneIds = initCmd.zoneIds,
      zoneTargetTemps = initCmd.zoneTargetTemps,
      conds = List.filled(6, 0.0), // Hardcoded 6 material types
      caps = List.filled(6, 0.0) {
    _initMaterialProperties();
    _rebuildZoneLookups();
  }

  void _initMaterialProperties() {
    conds[gm.MaterialType.air.index] = 50.0;
    conds[gm.MaterialType.floor.index] = 20.0;
    conds[gm.MaterialType.wall.index] = 0.5;
    conds[gm.MaterialType.insulation.index] = 0.01;
    conds[gm.MaterialType.heater.index] = 5.0;
    conds[gm.MaterialType.thermostat.index] = 50.0;

    final double m = 1000.0;
    caps[gm.MaterialType.air.index] = 1.0 * m;
    caps[gm.MaterialType.floor.index] = 5.0 * m;
    caps[gm.MaterialType.wall.index] = 15.0 * m;
    caps[gm.MaterialType.insulation.index] = 5.0 * m;
    caps[gm.MaterialType.heater.index] = 10.0 * m;
    caps[gm.MaterialType.thermostat.index] = 0.5 * m;
  }

  void updateMap(WorkerUpdateMapCommand cmd) {
    temps = cmd.temps;
    materials = cmd.materials;
    zoneIds = cmd.zoneIds;
    zoneTargetTemps = cmd.zoneTargetTemps;
    _rebuildZoneLookups();
  }

  void _rebuildZoneLookups() {
    zoneThermostats.clear();
    zoneHeaters.clear();

    for (int zId in zoneTargetTemps.keys) {
      if (zId == 0) continue;
      zoneThermostats[zId] = [];
      zoneHeaters[zId] = [];
    }

    final int length = size * size;
    for (int i = 0; i < length; i++) {
      final int mIdx = materials[i];
      final int zId = zoneIds[i];

      if (zId != 0) {
        if (mIdx == gm.MaterialType.thermostat.index) {
          zoneThermostats.putIfAbsent(zId, () => []).add(i);
        } else if (mIdx == gm.MaterialType.heater.index) {
          zoneHeaters.putIfAbsent(zId, () => []).add(i);
        }
      }
    }
  }

  WorkerResponse step(WorkerStepCommand cmd) {
    // Fyzikální práh kroku: čím menší, tím přesnější
    double dtThreshold = 2.0;

    // Pokud uživatel nasadí obrovské zrychlení (Den/s, Týden/s), snížíme zátěž na frame (maxStepsPerFrame),
    // tím se rychlost de-facto limituje maximální kapacitou procesoru, ale nezačne lagovat!
    // Procesor se neutopí ve smyčce. Omezíme počet cyklů na jeden tick (např. 1500 na 33ms).
    final int maxStepsPerFrame = 1500;

    int steps = (cmd.virtualDtSec / dtThreshold).ceil();
    if (steps > maxStepsPerFrame) {
      steps = maxStepsPerFrame;
    }
    final double stepDt = cmd.virtualDtSec / steps;

    final int length = size * size;

    // 1D pole zapnutých radiátorů (použijeme bool list nebo byte list?)
    // Použijeme rovnou Int8List pro extrémní rychlost: 1 = true, 0 = false
    final Uint8List heatersOn = Uint8List(length);

    for (int step = 0; step < steps; step++) {
      // 1. Zjistit, které radiátory běží (O(n) přes lookup tabulky namísto O(n^4))
      heatersOn.fillRange(0, length, 0); // Vynulovat

      // Procházíme všechny zóny, ve kterých se nachází alespoň jeden radiátor
      for (int zId in zoneHeaters.keys) {
        if (zId == 0) continue;
        final double target = zoneTargetTemps[zId] ?? 22.0;

        // Zkontrolovat termostaty v zóně
        bool needHeat = false;
        final tList = zoneThermostats[zId];
        if (tList != null) {
          for (int tIdx in tList) {
            if (temps[tIdx] < target) {
              needHeat = true;
              break;
            }
          }
        }

        // Zapnout radiátory v zóně
        if (needHeat) {
          final hList = zoneHeaters[zId];
          if (hList != null) {
            for (int hIdx in hList) {
              heatersOn[hIdx] = 1;
            }
          }
        }
      }

      // 2. Samotná zploštěná 1D fyzika (mnohem rychlejší Cache access)
      for (int i = 0; i < length; i++) {
        final double currentTemp = temps[i];
        final int matIndex = materials[i];

        if (matIndex == gm.MaterialType.heater.index && heatersOn[i] == 1) {
          nextTemps[i] = 60.0;
          continue;
        }

        if (matIndex == gm.MaterialType.air.index) {
          nextTemps[i] = cmd.outdoorTemp;
          continue;
        }

        final double myCond = conds[matIndex];
        final double myCap = caps[matIndex];
        double totalFlux = 0.0;

        final int x = i % size;
        final int y = i ~/ size;

        // Doprava (+1)
        if (x + 1 < size) {
          final double neighborCond = conds[materials[i + 1]];
          final double c = (myCond < neighborCond) ? myCond : neighborCond;
          totalFlux += (temps[i + 1] - currentTemp) * c;
        } else {
          totalFlux +=
              (cmd.outdoorTemp - currentTemp) * ((myCond < 1.0) ? myCond : 1.0);
        }

        // Doleva (-1)
        if (x - 1 >= 0) {
          final double neighborCond = conds[materials[i - 1]];
          final double c = (myCond < neighborCond) ? myCond : neighborCond;
          totalFlux += (temps[i - 1] - currentTemp) * c;
        } else {
          totalFlux +=
              (cmd.outdoorTemp - currentTemp) * ((myCond < 1.0) ? myCond : 1.0);
        }

        // Dolů (+size)
        if (y + 1 < size) {
          final double neighborCond = conds[materials[i + size]];
          final double c = (myCond < neighborCond) ? myCond : neighborCond;
          totalFlux += (temps[i + size] - currentTemp) * c;
        } else {
          totalFlux +=
              (cmd.outdoorTemp - currentTemp) * ((myCond < 1.0) ? myCond : 1.0);
        }

        // Nahoru (-size)
        if (y - 1 >= 0) {
          final double neighborCond = conds[materials[i - size]];
          final double c = (myCond < neighborCond) ? myCond : neighborCond;
          totalFlux += (temps[i - size] - currentTemp) * c;
        } else {
          totalFlux +=
              (cmd.outdoorTemp - currentTemp) * ((myCond < 1.0) ? myCond : 1.0);
        }

        // Fyzikální výpočet posunu tepla bez jakékoliv nebezpečné tolerance.
        nextTemps[i] = currentTemp + (totalFlux * stepDt / myCap);
      }

      // Pointer Swap (Žádný foreach pro kopírování přes celou paměť)
      final Float64List tmp = temps;
      temps = nextTemps;
      nextTemps = tmp;
    }

    // Vrátíme kopii pole jako Float64List pro UI
    return WorkerResponse(Float64List.fromList(temps));
  }
}
