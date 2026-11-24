import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smriti/app.dart';
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

void main() {
  testWidgets('SmritiApp renders home screen with title and navigation bar',
      (WidgetTester tester) async {
    final vs = InMemoryVectorStore();
    await vs.initialize();
    const es = MockEmbeddingService();
    final ls = MockLlmService(tokenDelay: Duration.zero);
    const ingestor = LocalDocumentIngestor();
    final rag = RagService(
      embeddingService: es,
      vectorStoreService: vs,
      llmService: ls,
    );
    final mm = ModelManagerProvider()..useMockOrBypass();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ModelManagerProvider>.value(value: mm),
          Provider<DocumentIngestor>.value(value: ingestor),
          Provider<EmbeddingService>.value(value: es),
          Provider<VectorStoreService>.value(value: vs),
          Provider<LlmService>.value(value: ls),
          Provider<RagService>.value(value: rag),
          ChangeNotifierProvider<KnowledgeBaseProvider>(
            create: (_) => KnowledgeBaseProvider(
              ingestor: ingestor,
              embeddingService: es,
              vectorStoreService: vs,
            ),
          ),
          ChangeNotifierProvider<ChatProvider>(
            create: (_) => ChatProvider(ragService: rag),
          ),
        ],
        child: const SmritiApp(),
      ),
    );

    // Verify the initial AppBar title is present (defaults to Chat tab)
    expect(find.text('Smriti Chat'), findsOneWidget);

    // Verify NavigationBar destinations exist
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);

    // Verify ChatScreen empty state is present
    expect(find.text('Ask Smriti Anything'), findsOneWidget);
  });

  testWidgets('NavigationBar switches between Chat and Documents tabs',
      (WidgetTester tester) async {
    final vs = InMemoryVectorStore();
    await vs.initialize();
    const es = MockEmbeddingService();
    final ls = MockLlmService(tokenDelay: Duration.zero);
    const ingestor = LocalDocumentIngestor();
    final rag = RagService(
      embeddingService: es,
      vectorStoreService: vs,
      llmService: ls,
    );
    final mm = ModelManagerProvider()..useMockOrBypass();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ModelManagerProvider>.value(value: mm),
          Provider<DocumentIngestor>.value(value: ingestor),
          Provider<EmbeddingService>.value(value: es),
          Provider<VectorStoreService>.value(value: vs),
          Provider<LlmService>.value(value: ls),
          Provider<RagService>.value(value: rag),
          ChangeNotifierProvider<KnowledgeBaseProvider>(
            create: (_) => KnowledgeBaseProvider(
              ingestor: ingestor,
              embeddingService: es,
              vectorStoreService: vs,
            ),
          ),
          ChangeNotifierProvider<ChatProvider>(
            create: (_) => ChatProvider(ragService: rag),
          ),
        ],
        child: const SmritiApp(),
      ),
    );

    // Tap the Documents navigation destination
    await tester.tap(find.text('Documents'));
    await tester.pumpAndSettle();

    // Now AppBar displays Knowledge Base and DocumentsScreen is shown
    expect(find.text('Knowledge Base'), findsOneWidget);
    expect(find.text('No documents indexed yet'), findsOneWidget);
    expect(find.text('Add Document'), findsOneWidget);
  });

  testWidgets('SmritiApp responds to lifecycle transitions by unloading and reloading LLM',
      (WidgetTester tester) async {
    final vs = InMemoryVectorStore();
    await vs.initialize();
    const es = MockEmbeddingService();
    final ls = MockLlmService(tokenDelay: Duration.zero);
    await ls.initialize();
    expect(ls.isReady, isTrue);

    const ingestor = LocalDocumentIngestor();
    final rag = RagService(
      embeddingService: es,
      vectorStoreService: vs,
      llmService: ls,
    );
    final mm = ModelManagerProvider()..useMockOrBypass();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ModelManagerProvider>.value(value: mm),
          Provider<DocumentIngestor>.value(value: ingestor),
          Provider<EmbeddingService>.value(value: es),
          Provider<VectorStoreService>.value(value: vs),
          Provider<LlmService>.value(value: ls),
          Provider<RagService>.value(value: rag),
          ChangeNotifierProvider<KnowledgeBaseProvider>(
            create: (_) => KnowledgeBaseProvider(
              ingestor: ingestor,
              embeddingService: es,
              vectorStoreService: vs,
            ),
          ),
          ChangeNotifierProvider<ChatProvider>(
            create: (_) => ChatProvider(ragService: rag),
          ),
        ],
        child: const SmritiApp(),
      ),
    );

    // Transition to inactive (e.g. permission prompt or notification shade): must NOT unload LLM
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(ls.isReady, isTrue);

    // Transition to paused via hidden (app moving to background): unloads LLM
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(ls.isReady, isFalse);

    // Transition back through hidden and inactive to foreground (resumed): re-warms LLM
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(ls.isReady, isTrue);
  });
}
