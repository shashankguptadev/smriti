import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/services/llm_service.dart';
import 'core/services/vector_store_service.dart';
import 'providers/model_manager_provider.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/model_manager_screen.dart';

/// Root application widget that listens to platform lifecycle events to release
/// model memory when backgrounded and close database stores upon app detachment.
class SmritiApp extends StatefulWidget {
  const SmritiApp({super.key});

  @override
  State<SmritiApp> createState() => _SmritiAppState();
}

class _SmritiAppState extends State<SmritiApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;

    if (state == AppLifecycleState.paused) {
      // Unload memory-heavy LLM weights when app moves to background
      try {
        context.read<LlmService>().dispose();
      } catch (_) {}
    } else if (state == AppLifecycleState.resumed) {
      // Re-warm LLM service upon resuming foreground
      try {
        final llm = context.read<LlmService>();
        if (!llm.isReady) {
          llm.initialize();
        }
      } catch (_) {}
    } else if (state == AppLifecycleState.detached) {
      // Close database handles when app process is terminating
      try {
        context.read<VectorStoreService>().dispose();
      } catch (_) {}
    }
  }

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
