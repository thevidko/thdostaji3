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
  final int size;
  final Float64List temps;
  final Uint8List materials;
  final Int32List zoneIds;
  final Map<int, double> zoneTargetTemps;
  final Map<int, double> zoneSatisfaction;

  WorkerUpdateMapCommand({
    required this.size,
    required this.temps,
    required this.materials,
    required this.zoneIds,
    required this.zoneTargetTemps,
    required this.zoneSatisfaction,
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
  final Map<int, double> zoneSatisfaction;
  // Kumulativní tepelná energie dodaná radiátory do každé zóny [sim. J]
  final Map<int, double> zoneEnergyConsumed;
  // Okamžitý výkon radiátorů v každé zóně za poslední frame [sim. W]
  final Map<int, double> zoneInstantPower;
  WorkerResponse(
    this.temps,
    this.zoneSatisfaction,
    this.zoneEnergyConsumed,
    this.zoneInstantPower,
  );
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
  Map<int, double> zoneSatisfaction = {};
  // Kumulativní energie dodaná radiátory per zóna od spuštění simulace [sim. J]
  Map<int, double> zoneEnergyConsumed = {};
  // Okamžitý výkon radiátorů per zóna za aktuální frame [sim. W]
  Map<int, double> zoneInstantPower = {};

  // Precalculated O(n) maps pro O(1) přístupy do radiátorů
  final Map<int, List<int>> zoneThermostats = {};
  final Map<int, List<int>> zoneHeaters = {};

  final List<double> conds;
  final List<double> caps;

  // Konstanta vodivosti zdroje radiátoru — sdílená mezi fyzikálním výpočtem a stabilitní analýzou.
  static const double heaterSourceConductance = 500.0;

  // Maximální stabilní dt odvozený z parametrů materiálů (CFL podmínka pro explicitní schéma).
  // Přepočítá se při každé změně parametrů materiálů.
  late double _dtThreshold;

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
    conds[gm.MaterialType.wall.index] =
        1.0; // Zvýšeno z 0.5 kvůli lepšímu průniku tepla do nezásobených místností
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

    // Odvodit maximální stabilní dt z parametrů materiálů.
    // CFL podmínka pro explicitní FD schéma (4 sousedé):
    //   dt_max(m) = cap[m] / (4 * cond_eff[m])
    // kde cond_eff zahrnuje i zdroj radiátoru pro buňky typu heater.
    // Globální dtThreshold = min přes všechny materiály, s bezpečnostním faktorem 0.9.
    double minDt = double.infinity;
    for (int m = 0; m < conds.length; m++) {
      double effectiveCond = 4.0 * conds[m];
      if (m == gm.MaterialType.heater.index) {
        effectiveCond += heaterSourceConductance;
      }
      if (effectiveCond > 0) {
        final double dtMax = caps[m] / effectiveCond;
        if (dtMax < minDt) minDt = dtMax;
      }
    }
    _dtThreshold = minDt * 0.9; // Bezpečnostní faktor 0.9 pro numerický klid
  }

  void updateMap(WorkerUpdateMapCommand cmd) {
    if (size != cmd.size) {
      size = cmd.size;
      nextTemps = Float64List(size * size);
    }
    temps = cmd.temps;
    materials = cmd.materials;
    zoneIds = cmd.zoneIds;
    zoneTargetTemps = cmd.zoneTargetTemps;

    // Obnovit jen ty, co přišly z UI, zbytek nechat běžet
    for (final entry in cmd.zoneSatisfaction.entries) {
      zoneSatisfaction[entry.key] = entry.value;
    }

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
    // Fyzikální práh kroku odvozený z CFL podmínky materiálových parametrů.
    final double dtThreshold = _dtThreshold;

    // Pokud uživatel nasadí obrovské zrychlení (Den/s, Týden/s), snížíme zátěž na frame (maxStepsPerFrame),
    // tím se rychlost de-facto limituje maximální kapacitou procesoru, ale nezačne lagovat!
    // Procesor se neutopí ve smyčce. Omezíme počet cyklů na jeden tick (např. 1500 na 33ms).
    final int maxStepsPerFrame = 1500;

    int steps = (cmd.virtualDtSec / dtThreshold).ceil();
    if (steps > maxStepsPerFrame) {
      steps = maxStepsPerFrame;
    }
    // stepDt nesmí překročit dtThreshold — jinak explicitní schéma diverguje do NaN.
    // Pokud maxStepsPerFrame nestačí, zkrátíme simulovaný čas framu (vizuálně pomalejší
    // při extrémních násobcích, ale numericky stabilní).
    final double effectiveVirtualDt =
        (steps * dtThreshold).clamp(0.0, cmd.virtualDtSec);
    final double stepDt = effectiveVirtualDt / steps;
    // Reálný čas na jeden sub-krok — nezávislý na timeMultiplier.
    // virtualDtSec / timeMultiplier ≈ 0.033s (délka reálného framu),
    // děleno počtem sub-kroků dává reálný čas každé iterace.
    final double realStepDt = effectiveVirtualDt / (cmd.timeMultiplier * steps);

    final int length = size * size;

    // 1D pole teplot zapnutých radiátorů (Proporcionální řízení)
    // 0.0 znamená vypnutý radiátor (běžná chladnoucí hmota)
    final Float64List heaterTargetTemps = Float64List(length);

    for (int step = 0; step < steps; step++) {
      // 1. Zjistit, které radiátory běží a na kolik stupňů (O(n) lookup)
      heaterTargetTemps.fillRange(0, length, 0.0); // Vynulovat

      // Procházíme všechny zóny, ve kterých se nachází alespoň jeden radiátor
      for (int zId in zoneHeaters.keys) {
        if (zId == 0) continue;
        final double target = zoneTargetTemps[zId] ?? 22.0;

        final tList = zoneThermostats[zId];
        if (tList != null && tList.isNotEmpty) {
          // Pro zjednodušení bereme první termostat v zóně
          final double currentZoneTemp = temps[tList.first];
          final double diff = target - currentZoneTemp;

          // Proporcionální regulátor (P-Controller) laděný na přesné udržování
          // Abychom zamezili přetopení (overshootku), nepustíme do topení rovnou 40°C,
          // když chybí jen desetinka stupně.
          // Výchozím bodem je samotná cílová teplota (např. 22°C), od které se odpíchneme rasantní křivkou nahoru.
          if (diff > 0.0) {
            // Např. chybí 2°C -> 22 + 60 = 82°C (Max limitováno na 60°C).
            // Chybí 0.5°C -> 22 + 15 = 37°C.
            // Chybí 0.1°C -> 22 + 3 = 25°C.
            double heaterTemp = target + (diff * 30.0);
            if (heaterTemp > 60.0) heaterTemp = 60.0; // Maximální výkon kotle

            final hList = zoneHeaters[zId];
            if (hList != null) {
              for (int hIdx in hList) {
                heaterTargetTemps[hIdx] = heaterTemp;
              }
            }
          }

          // Výpočet metriky spokojenosti (0.0 to 1.0)
          // Rychlost poklesu spokojenosti je závislá na odchylce:
          // tolerance je 0.5 stupně, kde je člověk "maximálně spokojen"
          double currentSatisfaction = zoneSatisfaction[zId] ?? 1.0;
          final double absoluteError = diff.abs();

          if (absoluteError <= 0.5) {
            // Regenerace spokojenosti: 0.5% za reálnou vteřinu (nezávisle na rychlosti simulace)
            currentSatisfaction += realStepDt * 0.005;
          } else {
            // Penalizace: chyba 3°C propálí ~10% za reálnou minutu (nezávisle na rychlosti simulace)
            currentSatisfaction -= realStepDt * (absoluteError * 0.0003);
          }

          if (currentSatisfaction > 1.0) currentSatisfaction = 1.0;
          if (currentSatisfaction < 0.0) currentSatisfaction = 0.0;

          zoneSatisfaction[zId] = currentSatisfaction;
        }
      }

      // Reset okamžitého výkonu na začátku každého sub-kroku (průměruje se přes frame)
      if (step == 0) zoneInstantPower.clear();

      // 2. Samotná zploštěná 1D fyzika (mnohem rychlejší Cache access)
      for (int i = 0; i < length; i++) {
        final double currentTemp = temps[i];
        final int matIndex = materials[i];

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
          // Hranice gridu = kontakt s venkovním prostředím.
          // Použijeme myCond přímo (bez capu), aby vzduch na okraji rychle přebíral
          // venkovní teplotu — konzistentní s interní difúzí.
          // Stabilita zaručena dtThreshold z CFL podmínky.
          totalFlux += (cmd.outdoorTemp - currentTemp) * myCond;
        }

        // Doleva (-1)
        if (x - 1 >= 0) {
          final double neighborCond = conds[materials[i - 1]];
          final double c = (myCond < neighborCond) ? myCond : neighborCond;
          totalFlux += (temps[i - 1] - currentTemp) * c;
        } else {
          totalFlux += (cmd.outdoorTemp - currentTemp) * myCond;
        }

        // Dolů (+size)
        if (y + 1 < size) {
          final double neighborCond = conds[materials[i + size]];
          final double c = (myCond < neighborCond) ? myCond : neighborCond;
          totalFlux += (temps[i + size] - currentTemp) * c;
        } else {
          totalFlux += (cmd.outdoorTemp - currentTemp) * myCond;
        }

        // Nahoru (-size)
        if (y - 1 >= 0) {
          final double neighborCond = conds[materials[i - size]];
          final double c = (myCond < neighborCond) ? myCond : neighborCond;
          totalFlux += (temps[i - size] - currentTemp) * c;
        } else {
          totalFlux += (cmd.outdoorTemp - currentTemp) * myCond;
        }

        // Zdroj tepla pro radiátor: fyzikálně korektní vstup energie přes
        // proporcionální tok do tepelného rezervoáru (namísto tvrdého clampování teploty).
        // Energie vstupuje postupně — zachování energie je zachováno.
        // Stabilita: heaterSourceConductance * stepDt / myCap = 500 * 2 / 10000 = 0.1 < 1 ✓
        if (matIndex == gm.MaterialType.heater.index) {
          final double targetHeaterTemp = heaterTargetTemps[i];
          if (targetHeaterTemp > 0.0) {
            final double power =
                heaterSourceConductance * (targetHeaterTemp - currentTemp);
            totalFlux += power;

            // Akumulace energie a výkonu per zóna — pouze kladný výkon.
            // Záporný power nastane když je currentTemp > targetHeaterTemp
            // (radiátor se chladí zpět — fyzikálně správné, ale není to spotřeba energie).
            if (power > 0.0) {
              final int zId = zoneIds[i];
              if (zId != 0) {
                zoneEnergyConsumed[zId] =
                    (zoneEnergyConsumed[zId] ?? 0.0) + power * stepDt;
                zoneInstantPower[zId] =
                    (zoneInstantPower[zId] ?? 0.0) + power;
              }
            }
          }
          // Pokud je targetHeaterTemp == 0.0, radiátor je vypnutý a přirozeně chladne difúzí.
        }

        // Fyzikální výpočet posunu tepla.
        nextTemps[i] = currentTemp + (totalFlux * stepDt / myCap);
      }

      // Pointer Swap (Žádný foreach pro kopírování přes celou paměť)
      final Float64List tmp = temps;
      temps = nextTemps;
      nextTemps = tmp;
    }

    // Vrátíme zkopírovaná pole pro UI
    return WorkerResponse(
      Float64List.fromList(temps),
      Map<int, double>.from(zoneSatisfaction),
      Map<int, double>.from(zoneEnergyConsumed),
      Map<int, double>.from(zoneInstantPower),
    );
  }
}
