import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'core/services/document_ingestor.dart';
import 'core/services/embedding_service.dart';
import 'core/services/llm_service.dart';
import 'core/services/vector_store_service.dart';
import 'providers/app_init_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/knowledge_base_provider.dart';
import 'providers/model_manager_provider.dart';
import 'services/edge_embedding_service.dart';
import 'services/edge_llm_service.dart';
import 'services/local_document_ingestor.dart';
import 'services/mock_embedding_service.dart';
import 'services/mock_llm_service.dart';
import 'services/objectbox_vector_store.dart';
import 'services/rag_service.dart';
import 'services/switchable_llm_service.dart';
import 'ui/screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final initProvider = AppInitProvider();

  // ── STEP 0: Show the splash screen immediately ──────────────────────────
  // The user sees the branded screen within the first frame instead of a
  // black/white blank while the AI engine and database boot up.
  runApp(
    ChangeNotifierProvider.value(
      value: initProvider,
      child: MaterialApp(
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
        home: const SplashScreen(),
      ),
    ),
  );

  // ── STEP 1: LiteRT inference engine ─────────────────────────────────────
  initProvider.advance(
    InitStage.initializingEngine,
    'Initializing AI engine…',
    0.10,
  );
  try {
    await FlutterEdgeAi.initialize(
      inferenceEngines: const [LiteRtLmEngine()],
    );
  } catch (e) {
    debugPrint('FlutterEdgeAi initialization notice: $e');
    // Non-fatal — the app still works in mock mode.
  }

  // ── STEP 2: Model availability ───────────────────────────────────────────
  initProvider.advance(
    InitStage.checkingModels,
    'Checking model availability…',
    0.25,
  );
  final modelManager = ModelManagerProvider();
  await modelManager.checkModelAvailability();

  // ── STEP 3: ObjectBox vector store ───────────────────────────────────────
  initProvider.advance(
    InitStage.openingDatabase,
    'Opening knowledge base…',
    0.45,
  );
  const ingestor = LocalDocumentIngestor();
  final vectorStore = ObjectBoxVectorStore();
  await vectorStore.initialize();

  // ── STEP 4: Embedding & LLM services ────────────────────────────────────
  initProvider.advance(
    InitStage.loadingModel,
    'Setting up AI services…',
    0.60,
  );

  final EmbeddingService embeddingService = modelManager.hasRealModel
      ? EdgeEmbeddingService(modelPath: modelManager.activeModelPath)
      : const MockEmbeddingService();

  // Start with MockLlmService so the main app appears instantly.
  // The real EdgeLlmService is loaded in the background and hot-swapped in.
  final mockLlm = MockLlmService();
  await mockLlm.initialize();
  final switchableLlm = SwitchableLlmService(mockLlm);

  // ── STEP 5: Kick off background LLM load (non-blocking) ─────────────────
  if (modelManager.hasRealModel) {
    initProvider.advance(
      InitStage.loadingModel,
      'AI model loading in background — the app is ready to use now!',
      0.80,
    );
    // Load in background; app is fully usable in mock mode in the meantime.
    unawaited(_loadLlmInBackground(
      modelPath: modelManager.activeModelPath!,
      switchableLlm: switchableLlm,
      modelManager: modelManager,
    ));
  }

  // ── STEP 6: RAG pipeline ─────────────────────────────────────────────────
  final ragService = RagService(
    embeddingService: embeddingService,
    vectorStoreService: vectorStore,
    llmService: switchableLlm,
  );

  // Listen for model changes from the Model Manager UI and hot-swap.
  modelManager.addListener(() async {
    if (modelManager.hasRealModel) {
      final edge = EdgeLlmService(modelPath: modelManager.activeModelPath);
      try {
        await edge.initialize();
        switchableLlm.switchTo(edge);
        debugPrint('main: EdgeLlmService initialized and hot-swapped in.');
      } catch (e) {
        debugPrint('main: EdgeLlmService.initialize() failed: $e');
        final mock = MockLlmService();
        await mock.initialize();
        switchableLlm.switchTo(mock);
        modelManager.setEngineError(
          'Model failed to load: ${_shortError(e)}. '
          'The file may be incomplete or unsupported. Please re-import.',
        );
      }
    } else {
      final mock = MockLlmService();
      await mock.initialize();
      switchableLlm.switchTo(mock);
    }
  });

  // ── STEP 7: Swap in the full app ─────────────────────────────────────────
  initProvider.complete();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ModelManagerProvider>.value(value: modelManager),
        Provider<DocumentIngestor>.value(value: ingestor),
        Provider<EmbeddingService>.value(value: embeddingService),
        Provider<VectorStoreService>.value(value: vectorStore),
        Provider<LlmService>.value(value: switchableLlm),
        Provider<RagService>.value(value: ragService),
        ChangeNotifierProvider<KnowledgeBaseProvider>(
          create: (_) => KnowledgeBaseProvider(
            ingestor: ingestor,
            embeddingService: embeddingService,
            vectorStoreService: vectorStore,
          )..loadDocuments(),
        ),
        ChangeNotifierProvider<ChatProvider>(
          create: (_) => ChatProvider(ragService: ragService),
        ),
      ],
      child: const SmritiApp(),
    ),
  );
}

/// Loads [EdgeLlmService] asynchronously and hot-swaps it into [switchableLlm].
/// Any engine error is surfaced through [modelManager.setEngineError].
Future<void> _loadLlmInBackground({
  required String modelPath,
  required SwitchableLlmService switchableLlm,
  required ModelManagerProvider modelManager,
}) async {
  final edge = EdgeLlmService(modelPath: modelPath);
  try {
    await edge.initialize();
    switchableLlm.switchTo(edge);
    debugPrint('main: background EdgeLlmService hot-swapped in successfully.');
  } catch (e) {
    debugPrint('main: background EdgeLlmService.initialize() failed: $e');
    modelManager.setEngineError(
      'Model failed to load: ${_shortError(e)}. '
      'The file may be incomplete or unsupported. Please re-import.',
    );
  }
}

/// Returns the first line of an exception message, truncated to 120 chars.
String _shortError(Object e) {
  final full = e.toString();
  final firstLine = full.split('\n').first.trim();
  return firstLine.length > 120 ? '${firstLine.substring(0, 117)}...' : firstLine;
}
