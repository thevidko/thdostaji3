import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MaterialType {
  air, // 0
  wall, // 1
  heater, // 2
  thermostat, // 3
  insulation, // 4
  floor, // 5
}

// Rozšíření pro MaterialType, abychom mohli snadno získat barvy
extension MaterialTypeExtension on MaterialType {
  Color get color {
    switch (this) {
      case MaterialType.air:
        return Colors.lightBlue.shade50; // Světle modrá pro vzduch
      case MaterialType.wall:
        return Colors.brown.shade400; // Hnědá pro zeď
      case MaterialType.heater:
        return Colors
            .grey
            .shade400; // Šedá pro vypnuté topení (zčervená teplem)
      case MaterialType.thermostat:
        return Colors.green.shade400; // Zelená pro termostat
      case MaterialType.insulation:
        return Colors.purple.shade300; // Fialová pro izolaci
      case MaterialType.floor:
        return Colors.brown.shade200; // Světle hnědá pro podlahu
    }
  }
}

class GridModel extends ChangeNotifier {
  int _gridSize;
  // Matice pro teploty
  List<List<double>> _temperatures;
  // Matice pro typy materiálů
  List<List<MaterialType>> _materials;
  // Matice pro ID zón (0 = žádná zóna, 1+ = číslo zóny)
  List<List<int>> _zoneIds;
  // Cílové teploty pro jednotlivé zóny
  final Map<int, double> _zoneTargetTemps = {};

  GridModel(int size)
    : _gridSize = size,
      _temperatures = List.generate(size, (_) => List.filled(size, 20.0)),
      _materials = List.generate(
        size,
        (_) => List.filled(size, MaterialType.air),
      ),
      _zoneIds = List.generate(size, (_) => List.filled(size, 0));

  int get gridSize => _gridSize;
  List<List<double>> get temperatures => _temperatures;
  List<List<MaterialType>> get materials => _materials;
  List<List<int>> get zoneIds => _zoneIds;

  double getZoneTargetTemp(int zoneId) {
    if (zoneId <= 0) return 22.0; // Default
    return _zoneTargetTemps[zoneId] ?? 22.0;
  }

  void setZoneTargetTemp(int zoneId, double temp) {
    if (zoneId > 0) {
      _zoneTargetTemps[zoneId] = temp;
      notifyListeners();
    }
  }

  int getZoneId(int x, int y) {
    if (x >= 0 && x < _gridSize && y >= 0 && y < _gridSize) {
      return _zoneIds[y][x];
    }
    return 0;
  }

  // Přepočítá zóny na základě propojení materiálů (Connected Components)
  // Zóna je tvořena spojitými buňkami typu: Floor, Heater, Thermostat.
  void recalculateZones() {
    // Reset zón
    for (int y = 0; y < _gridSize; y++) {
      for (int x = 0; x < _gridSize; x++) {
        _zoneIds[y][x] = 0;
      }
    }

    int nextZoneId = 1;
    final Set<int> activeZones = {};

    for (int y = 0; y < _gridSize; y++) {
      for (int x = 0; x < _gridSize; x++) {
        final type = _materials[y][x];
        // Pokud je to materiál, který tvoří zónu, a ještě nemá ID
        if (_isZoneMaterial(type) && _zoneIds[y][x] == 0) {
          _floodFillZone(x, y, nextZoneId);
          activeZones.add(nextZoneId);
          nextZoneId++;
        }
      }
    }

    // Vyčistit nastavení pro neexistující zóny (volitelné, garbage collection)
    _zoneTargetTemps.removeWhere((key, _) => !activeZones.contains(key));
  }

  bool _isZoneMaterial(MaterialType type) {
    return type == MaterialType.floor ||
        type == MaterialType.heater ||
        type == MaterialType.thermostat;
  }

  void _floodFillZone(int startX, int startY, int zoneId) {
    final List<({int x, int y})> queue = [];
    queue.add((x: startX, y: startY));
    _zoneIds[startY][startX] = zoneId;

    while (queue.isNotEmpty) {
      final point = queue.removeLast();
      final px = point.x;
      final py = point.y;

      void checkNeighbor(int nx, int ny) {
        if (nx >= 0 && nx < _gridSize && ny >= 0 && ny < _gridSize) {
          if (_zoneIds[ny][nx] == 0 && _isZoneMaterial(_materials[ny][nx])) {
            _zoneIds[ny][nx] = zoneId;
            queue.add((x: nx, y: ny));
          }
        }
      }

      checkNeighbor(px + 1, py);
      checkNeighbor(px - 1, py);
      checkNeighbor(px, py + 1);
      checkNeighbor(px, py - 1);
    }
  }

  // Nastaví buňku a upozorní posluchače, aby se překreslili
  void setCell(int x, int y, MaterialType type, {double? temp}) {
    if (x >= 0 && x < _gridSize && y >= 0 && y < _gridSize) {
      bool typeChanged = _materials[y][x] != type;
      _materials[y][x] = type;
      if (temp != null) {
        _temperatures[y][x] = temp;
      }

      if (typeChanged) {
        recalculateZones();
      }

      notifyListeners(); // Řekne UI, že se má překreslit
    }
  }

  // Flood Fill (Kyblík)
  void floodFill(int startX, int startY, MaterialType newType) {
    if (startX < 0 ||
        startX >= _gridSize ||
        startY < 0 ||
        startY >= _gridSize) {
      return;
    }

    final targetType = _materials[startY][startX];

    // Pokud je materiál stejný, nic neděláme
    if (targetType == newType) return;

    // Fronta pro BFS
    final List<({int x, int y})> queue = [];
    queue.add((x: startX, y: startY));

    // Místo setCell použijeme přímý přístup pro rychlost (batch update)
    // Abychom se nezacyklili, měníme materiál okamžitě.

    while (queue.isNotEmpty) {
      final point = queue
          .removeLast(); // DFS nebo BFS, na tom nezáleží pro výsledek, jen pro vizuál
      final x = point.x;
      final y = point.y;

      if (x < 0 || x >= _gridSize || y < 0 || y >= _gridSize) continue;

      if (_materials[y][x] == targetType) {
        _materials[y][x] = newType;

        queue.add((x: x + 1, y: y));
        queue.add((x: x - 1, y: y));
        queue.add((x: x, y: y + 1));
        queue.add((x: x, y: y - 1));
      }
    }

    recalculateZones();
    notifyListeners();
  }

  // Získá typ materiálu v dané buňce
  MaterialType getMaterialAt(int x, int y) {
    if (x >= 0 && x < _gridSize && y >= 0 && y < _gridSize) {
      return _materials[y][x];
    }
    return MaterialType.air; // Výchozí pro neplatné souřadnice
  }

  // Získá teplotu v dané buňce
  double getTemperatureAt(int x, int y) {
    if (x >= 0 && x < _gridSize && y >= 0 && y < _gridSize) {
      return _temperatures[y][x];
    }
    return 0.0; // Výchozí pro neplatné souřadnice
  }

  // Změní velikost gridu a resetuje data
  void setGridSize(int newSize) {
    _gridSize = newSize;
    reset();
  }

  // Resetuje celý grid
  void reset() {
    _temperatures = List.generate(
      _gridSize,
      (_) => List.filled(_gridSize, 20.0),
    );
    _materials = List.generate(
      _gridSize,
      (_) => List.filled(_gridSize, MaterialType.air),
    );
    _zoneIds = List.generate(_gridSize, (_) => List.filled(_gridSize, 0));
    _zoneTargetTemps.clear();
    notifyListeners();
  }

  // --- Persistence ---

  // Serializace do JSON
  Map<String, dynamic> toJson() {
    return {
      'size': _gridSize,
      'materials': _materials.expand((row) => row.map((m) => m.index)).toList(),
      'temperatures': _temperatures.expand((row) => row).toList(),
    };
  }

  // Deserializace z JSON
  void fromJson(Map<String, dynamic> json) {
    _gridSize = json['size'] as int;
    final materialsList = List<int>.from(json['materials'] as List);
    final temperaturesList = List<double>.from(json['temperatures'] as List);

    _materials = [];
    _temperatures = [];
    _zoneIds = List.generate(_gridSize, (_) => List.filled(_gridSize, 0));
    _zoneTargetTemps.clear();

    for (int i = 0; i < _gridSize; i++) {
      final startIndex = i * _gridSize;
      final endIndex = startIndex + _gridSize;

      // Materiály
      _materials.add(
        materialsList
            .sublist(startIndex, endIndex)
            .map((index) => MaterialType.values[index])
            .toList(),
      );

      // Teploty
      _temperatures.add(temperaturesList.sublist(startIndex, endIndex));
    }
    recalculateZones();
    notifyListeners();
  }

  // Uložení gridu do vybraného souboru
  Future<void> saveToFile() async {
    try {
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Uložit mřížku jako...',
        fileName: 'model.thg',
        type: FileType.custom,
        allowedExtensions: ['thg', 'json'],
      );

      if (outputFile != null) {
        final file = File(outputFile);
        final jsonString = jsonEncode(toJson());
        await file.writeAsString(jsonString);
      }
    } catch (e) {
      debugPrint("Chyba při ukládání souboru: $e");
      rethrow;
    }
  }

  // Načtení gridu z vybraného souboru
  Future<void> loadFromFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Načíst mřížku ze souboru',
        type: FileType.custom,
        allowedExtensions: ['thg', 'json'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final jsonString = await file.readAsString();
        fromJson(jsonDecode(jsonString));
      }
    } catch (e) {
      debugPrint("Chyba při načítání souboru: $e");
      rethrow;
    }
  }

  // Uložení gridu do SharedPreferences
  Future<void> saveGrid() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(toJson());
    await prefs.setString('saved_grid', jsonString);
  }

  // Načtení gridu z SharedPreferences
  Future<void> loadGrid() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('saved_grid');
    if (jsonString != null) {
      fromJson(jsonDecode(jsonString));
    }
  }
}
