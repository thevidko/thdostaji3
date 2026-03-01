import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/grid_model.dart';
import '../models/grid_model.dart' as gm; // Alias for MaterialType

class SimulationIsolateData {
  final int size;
  final double virtualDt;
  final double outdoorTemp;
  final List<List<double>> temps;
  final List<List<gm.MaterialType>> materials;
  final List<List<int>> zoneIds;
  final Map<int, double> zoneTargetTemps;

  SimulationIsolateData({
    required this.size,
    required this.virtualDt,
    required this.outdoorTemp,
    required this.temps,
    required this.materials,
    required this.zoneIds,
    required this.zoneTargetTemps,
  });
}

// Výpočet oddělený do nezávislého procesorového vlákna (Isolate)
List<List<double>> runSimulationIsolate(SimulationIsolateData data) {
  final int size = data.size;
  final List<List<double>> temps = data.temps;
  final List<List<gm.MaterialType>> materials = data.materials;
  final List<List<int>> zoneIds = data.zoneIds;
  final Map<int, double> zoneTargetTemps = data.zoneTargetTemps;
  final double outdoorTemp = data.outdoorTemp;

  // Předvytvoření paměťového bufferu pouze jednou na celý balík výpočtů (Ušetří miliony alokací a odtíží Garbage Collector)
  final List<List<double>> nextTemps = List.generate(
    size,
    (y) => List.filled(size, 0.0),
  );

  // Předpočítané statické pole vodivostí (k) podle Enum indexů
  final List<double> conds = List.filled(gm.MaterialType.values.length, 0.0);
  conds[gm.MaterialType.air.index] = 50.0;
  conds[gm.MaterialType.floor.index] = 20.0;
  conds[gm.MaterialType.wall.index] =
      0.5; // Zvýšeno z 0.2 (cihla trochu lépe propouští teplo mezi místnostmi)
  conds[gm.MaterialType.insulation.index] = 0.01;
  conds[gm.MaterialType.heater.index] = 5.0;
  conds[gm.MaterialType.thermostat.index] =
      50.0; // Změněno z 5.0 na 50.0 pro bleskové převzetí teploty

  // Předpočítané pole kapacit (c)
  final double m = 1000.0;
  final List<double> caps = List.filled(gm.MaterialType.values.length, 0.0);
  caps[gm.MaterialType.air.index] = 1.0 * m;
  caps[gm.MaterialType.floor.index] = 5.0 * m;
  caps[gm.MaterialType.wall.index] =
      15.0 *
      m; // Výrazně sníženo z 50.0 (zdi zachytávají méně tepla a propustí ho dál do chodeb)
  caps[gm.MaterialType.insulation.index] = 5.0 * m;
  caps[gm.MaterialType.heater.index] = 10.0 * m;
  caps[gm.MaterialType.thermostat.index] =
      0.5 * m; // Extrémně snížená tepelná kapacita

  // Matematická pojistka CFL
  const double dtThreshold = 2.0;
  final int steps = (data.virtualDt / dtThreshold).ceil();
  final double stepDt = data.virtualDt / steps;

  for (int step = 0; step < steps; step++) {
    // 1. Nejprve určíme zapnuté radiátory (před samotnou buněčnou iterací)
    final List<List<bool>> heatersOn = List.generate(
      size,
      (_) => List.filled(size, false),
    );
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        if (materials[y][x] == gm.MaterialType.heater) {
          final int zId = zoneIds[y][x];
          if (zId != 0) {
            final double target = zoneTargetTemps[zId] ?? 20.0;
            bool needHeat = false;
            for (int ty = 0; ty < size; ty++) {
              for (int tx = 0; tx < size; tx++) {
                if (materials[ty][tx] == gm.MaterialType.thermostat &&
                    zoneIds[ty][tx] == zId) {
                  if (temps[ty][tx] < target) {
                    needHeat = true;
                    break;
                  }
                }
              }
              if (needHeat) break;
            }
            heatersOn[y][x] = needHeat;
          }
        }
      }
    }

    // 2. Fyzikální výpočet vodivostí a posunu teplot
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final double currentTemp = temps[y][x];
        final int matIndex = materials[y][x].index;

        if (materials[y][x] == gm.MaterialType.heater && heatersOn[y][x]) {
          nextTemps[y][x] = 60.0;
          continue;
        }

        final double myCond = conds[matIndex];
        final double myCap = caps[matIndex];
        double totalFlux = 0.0;

        // Rozbalené Inlining cykly (Ušetříme stovky milionů uzavírání funkcí / iterací)

        // Soused Doprava (+)
        if (x + 1 < size) {
          final double neighborCond = conds[materials[y][x + 1].index];
          final double c = (myCond < neighborCond) ? myCond : neighborCond;
          totalFlux += (temps[y][x + 1] - currentTemp) * c;
        } else {
          totalFlux +=
              (outdoorTemp - currentTemp) * ((myCond < 1.0) ? myCond : 1.0);
        }

        // Soused Doleva (-)
        if (x - 1 >= 0) {
          final double neighborCond = conds[materials[y][x - 1].index];
          final double c = (myCond < neighborCond) ? myCond : neighborCond;
          totalFlux += (temps[y][x - 1] - currentTemp) * c;
        } else {
          totalFlux +=
              (outdoorTemp - currentTemp) * ((myCond < 1.0) ? myCond : 1.0);
        }

        // Soused Dolů (+)
        if (y + 1 < size) {
          final double neighborCond = conds[materials[y + 1][x].index];
          final double c = (myCond < neighborCond) ? myCond : neighborCond;
          totalFlux += (temps[y + 1][x] - currentTemp) * c;
        } else {
          totalFlux +=
              (outdoorTemp - currentTemp) * ((myCond < 1.0) ? myCond : 1.0);
        }

        // Soused Nahorů (-)
        if (y - 1 >= 0) {
          final double neighborCond = conds[materials[y - 1][x].index];
          final double c = (myCond < neighborCond) ? myCond : neighborCond;
          totalFlux += (temps[y - 1][x] - currentTemp) * c;
        } else {
          totalFlux +=
              (outdoorTemp - currentTemp) * ((myCond < 1.0) ? myCond : 1.0);
        }

        nextTemps[y][x] = currentTemp + (totalFlux * stepDt / myCap);
      }
    }

    // 3. Kopírování mezivýpočtu z recyklovaného bufferu zpět do hlavní paměti matice
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        temps[y][x] = nextTemps[y][x];
      }
    }
  }

  return temps;
}

class SimulationEngine extends ChangeNotifier {
  void updateGridModel(GridModel newModel) {
    gridModel = newModel;
  }

  GridModel gridModel;
  Timer? _timer;
  bool _isRunning = false;

  double _outdoorTemp = 0.0;

  // Proměnné pro simulaci času
  DateTime _currentTime = DateTime(2025, 1, 1, 8, 0); // Výchozí čas 8:00
  int _timeMultiplier = 60; // 1 min/s jako výchozí

  bool get isRunning => _isRunning;
  double get outdoorTemp => _outdoorTemp;
  DateTime get currentTime => _currentTime;
  int get timeMultiplier => _timeMultiplier;

  SimulationEngine(this.gridModel);

  void setOutdoorTemp(double temp) {
    _outdoorTemp = temp;
    notifyListeners();
  }

  void setTimeMultiplier(int multiplier) {
    _timeMultiplier = multiplier;
    notifyListeners();
  }

  void toggleSimulation() {
    if (_isRunning) {
      stop();
    } else {
      start();
    }
  }

  bool _isComputing = false;

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    notifyListeners();

    // Spustíme timer, např. 30x za sekundu
    _timer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      // Ochrana: pokud Isolate ještě nedopočítal předchozí frame, počkáme (zabrání frontám)
      if (_isComputing) return;

      // Reálný uplynulý čas 0.033 s * násobič času
      final double virtualDtSec = 0.033 * _timeMultiplier;

      // Posun simulovaného času
      _currentTime = _currentTime.add(
        Duration(milliseconds: 33 * _timeMultiplier),
      );

      _isComputing = true;

      // Připravíme immutable kopii dat pro odeslání do nezávislého vlákna
      // Flutter `compute` si serializuje objekt automaticky jako deep copy při průjezdu přes Porty Isolate
      final isolateData = SimulationIsolateData(
        size: gridModel.gridSize,
        virtualDt: virtualDtSec,
        outdoorTemp: _outdoorTemp,
        temps: gridModel.temperatures,
        materials: gridModel.materials,
        zoneIds: gridModel.zoneIds,
        zoneTargetTemps: Map<int, double>.from(gridModel.zoneTargetTemps),
      );

      // Spuštění výpočtu asynchronně mimo UI vlákno
      compute(runSimulationIsolate, isolateData)
          .then((newTemps) {
            _isComputing = false;

            // Pokud uživatel mezitím simulaci zastavil, nepotřebujeme výsledek propisovat
            if (!_isRunning) return;

            // Zapíšeme finální teploty zpět do modelu
            gridModel.updateTemperatures(newTemps);

            // Notifikujeme UI o změně (překreslení domku i hodin zaráz)
            gridModel.notifyListeners();
            notifyListeners();
          })
          .catchError((e) {
            _isComputing = false;
            debugPrint("Simulation isolate error: \$e");
          });
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    _isComputing = false;
    notifyListeners();
  }
}
