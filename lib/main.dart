import 'package:flutter/material.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Model Manager checks on-device model weights in app storage
  final modelManager = ModelManagerProvider();
  await modelManager.checkModelAvailability();

  const ingestor = LocalDocumentIngestor();
  final vectorStore = ObjectBoxVectorStore();
  await vectorStore.initialize();

  // Conditional injection: use Edge services if model is ready, otherwise mocks
  final EmbeddingService embeddingService = modelManager.isModelReady
      ? EdgeEmbeddingService(modelPath: modelManager.activeModelPath)
      : const MockEmbeddingService();

  final LlmService llmService = modelManager.isModelReady
      ? EdgeLlmService(modelPath: modelManager.activeModelPath)
      : MockLlmService();
  await llmService.initialize();

  final ragService = RagService(
    embeddingService: embeddingService,
    vectorStoreService: vectorStore,
    llmService: llmService,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ModelManagerProvider>.value(value: modelManager),
        Provider<DocumentIngestor>.value(value: ingestor),
        Provider<EmbeddingService>.value(value: embeddingService),
        Provider<VectorStoreService>.value(value: vectorStore),
        Provider<LlmService>.value(value: llmService),
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
