import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/grid_model.dart';

import 'dart:isolate';
import 'simulation_worker.dart';

class SimulationEngine extends ChangeNotifier {
  GridModel gridModel;
  Timer? _timer;
  bool _isRunning = false;

  double _outdoorTemp = 0.0;
  DateTime _currentTime = DateTime(2025, 1, 1, 8, 0); // Výchozí čas 8:00
  int _timeMultiplier = 60; // 1 min/s jako výchozí

  bool get isRunning => _isRunning;
  double get outdoorTemp => _outdoorTemp;
  DateTime get currentTime => _currentTime;
  int get timeMultiplier => _timeMultiplier;

  // Persistent Isolate
  Isolate? _workerIsolate;
  SendPort? _workerSendPort;
  bool _isWorkerReady = false;
  bool _isComputing = false;

  bool _isUpdatingFromWorker = false;

  SimulationEngine(this.gridModel) {
    gridModel.addListener(_onGridModelChanged);
    _initWorker();
  }

  void _onGridModelChanged() {
    if (_isUpdatingFromWorker) return;
    _sendUpdateMapToWorker();
  }

  @override
  void dispose() {
    stop();
    gridModel.removeListener(_onGridModelChanged);
    _workerIsolate?.kill(priority: Isolate.immediate);
    super.dispose();
  }

  void updateGridModel(GridModel newModel) {
    gridModel.removeListener(_onGridModelChanged);
    gridModel = newModel;
    gridModel.addListener(_onGridModelChanged);
    _sendUpdateMapToWorker();
  }

  Float64List _exportTemps1D() {
    final size = gridModel.gridSize;
    final flat = Float64List(size * size);
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        flat[y * size + x] = gridModel.temperatures[y][x];
      }
    }
    return flat;
  }

  Uint8List _exportMaterials1D() {
    final size = gridModel.gridSize;
    final flat = Uint8List(size * size);
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        flat[y * size + x] = gridModel.materials[y][x].index;
      }
    }
    return flat;
  }

  Int32List _exportZoneIds1D() {
    final size = gridModel.gridSize;
    final flat = Int32List(size * size);
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        flat[y * size + x] = gridModel.zoneIds[y][x];
      }
    }
    return flat;
  }

  void _sendUpdateMapToWorker() {
    if (!_isWorkerReady || _workerSendPort == null) return;
    _workerSendPort!.send(
      WorkerUpdateMapCommand(
        size: gridModel.gridSize,
        temps: _exportTemps1D(),
        materials: _exportMaterials1D(),
        zoneIds: _exportZoneIds1D(),
        zoneTargetTemps: Map<int, double>.from(gridModel.zoneTargetTemps),
        zoneSatisfaction: Map<int, double>.from(gridModel.zoneSatisfaction),
      ),
    );
  }

  Future<void> _initWorker() async {
    if (_workerIsolate != null) return;

    final receivePort = ReceivePort();

    final initCmd = WorkerInitCommand(
      sendPort: receivePort.sendPort,
      size: gridModel.gridSize,
      initialTemps: _exportTemps1D(),
      materials: _exportMaterials1D(),
      zoneIds: _exportZoneIds1D(),
      zoneTargetTemps: Map<int, double>.from(gridModel.zoneTargetTemps),
    );

    _workerIsolate = await Isolate.spawn(runSimulationWorker, initCmd);

    receivePort.listen((message) {
      if (message is SendPort) {
        _workerSendPort = message;
        _isWorkerReady = true;
      } else if (message is WorkerResponse) {
        _handleWorkerResponse(message);
      }
    });
  }

  void _handleWorkerResponse(WorkerResponse response) {
    _isComputing = false;

    if (!_isRunning) return;

    // Zapíšeme 1D pole zpět do 2D UI modelu
    final size = gridModel.gridSize;
    final List<List<double>> temps2D = List.generate(
      size,
      (y) => List.generate(size, (x) => response.temps[y * size + x]),
    );

    _isUpdatingFromWorker = true;
    gridModel.updateTemperatures(temps2D);
    gridModel.updateZoneSatisfactions(response.zoneSatisfaction);
    gridModel.notifyListeners();
    _isUpdatingFromWorker = false;

    notifyListeners();
  }

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

  double _calculateOutdoorTemperature(DateTime time) {
    const double yearlyMean = 10.0;
    const double yearlyAmplitude = 15.0;

    final int dayOfYear = time.difference(DateTime(time.year, 1, 1)).inDays;
    final double yearlyAngle =
        (dayOfYear / 365.0) * 2 * math.pi - (math.pi / 2);
    final double seasonalBaseTemp =
        yearlyMean + yearlyAmplitude * math.sin(yearlyAngle);

    const double dailyAmplitude = 4.0;
    final double hourFraction = time.hour + (time.minute / 60.0);
    final double dailyAngle =
        ((hourFraction - 4) / 24.0) * 2 * math.pi - (math.pi / 2);
    final double currentTemp =
        seasonalBaseTemp + dailyAmplitude * math.sin(dailyAngle);

    return currentTemp;
  }

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    notifyListeners();

    _initWorker().then((_) {
      if (!_isRunning) return;

      _timer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
        if (!_isWorkerReady) return;
        if (_isComputing) return;

        final double virtualDtSec = 0.033 * _timeMultiplier;

        _currentTime = _currentTime.add(
          Duration(milliseconds: (33 * _timeMultiplier).toInt()),
        );

        _outdoorTemp = _calculateOutdoorTemperature(_currentTime);

        _isComputing = true;

        _workerSendPort!.send(
          WorkerStepCommand(
            virtualDtSec: virtualDtSec,
            timeMultiplier: _timeMultiplier,
            outdoorTemp: _outdoorTemp,
          ),
        );
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
