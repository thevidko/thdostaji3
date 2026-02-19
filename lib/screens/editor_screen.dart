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

    // Sidebar s nástroji
    final toolsPanel = Container(
      width: 280,
      padding: const EdgeInsets.all(8.0),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          // Sekce: Soubor
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  const Text(
                    'Soubor',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () async {
                            await gridModel.saveGrid();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Mřížka uložena!'),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.save),
                          label: const Text('Uložit'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () async {
                            await gridModel.loadGrid();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Mřížka načtena!'),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Načíst'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => gridModel.reset(),
                    icon: const Icon(Icons.delete_forever),
                    label: const Text('Vymazat vše'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Sekce: Režim
          const Text('Režim', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          SegmentedButton<EditorMode>(
            segments: const [
              ButtonSegment(
                value: EditorMode.draw,
                icon: Icon(Icons.edit),
                label: Text('Kreslit'),
              ),
              ButtonSegment(
                value: EditorMode.fill,
                icon: Icon(Icons.format_color_fill),
                label: Text('Výplň'),
              ),
              ButtonSegment(
                value: EditorMode.move,
                icon: Icon(Icons.pan_tool),
                label: Text('Posun'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (Set<EditorMode> newSelection) {
              setState(() {
                _mode = newSelection.first;
              });
            },
            showSelectedIcon: false,
          ),
          const SizedBox(height: 16),

          // Sekce: Materiály
          const Text(
            'Materiály',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView(
              children: [
                _buildToolTile(MaterialType.wall, 'Zeď', Icons.gite_rounded),
                _buildToolTile(
                  MaterialType.floor,
                  'Podlaha (Zóna)',
                  Icons.grid_view,
                ),
                _buildToolTile(
                  MaterialType.insulation,
                  'Izolace',
                  Icons.layers,
                ),
                _buildToolTile(
                  MaterialType.heater,
                  'Zdroj tepla',
                  Icons.fireplace,
                ),
                _buildToolTile(
                  MaterialType.thermostat,
                  'Termostat',
                  Icons.thermostat,
                ),
                _buildToolTile(
                  MaterialType.air,
                  'Vzduch (Guma)',
                  Icons.cleaning_services,
                ),
              ],
            ),
          ),

          // Sekce: Velikost
          const Divider(),
          Text('Velikost: ${gridModel.gridSize}x${gridModel.gridSize}'),
          Slider(
            value: gridModel.gridSize.toDouble(),
            min: 10,
            max: 100,
            divisions: 90,
            onChanged: (v) => gridModel.setGridSize(v.toInt()),
          ),
        ],
      ),
    );

    return Row(
      children: [
        // Sidebar vlevo (nebo vpravo? User: "Nástroje vpravo"? Plan: "Sidebar (Right)". Wait.
        // Plan said: "Editor Screen: Move tool palette to a dedicated Right Sidebar."
        // So I should put Expanded(Grid) FIRST, then Sidebar.
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: AspectRatio(
                aspectRatio: 1.0,
                child: Card(
                  elevation: 4,
                  clipBehavior: Clip.antiAlias,
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    panEnabled: _mode == EditorMode.move,
                    scaleEnabled: _mode == EditorMode.move,
                    minScale: 0.5,
                    maxScale: 5.0,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    child: GestureDetector(
                      key: _gridKey,
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
                          : (_mode == EditorMode.draw
                                ? (details) => _handlePan(
                                    details.localPosition,
                                    gridModel,
                                  )
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
          ),
        ),
        const VerticalDivider(width: 1),
        toolsPanel, // Sidebar vpravo
      ],
    );
  }

  Widget _buildToolTile(MaterialType type, String label, IconData icon) {
    final isSelected = _selectedTool == type;
    final colorScheme = Theme.of(context).colorScheme;

    // Určíme barvu pozadí ikony a barvu samotné ikony pro kontrast
    Color bgColor = type.color;
    if (type == MaterialType.air) {
      bgColor = Colors.white; // Pro vzduch/gumu dáme bílé pozadí
    } else if (type == MaterialType.thermostat) {
      // Thermostat color might be transparent-ish or specific? Check model.
      // Default thermostat is usually visible.
    }

    final iconColor = bgColor.computeLuminance() > 0.5
        ? Colors.black87
        : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.withOpacity(0.5), width: 1),
          ),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        title: Text(
          label,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurface,
          ),
        ),
        selected: isSelected,
        selectedTileColor: colorScheme.primaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: () {
          setState(() {
            _selectedTool = type;
            if (_mode == EditorMode.move) {
              _mode = EditorMode.draw; // Auto-switch to draw
            }
          });
        },
      ),
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

  (int?, int?) _getLocalCoordinates(Offset localPosition, GridModel gridModel) {
    final RenderBox? renderBox =
        _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return (null, null);

    final double cellSize = renderBox.size.shortestSide / gridModel.gridSize;
    final x = (localPosition.dx / cellSize).floor();
    final y = (localPosition.dy / cellSize).floor();
    return (x, y);
  }
}
