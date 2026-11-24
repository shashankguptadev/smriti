import 'package:flutter/material.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'core/services/document_ingestor.dart';
import 'core/services/embedding_service.dart';
import 'core/services/llm_service.dart';
import 'core/services/vector_store_service.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize FlutterEdgeAi with LiteRT LM inference engine
  try {
    await FlutterEdgeAi.initialize(
      inferenceEngines: const [LiteRtLmEngine()],
    );
  } catch (e) {
    debugPrint('FlutterEdgeAi initialization notice: $e');
  }

  // Model Manager checks on-device model weights in app storage
  final modelManager = ModelManagerProvider();
  await modelManager.checkModelAvailability();

  const ingestor = LocalDocumentIngestor();
  final vectorStore = ObjectBoxVectorStore();
  await vectorStore.initialize();

  final EmbeddingService embeddingService = modelManager.hasRealModel
      ? EdgeEmbeddingService(modelPath: modelManager.activeModelPath)
      : const MockEmbeddingService();

  final LlmService initialLlm = modelManager.hasRealModel
      ? EdgeLlmService(modelPath: modelManager.activeModelPath)
      : MockLlmService();
  try {
    await initialLlm.initialize();
  } catch (e) {
    debugPrint('Initial LLM initialization notice: $e');
  }

  // Dynamic switchable LLM service for seamless hot-swapping
  final switchableLlm = SwitchableLlmService(initialLlm);

  modelManager.addListener(() async {
    if (modelManager.hasRealModel) {
      final edge = EdgeLlmService(modelPath: modelManager.activeModelPath);
      try {
        await edge.initialize();
        switchableLlm.switchTo(edge);
        debugPrint('main: EdgeLlmService initialized and hot-swapped in.');
      } catch (e) {
        // The LiteRT engine failed to load (e.g. corrupted file, unsupported
        // model format). Revert the ModelManagerProvider to an error state so
        // the UI shows the failure instead of silently crashing.
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

  final ragService = RagService(
    embeddingService: embeddingService,
    vectorStoreService: vectorStore,
    llmService: switchableLlm,
  );

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

/// Returns the first line / short summary of an exception message so it fits
/// in a SnackBar / error card without overwhelming the user.
String _shortError(Object e) {
  final full = e.toString();
  final firstLine = full.split('\n').first.trim();
  return firstLine.length > 120 ? '${firstLine.substring(0, 117)}...' : firstLine;
}
