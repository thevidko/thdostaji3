import 'dart:async';
import 'package:flutter/material.dart';
import '../models/grid_model.dart';
import '../models/grid_model.dart' as gm; // Alias for MaterialType

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

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    notifyListeners();

    // Spustíme timer, např. 30x za sekundu
    _timer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      // Reálný uplynulý čas 0.033 s * násobič času
      final double virtualDtSec = 0.033 * _timeMultiplier;

      // Posun simulovaného času
      _currentTime = _currentTime.add(
        Duration(milliseconds: 33 * _timeMultiplier),
      );

      // Zde v budoucnu budeme volat logiku pro počasí a absenci osob:
      // _updateEnvironment();

      // Zpracujeme fyziku podle uplynulého virtuálního času
      _stepVirtualTime(virtualDtSec);

      // Notifikujeme UI o změně (překreslení)
      // Zde budeme volat notifyListeners() na GridModelu explicitně,
      // protože GridModel sám o sobě neví že se změnila data v poli (pokud do něj saháme přímo).
      gridModel.notifyListeners();
      notifyListeners(); // Aby se překreslil i čas v UI
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    notifyListeners();
  }

  // Zpracování fyziky pro uběhlý simulovaný čas t_virtual.
  // Pro zachování matematické stability využíváme maximální povolený fyzikální krok (dtThreshold),
  // a celkový uplynulý čas tak sekáme na dílčí mikro-kroky.
  void _stepVirtualTime(double virtualDt) {
    const double dtThreshold =
        2.0; // Stabilní krok díky novému poměru (zabrání vygenerování NaN u vzduchu)
    final int steps = (virtualDt / dtThreshold).ceil();
    final double stepDt = virtualDt / steps;

    for (int i = 0; i < steps; i++) {
      _computeHeatTransfer(stepDt);
    }
  }

  // Jeden fyzikální mikro-krok šíření tepla (s tepelnou kapacitou a vodivostí)
  void _computeHeatTransfer(double dt) {
    final int size = gridModel.gridSize;
    final temps = gridModel.temperatures;
    final materials = gridModel.materials;

    // Double buffering pro teploty
    List<List<double>> nextTemps = List.generate(
      size,
      (y) => List.from(temps[y]),
    );

    // Iterace přes celou mřížku
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final currentTemp = temps[y][x];
        final material = materials[y][x];

        // 1. Zpracování Zdroje tepla
        if (material == gm.MaterialType.heater) {
          bool shouldHeat = _shouldHeaterTurnOn(x, y, temps);
          if (shouldHeat) {
            nextTemps[y][x] = 60.0; // Heater topí na fixní teplotu
            continue;
          }
        }

        // 2. Termostat (nemění svou teplotu jinak než okolím, nebo má vlastní elektroniku?
        // Považujeme ho za materiál s vlastnostmi (plast/kov).

        // 3. Fyzikální výpočet (Vodivost + Kapacita)
        // Q = součet toků od sousedů
        // Tok (Flux) = (T_neighbor - T_current) * conductivity_interface
        // DeltaT = Q / capacity

        double totalFlux = 0.0;
        final myConductivity = _getConductivity(material);
        final myCapacity = _getCapacity(material);

        void processNeighbor(int nx, int ny) {
          double neighborTemp;
          double neighborConductivity;

          if (nx >= 0 && nx < size && ny >= 0 && ny < size) {
            neighborTemp = temps[ny][nx];
            neighborConductivity = _getConductivity(materials[ny][nx]);
          } else {
            neighborTemp = _outdoorTemp;
            neighborConductivity = 1.0; // Vzduch venku
          }

          // Efektivní vodivost rozhraní
          // Použijeme minimum. Zabrání to matematické chybě a zároveň respektuje fyzikální maximum
          // bariéry (např. Vzduch a Zeď -> omezí se to zdí. Vzduch a Vzduch -> povalí to na plný výkon konvekce).
          double interfaceConductivity;
          if (myConductivity == 0 || neighborConductivity == 0) {
            interfaceConductivity = 0;
          } else {
            interfaceConductivity = myConductivity < neighborConductivity
                ? myConductivity
                : neighborConductivity;
          }

          // Tok energie
          totalFlux += (neighborTemp - currentTemp) * interfaceConductivity;
        }

        processNeighbor(x + 1, y);
        processNeighbor(x - 1, y);
        processNeighbor(x, y + 1);
        processNeighbor(x, y - 1);

        // Změna teploty (s konkrétním časovým dílkem dt)
        nextTemps[y][x] = currentTemp + (totalFlux * dt / myCapacity);
      }
    }

    // Aplikujeme vypočítané teploty zpět do modelu
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        temps[y][x] = nextTemps[y][x];
      }
    }
  }

  // Tepelná vodivost (k) - schopnost materiálu vést teplo
  double _getConductivity(gm.MaterialType type) {
    switch (type) {
      case gm.MaterialType.air:
        return 50.0; // Venkovní vzduch (vítr) - okamžité odsátí tepla
      case gm.MaterialType.floor:
        return 20.0; // Vnitřní prostor místnosti (vzduch uvnitř) - silná konvekce
      case gm.MaterialType.wall:
        return 0.2; // Zeď vede pomalu
      case gm.MaterialType.insulation:
        return 0.01; // Izolace je nepropustná pečeť
      case gm.MaterialType.heater:
      case gm.MaterialType.thermostat:
        return 5.0; // Solidní kovový vodič
    }
  }

  // Tepelná kapacita (c) - setrvačnost (jak těžké je změnit teplotu)
  double _getCapacity(gm.MaterialType type) {
    const double m = 1000.0; // Kapacitní násobič pro zamezení nestabilitě
    switch (type) {
      case gm.MaterialType.air:
        return 1.0 *
            m; // Venkovní vzduch - chceme, aby hned přebral venkovní teplotu bez setrvačnosti
      case gm.MaterialType.floor:
        return 5.0 *
            m; // Vnitřní vzduch je rychlý, ohřev a ochlazení běží svižně (stabilita 5000 / 80 = 62)
      case gm.MaterialType.wall:
        return 50.0 * m; // Zeď má ohromnou setrvačnost, trvá dny ji vyhřát
      case gm.MaterialType.insulation:
        return 5.0 * m; // Izolace je lehká
      case gm.MaterialType.heater:
      case gm.MaterialType.thermostat:
        return 10.0 * m; // Kov má střední kapacitu
    }
  }

  // Pomocná metoda: Zjistí, zda má topení na dané pozici topit
  bool _shouldHeaterTurnOn(int x, int y, List<List<double>> temps) {
    final int myZoneId = gridModel.getZoneId(x, y);

    // Pokud topení není v zóně, netopí (nebo můžeme nechat globální logiku, ale zóny jsou lepší)
    if (myZoneId == 0) return false;

    final double targetTemp = gridModel.getZoneTargetTemp(myZoneId);
    bool needHeat = false;

    // Projdeme celou mřížku a hledáme termostaty ve STEJNÉ zóně
    // (Optimalizace: GridModel by mohl mít seznam termostatů pro každou zónu, ale pro 50x50 to stačí takto)
    for (int ty = 0; ty < gridModel.gridSize; ty++) {
      for (int tx = 0; tx < gridModel.gridSize; tx++) {
        if (gridModel.materials[ty][tx] == gm.MaterialType.thermostat) {
          if (gridModel.getZoneId(tx, ty) == myZoneId) {
            // Našli jsme termostat ve stejné zóně
            if (temps[ty][tx] < targetTemp) {
              needHeat = true;
              break; // Stačí jeden termostat, který hlásí zimu
            }
          }
        }
      }
      if (needHeat) break;
    }

    return needHeat;
  }
}
