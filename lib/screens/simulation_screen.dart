import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../logic/simulation_engine.dart';
import '../models/grid_model.dart';
import '../widgets/grid_painter.dart';

class SimulationScreen extends StatefulWidget {
  const SimulationScreen({super.key});

  @override
  State<SimulationScreen> createState() => _SimulationScreenState();
}

class _SimulationScreenState extends State<SimulationScreen> {
  final GlobalKey _gridKey = GlobalKey();
  final TransformationController _transformationController =
      TransformationController();
  bool _showValues = false;
  double _currentScale = 1.0;

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_onTransformationChanged);
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformationChanged);
    _transformationController.dispose();
    super.dispose();
  }

  void _onTransformationChanged() {
    // Získáme aktuální měřítko z matice transformace
    final scale = _transformationController.value.getMaxScaleOnAxis();
    if (scale != _currentScale) {
      setState(() {
        _currentScale = scale;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Přistupujeme k GridModelu (pouze pro čtení / zobrazení)
    final gridModel = Provider.of<GridModel>(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Simulace (Náhled)',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1.0,
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  minScale: 0.5,
                  maxScale: 20.0, // Zvýšeno pro lepší zoom na text
                  // V simulaci chceme jen prohlížet, ne kreslit, ale ťuknutí vyvolá nastavení zóny
                  child: GestureDetector(
                    key: _gridKey,
                    onTapUp: (details) =>
                        _handleTap(details.localPosition, gridModel),
                    child: CustomPaint(
                      painter: GridPainter(
                        grid: gridModel,
                        showTemperatureValues: _showValues,
                        zoomScale: _currentScale,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Ovládací panel
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Colors.grey[200],
            child: Consumer<SimulationEngine>(
              builder: (context, engine, child) {
                return Column(
                  children: [
                    // Start / Stop
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: engine.toggleSimulation,
                          icon: Icon(
                            engine.isRunning ? Icons.pause : Icons.play_arrow,
                          ),
                          label: Text(engine.isRunning ? 'Pauza' : 'Spustit'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: engine.isRunning
                                ? Colors.orange
                                : Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    const Text(
                      'Tip: Ťukněte na místnost pro nastavení teploty',
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 10),

                    // Rychlost
                    Row(
                      children: [
                        const Text('Rychlost:'),
                        Expanded(
                          child: Slider(
                            value: engine.speedFactor.toDouble(),
                            min: 1,
                            max: 20,
                            divisions: 19,
                            label: '${engine.speedFactor}x',
                            onChanged: (val) =>
                                engine.setSpeedFactor(val.toInt()),
                          ),
                        ),
                        Text('${engine.speedFactor}x'),
                      ],
                    ),

                    // Venkovní teplota
                    Row(
                      children: [
                        const Text('Venku:'),
                        Expanded(
                          child: Slider(
                            value: engine.outdoorTemp,
                            min: -20,
                            max: 40,
                            divisions: 60,
                            label: '${engine.outdoorTemp.toStringAsFixed(1)}°C',
                            onChanged: engine.setOutdoorTemp,
                          ),
                        ),
                        Text('${engine.outdoorTemp.toStringAsFixed(1)}°C'),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Přepínač zobrazení hodnot
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Zobrazit hodnoty:'),
                        Switch(
                          value: _showValues,
                          onChanged: (val) {
                            setState(() {
                              _showValues = val;
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _handleTap(Offset localPosition, GridModel gridModel) {
    // Získáme RenderBox pomocí klíče
    final RenderBox? renderBox =
        _gridKey.currentContext?.findRenderObject() as RenderBox?;

    if (renderBox == null) return;

    // Dynamický výpočet velikosti buňky podle aktuální velikosti widgetu
    final double cellSize = renderBox.size.shortestSide / gridModel.gridSize;

    // Převod pixelů na souřadnice buňky
    final x = (localPosition.dx / cellSize).floor();
    final y = (localPosition.dy / cellSize).floor();

    final int zoneId = gridModel.getZoneId(x, y);

    if (zoneId > 0) {
      _showZoneConfigDialog(context, gridModel, zoneId);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Toto není zóna (místnost).'),
            duration: Duration(milliseconds: 500),
          ),
        );
      }
    }
  }

  void _showZoneConfigDialog(
    BuildContext context,
    GridModel gridModel,
    int zoneId,
  ) {
    double currentTemp = gridModel.getZoneTargetTemp(zoneId);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Nastavení Zóny #$zoneId'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Cílová teplota: ${currentTemp.toStringAsFixed(1)}°C'),
                  Slider(
                    value: currentTemp,
                    min: 15,
                    max: 30,
                    divisions: 30,
                    label: currentTemp.toStringAsFixed(1),
                    onChanged: (val) {
                      setState(() {
                        currentTemp = val;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Zrušit'),
                ),
                ElevatedButton(
                  onPressed: () {
                    gridModel.setZoneTargetTemp(zoneId, currentTemp);
                    Navigator.pop(context);
                  },
                  child: const Text('Uložit'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
