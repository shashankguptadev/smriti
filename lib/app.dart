import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/model_manager_provider.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/model_manager_screen.dart';

class SmritiApp extends StatelessWidget {
  const SmritiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smriti',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: Consumer<ModelManagerProvider>(
        builder: (context, modelManager, _) {
          if (modelManager.isModelReady) {
            return const HomeScreen();
          }
          return const ModelManagerScreen();
        },
      ),
    );
  }
}
