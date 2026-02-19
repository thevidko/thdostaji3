import 'package:flutter/material.dart' hide MaterialType;
import 'package:provider/provider.dart';
import '../models/grid_model.dart';
import '../widgets/grid_painter.dart';

enum EditorMode { draw, move, fill }

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  MaterialType _selectedTool = MaterialType.wall;
  final GlobalKey _gridKey = GlobalKey();
  final TransformationController _transformationController =
      TransformationController();
  EditorMode _mode = EditorMode.draw; // Výchozí režim

  @override
  Widget build(BuildContext context) {
    // Přistupujeme k GridModelu
    final gridModel = Provider.of<GridModel>(context);

    return Row(
      children: [
        // --- Levý panel s nástroji ---
        Container(
          width: 200,
          color: Colors.grey[200],
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nástroje',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              // --- Přepínač režimů (Kreslit / Kyblík / Posun) ---
              Row(
                children: [
                  Expanded(
                    child: _buildModeButton(Icons.edit, EditorMode.draw),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _buildModeButton(
                      Icons.format_color_fill,
                      EditorMode.fill,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _buildModeButton(Icons.pan_tool, EditorMode.move),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildToolButton(MaterialType.wall, 'Zeď', Icons.gite_rounded),
              _buildToolButton(MaterialType.floor, 'Podlaha', Icons.grid_view),
              _buildToolButton(
                MaterialType.insulation,
                'Izolace',
                Icons.layers,
              ),
              _buildToolButton(
                MaterialType.heater,
                'Zdroj tepla',
                Icons.fireplace,
              ),
              _buildToolButton(
                MaterialType.thermostat,
                'Termostat',
                Icons.thermostat,
              ),
              _buildToolButton(
                MaterialType.air,
                'Vzduch (Guma)',
                Icons.cleaning_services,
              ),
              const Spacer(), // Odsune tlačítka dolů
              // --- Ovládání velikosti mřížky ---
              const Text('Velikost mřížky:'),
              Slider(
                value: gridModel.gridSize.toDouble(),
                min: 10,
                max: 100,
                divisions: 90,
                label: gridModel.gridSize.toString(),
                onChanged: (value) {
                  gridModel.setGridSize(value.toInt());
                },
              ),
              Text(
                '${gridModel.gridSize} x ${gridModel.gridSize}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),

              // --- Ukládání / Načítání ---
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        await gridModel.saveGrid();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Mřížka uložena!')),
                          );
                        }
                      },
                      child: const Text('Uložit'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        await gridModel.loadGrid();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Mřížka načtena!')),
                          );
                        }
                      },
                      child: const Text('Načíst'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              ElevatedButton(
                onPressed: () {
                  gridModel.reset(); // Resetuje celou mřížku
                },
                child: const Text('Vymazat vše'),
              ),
            ],
          ),
        ),
        // --- Kreslicí plátno ---
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1.0, // Čtvercové plátno
              child: InteractiveViewer(
                transformationController: _transformationController,
                panEnabled: _mode == EditorMode.move,
                scaleEnabled: _mode == EditorMode.move,
                minScale: 0.5,
                maxScale: 5.0,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                child: GestureDetector(
                  key: _gridKey,
                  // Gesta pro kreslení a vyplňování
                  onPanStart: _mode == EditorMode.draw
                      ? (details) =>
                            _handlePan(details.localPosition, gridModel)
                      : null,
                  onPanUpdate: _mode == EditorMode.draw
                      ? (details) =>
                            _handlePan(details.localPosition, gridModel)
                      : null,
                  onTapUp: _mode == EditorMode.fill
                      ? (details) =>
                            _handleFill(details.localPosition, gridModel)
                      : (_mode ==
                                EditorMode
                                    .draw // Povolíme i ťuknutí pro kreslení tečky
                            ? (details) =>
                                  _handlePan(details.localPosition, gridModel)
                            : null),
                  child: CustomPaint(
                    painter: GridPainter(grid: gridModel),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Pomocná metoda pro tlačítka režimů
  Widget _buildModeButton(IconData icon, EditorMode mode) {
    final isSelected = _mode == mode;
    return ElevatedButton(
      onPressed: () {
        setState(() {
          _mode = mode;
        });
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.blue : Colors.grey[300],
        foregroundColor: isSelected ? Colors.white : Colors.black,
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 40), // Výška tlačítka
      ),
      child: Icon(icon),
    );
  }

  void _handleFill(Offset localPosition, GridModel gridModel) {
    final (x, y) = _getLocalCoordinates(localPosition, gridModel);
    if (x != null && y != null) {
      gridModel.floodFill(x, y, _selectedTool);
    }
  }

  void _handlePan(Offset localPosition, GridModel gridModel) {
    final (x, y) = _getLocalCoordinates(localPosition, gridModel);
    if (x != null && y != null) {
      gridModel.setCell(x, y, _selectedTool);
    }
  }

  // Pomocná metoda pro převod souřadnic
  (int?, int?) _getLocalCoordinates(Offset localPosition, GridModel gridModel) {
    final RenderBox? renderBox =
        _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return (null, null);

    final double cellSize = renderBox.size.shortestSide / gridModel.gridSize;
    final x = (localPosition.dx / cellSize).floor();
    final y = (localPosition.dy / cellSize).floor();
    return (x, y);
  }

  Widget _buildToolButton(MaterialType type, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: ElevatedButton.icon(
        onPressed: () {
          setState(() {
            _selectedTool = type;
          });
        },
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          foregroundColor: _selectedTool == type ? Colors.white : null,
          backgroundColor: _selectedTool == type ? type.color : null,
        ),
      ),
    );
  }
}
