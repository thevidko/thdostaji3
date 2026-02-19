import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(32.0),
              children: [
                Text(
                  'Jak používat',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 24),
                _buildStep(
                  context,
                  icon: Icons.gite_rounded,
                  title: '1. Vytvořte půdorys',
                  description:
                      'V Editoru vyberte nástroj "Zeď" a nakreslete obvodové zdi a příčky místností.',
                ),
                _buildStep(
                  context,
                  icon: Icons.fireplace,
                  title: '2. Přidejte zdroje tepla',
                  description:
                      'Umístěte "Zdroj tepla" (topení) do místností, které chcete vytápět.',
                ),
                _buildStep(
                  context,
                  icon: Icons.thermostat,
                  title: '3. Umístěte termostaty',
                  description:
                      'Každá vytápěná místnost potřebuje "Termostat", který bude řídit teplotu.',
                ),
                _buildStep(
                  context,
                  icon: Icons.format_color_fill,
                  title: '4. Definujte zóny (Místnosti)',
                  description:
                      'Použijte nástroj "Výplň" (Kyblík) s materiálem "Podlaha". Kliknutím do uzavřeného prostoru vyplníte podlahu a vytvoříte tak "Zónu".',
                ),
                const Divider(height: 48),
                Text(
                  'Simulace',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                _buildStep(
                  context,
                  icon: Icons.touch_app,
                  title: '5. Nastavte teplotu',
                  description:
                      'Přepněte se do záložky "Simulace". Kliknutím na termostat otevřete nastavení cílové teploty.',
                ),
                _buildStep(
                  context,
                  icon: Icons.play_arrow,
                  title: '6. Spusťte simulaci',
                  description:
                      'Stiskněte tlačítko "Spustit" v pravém panelu. Sledujte, jak se teplo šíří a jak termostaty spínají topení (červeně).',
                ),
              ],
            ),
          ),
          // Placeholder for optional right panel content or illustrative image
        ],
      ),
    );
  }

  Widget _buildStep(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Icon(
              icon,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
