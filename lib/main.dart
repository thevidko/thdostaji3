import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'logic/simulation_engine.dart';
import 'models/grid_model.dart';
import 'screens/editor_screen.dart';
import 'screens/simulation_screen.dart';
import 'screens/help_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => GridModel(50)),
        ChangeNotifierProxyProvider<GridModel, SimulationEngine>(
          create: (context) =>
              SimulationEngine(Provider.of<GridModel>(context, listen: false)),
          update: (context, gridModel, engine) =>
              engine!..updateGridModel(gridModel),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Heat Simulator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.light,
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final List<Widget> _pages = [
    const EditorScreen(),
    const SimulationScreen(),
    const HelpScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _currentIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _currentIndex = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.edit_outlined),
                selectedIcon: Icon(Icons.edit),
                label: Text('Editor'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.play_circle_outline),
                selectedIcon: Icon(Icons.play_circle_filled),
                label: Text('Simulace'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.help_outline),
                selectedIcon: Icon(Icons.help),
                label: Text('Nápověda'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: _pages[_currentIndex]),
        ],
      ),
    );
  }
}
