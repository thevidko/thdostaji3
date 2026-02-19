import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'logic/simulation_engine.dart';
import 'models/grid_model.dart';
import 'screens/home_screen.dart';

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
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomeScreen(),
    );
  }
}
