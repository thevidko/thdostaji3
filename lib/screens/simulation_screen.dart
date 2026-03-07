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

    // Sidebar s ovládáním
    final controlPanel = Container(
      width: 280,
      padding: const EdgeInsets.all(16.0),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Consumer<SimulationEngine>(
        builder: (context, engine, child) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Ovládání', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),

              // Karta: Stav simulace
              Card(
                color: engine.isRunning
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Icon(
                        engine.isRunning
                            ? Icons.timelapse
                            : Icons.pause_circle_filled,
                        size: 48,
                        color: engine.isRunning
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        engine.isRunning ? 'Běží' : 'Pozastaveno',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: engine.toggleSimulation,
                        icon: Icon(
                          engine.isRunning ? Icons.pause : Icons.play_arrow,
                        ),
                        label: Text(engine.isRunning ? 'Pauza' : 'Spustit'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Karta: Čas simulace
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      Text(
                        '${engine.currentTime.day}. ${engine.currentTime.month}. ${engine.currentTime.year}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                      Text(
                        '${engine.currentTime.hour.toString().padLeft(2, '0')}:${engine.currentTime.minute.toString().padLeft(2, '0')}:${engine.currentTime.second.toString().padLeft(2, '0')}',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Rychlost času',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 60, label: Text('Min/s')),
                          ButtonSegment(value: 3600, label: Text('Hod/s')),
                          ButtonSegment(value: 86400, label: Text('Den/s')),
                          ButtonSegment(value: 604800, label: Text('Týd/s')),
                        ],
                        selected: {
                          [
                                60,
                                3600,
                                86400,
                                604800,
                              ].contains(engine.timeMultiplier)
                              ? engine.timeMultiplier
                              : 60,
                        },
                        onSelectionChanged: (Set<int> newSelection) {
                          engine.setTimeMultiplier(newSelection.first);
                        },
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Odstraněna fyzikální rychlost, ta je nyní dána časem

              // Karta: Venkovní teplota
              Card(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      const Text(
                        'Počasí venku',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${engine.outdoorTemp.toStringAsFixed(1)} °C',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onTertiaryContainer,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Řízeno sezónně s ohledem na čas',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onTertiaryContainer,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              const Divider(),

              // Přepínače
              SwitchListTile(
                title: const Text('Zobrazit hodnoty'),
                value: _showValues,
                onChanged: (val) {
                  setState(() {
                    _showValues = val;
                  });
                },
                contentPadding: EdgeInsets.zero,
              ),

              const Spacer(),

              // Tip
              Card(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.touch_app,
                        color: Theme.of(
                          context,
                        ).colorScheme.onTertiaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tip: Ťukněte na místnost pro nastavení teploty.',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onTertiaryContainer,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    return Row(
      children: [
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
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    minScale: 0.5,
                    maxScale: 20.0,
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
          ),
        ),
        const VerticalDivider(width: 1),
        controlPanel,
      ],
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
              content: SizedBox(
                width: 340,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // METRIKA SPOKOJENOSTI
                    const Text(
                      'Spokojenost s teplotou',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ListenableBuilder(
                      listenable: gridModel,
                      builder: (context, _) {
                        final satisfaction = gridModel.getZoneSatisfaction(zoneId);
                        final percent = (satisfaction * 100).toInt();
                        Color meterColor = Colors.green;
                        if (satisfaction < 0.4) {
                          meterColor = Colors.red;
                        } else if (satisfaction < 0.7) {
                          meterColor = Colors.orange;
                        }
                        return Column(
                          children: [
                            LinearProgressIndicator(
                              value: satisfaction,
                              minHeight: 12,
                              backgroundColor: Colors.grey.shade300,
                              color: meterColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            const SizedBox(height: 4),
                            Text('$percent %'),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 8),

                    // ENERGETICKÉ METRIKY
                    const Text(
                      'Spotřeba tepelné energie',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    ListenableBuilder(
                      listenable: gridModel,
                      builder: (context, _) {
                        final energy = gridModel.getZoneEnergyConsumed(zoneId);
                        final power = gridModel.getZoneInstantPower(zoneId);
                        return _EnergyMetricsCard(energy: energy, power: power);
                      },
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => gridModel.resetZoneEnergy(),
                        icon: const Icon(Icons.restart_alt, size: 16),
                        label: const Text('Resetovat měřič'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.orange,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                    const Divider(),
                    const SizedBox(height: 8),

                    // NASTAVENÍ TEPLOTY
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

/// Karta s energetickými metrikami zóny.
/// Formátuje surová simulační čísla do čitelných jednotek.
class _EnergyMetricsCard extends StatelessWidget {
  final double energy;
  final double power;

  const _EnergyMetricsCard({required this.energy, required this.power});

  String _formatEnergy(double e) {
    if (e < 1e6) return '${e.toStringAsFixed(0)} J';
    if (e < 1e9) return '${(e / 1e6).toStringAsFixed(2)} MJ';
    return '${(e / 1e9).toStringAsFixed(2)} GJ';
  }

  String _formatPower(double p) {
    if (p < 1e3) return '${p.toStringAsFixed(0)} W';
    return '${(p / 1e3).toStringAsFixed(2)} kW';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: _MetricTile(
            icon: Icons.bolt,
            label: 'Okamžitý výkon',
            value: _formatPower(power),
            color: colorScheme.error,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MetricTile(
            icon: Icons.local_fire_department,
            label: 'Celková energie',
            value: _formatEnergy(energy),
            color: colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: color,
            ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
