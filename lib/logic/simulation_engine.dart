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

  // Rychlost simulace (kolik korků za sekundu, nebo speed factor)
  // Zde implementujeme "Speed Factor" jako počet updatů za tick timeru,
  // nebo zkrácení intervalu timeru. Pro plynulost UI je lepší fixní timer
  // (např. 60 FPS = 16ms) a v něm dělat N kroků simulace.
  int _speedFactor = 1;

  double _outdoorTemp = 0.0;

  // Cílová teplota pro termostaty
  double _targetTemp = 22.0;

  bool get isRunning => _isRunning;
  int get speedFactor => _speedFactor;
  double get outdoorTemp => _outdoorTemp;
  double get targetTemp => _targetTemp;

  SimulationEngine(this.gridModel);

  void setSpeedFactor(int factor) {
    _speedFactor = factor.clamp(1, 100);
    notifyListeners();
  }

  void setOutdoorTemp(double temp) {
    _outdoorTemp = temp;
    notifyListeners();
  }

  void setTargetTemp(double temp) {
    _targetTemp = temp;
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
      // V každém ticku provedeme _speedFactor kroků simulace
      for (int i = 0; i < _speedFactor; i++) {
        _step();
      }
      // Notifikujeme UI o změně (překreslení)
      // Pozor: Pokud je simulace velmi rychlá, může notifyListeners() zahltit UI.
      // GridModel.notifyListeners() voláme uvnitř _step jen pokud se něco změnilo,
      // nebo můžeme volat notifyListeners() jen jednou na konci timeru.
      // Zde budeme volat notifyListeners() na GridModelu explicitně,
      // protože GridModel sám o sobě neví že se změnila data v poli (pokud do něj saháme přímo).
      gridModel.notifyListeners();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    notifyListeners();
  }

  // Jeden krok fyzikální simulace (s tepelnou kapacitou a vodivostí)
  void _step() {
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
          bool shouldHeat = _checkThermostats(temps, materials, size);
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

          // Efektivní vodivost rozhraní (harmonický průměr nebo min, nebo průměr)
          // Pro zjednodušení použijeme průměr, nebo pokud je jeden izolant, tak izoluje.
          // Fyzikálně přesnější pro sériový odpor: 2 / (1/k1 + 1/k2)
          double interfaceConductivity;
          if (myConductivity == 0 || neighborConductivity == 0) {
            interfaceConductivity = 0;
          } else {
            interfaceConductivity =
                (2 * myConductivity * neighborConductivity) /
                (myConductivity + neighborConductivity);
          }

          // Tok energie
          totalFlux += (neighborTemp - currentTemp) * interfaceConductivity;
        }

        processNeighbor(x + 1, y);
        processNeighbor(x - 1, y);
        processNeighbor(x, y + 1);
        processNeighbor(x, y - 1);

        // Změna teploty
        // Použijeme časový krok (dt) pro stabilitu simulace.
        // Podmínka stability (CFL): součet (k * dt / C) pro všechny sousedy musí být < 1.
        // Pro vzduch: k=0.8, C=1.0 -> k/C = 0.8. Sousedů je 4 -> suma = 3.2.
        // Proto musí být dt < 1/3.2 ~= 0.31.
        const double dt = 0.2;
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
      case gm.MaterialType.floor:
        return 0.8; // Vzduch a podlaha vedou teplo stejně (pro zjednodušení)
      case gm.MaterialType.wall:
        return 0.1; // Zeď vede špatně
      case gm.MaterialType.insulation:
        return 0.01; // Izolace vede velmi špatně
      case gm.MaterialType.heater:
      case gm.MaterialType.thermostat:
        return 2.0; // Kov vede velmi dobře
    }
  }

  // Tepelná kapacita (c) - setrvačnost (jak těžké je změnit teplotu)
  double _getCapacity(gm.MaterialType type) {
    switch (type) {
      case gm.MaterialType.air:
      case gm.MaterialType.floor:
        return 1.0; // Vzduch a podlaha mají malou setrvačnost
      case gm.MaterialType.wall:
        return 50.0; // Zeď má velkou setrvačnost (cihla)
      case gm.MaterialType.insulation:
        return 5.0; // Izolace je lehká (vata/polystyren), malá kapacita
      case gm.MaterialType.heater:
      case gm.MaterialType.thermostat:
        return 10.0; // Kov má střední kapacitu
    }
  }

  // Pomocná metoda: Zkontroluje, zda má topit (alespoň jeden termostat hlásí zimu)
  bool _checkThermostats(
    List<List<double>> temps,
    List<List<gm.MaterialType>> materials,
    int size,
  ) {
    bool thermostatFound = false;
    bool needHeat = false;

    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        if (materials[y][x] == gm.MaterialType.thermostat) {
          thermostatFound = true;
          if (temps[y][x] < _targetTemp) {
            needHeat = true;
          }
        }
      }
    }

    // Pokud není termostat, netopíme (nebo topíme pořád? Bezpečnější je netopit).
    if (!thermostatFound) return false;

    return needHeat;
  }
}
