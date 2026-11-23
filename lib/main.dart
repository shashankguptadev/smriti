import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        // Placeholder until Phase 2 providers are added.
        Provider<String>.value(value: 'Smriti'),
      ],
      child: const SmritiApp(),
    ),
  );
}
