import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smriti/core/services/document_ingestor.dart';
import 'package:smriti/core/services/embedding_service.dart';
import 'package:smriti/core/services/llm_service.dart';
import 'package:smriti/core/services/vector_store_service.dart';
import 'package:smriti/providers/chat_provider.dart';
import 'package:smriti/providers/knowledge_base_provider.dart';
import 'package:smriti/providers/model_manager_provider.dart';
import 'package:smriti/services/in_memory_vector_store.dart';
import 'package:smriti/services/local_document_ingestor.dart';
import 'package:smriti/services/mock_embedding_service.dart';
import 'package:smriti/services/mock_llm_service.dart';
import 'package:smriti/services/rag_service.dart';
import 'package:smriti/ui/screens/home_screen.dart';

void main() {
  group('HomeScreen & ModelManager Navigation', () {
    late InMemoryVectorStore vectorStore;
    late MockEmbeddingService embeddingService;
    late MockLlmService llmService;
    late RagService ragService;
    late ModelManagerProvider modelManager;
    const ingestor = LocalDocumentIngestor();

    setUp(() async {
      vectorStore = InMemoryVectorStore();
      await vectorStore.initialize();
      embeddingService = const MockEmbeddingService();
      llmService = MockLlmService(tokenDelay: Duration.zero);
      await llmService.initialize();
      ragService = RagService(
        embeddingService: embeddingService,
        vectorStoreService: vectorStore,
        llmService: llmService,
      );
      modelManager = ModelManagerProvider()..useMockOrBypass();
    });

    Widget createTestApp() {
      return MultiProvider(
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
            ),
          ),
          ChangeNotifierProvider<ChatProvider>(
            create: (_) => ChatProvider(ragService: ragService),
          ),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      );
    }

    testWidgets('tune icon button in AppBar navigates to ModelManagerScreen',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      final tuneButton = find.byIcon(Icons.tune);
      expect(tuneButton, findsOneWidget);

      await tester.tap(tuneButton);
      await tester.pumpAndSettle();

      expect(find.text('AI Model Setup'), findsOneWidget);
      expect(find.text('Download Model from Hugging Face'), findsOneWidget);
      expect(find.text('Gemma 4 E2B (Recommended, ~2.41 GB)'), findsOneWidget);
    });

    testWidgets('mock mode banner displays in ChatScreen and navigates on tap',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      final bannerText = find.text('Running in Mock Mode — Tap to activate or import an AI model');
      expect(bannerText, findsOneWidget);

      await tester.tap(bannerText);
      await tester.pumpAndSettle();

      expect(find.text('AI Model Setup'), findsOneWidget);
    });
  });
}

