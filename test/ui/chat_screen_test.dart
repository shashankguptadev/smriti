import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smriti/core/services/llm_service.dart';
import 'package:smriti/providers/chat_provider.dart';
import 'package:smriti/services/in_memory_vector_store.dart';
import 'package:smriti/services/mock_embedding_service.dart';
import 'package:smriti/services/mock_llm_service.dart';
import 'package:smriti/services/rag_service.dart';
import 'package:smriti/ui/screens/chat_screen.dart';

class _ErrorLlmService implements LlmService {
  @override
  bool get isReady => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Stream<String> generateResponse({
    required String prompt,
    List<String> contextChunks = const [],
  }) async* {
    throw Exception('RESOURCE_EXHAUSTED: 3574 >= 2048');
  }
}

void main() {
  group('ChatScreen', () {
    late ChatProvider chatProvider;

    setUp(() async {
      final vs = InMemoryVectorStore();
      await vs.initialize();
      final es = const MockEmbeddingService();
      final ls = MockLlmService(tokenDelay: Duration.zero);
      final rag = RagService(
        embeddingService: es,
        vectorStoreService: vs,
        llmService: ls,
      );
      chatProvider = ChatProvider(ragService: rag);
    });

    testWidgets('renders empty state and input field initially', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ChatProvider>.value(
            value: chatProvider,
            child: const ChatScreen(),
          ),
        ),
      );

      expect(find.text('Ask Smriti Anything'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.send), findsOneWidget);
    });

    testWidgets('sends message and renders bubbles', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ChatProvider>.value(
            value: chatProvider,
            child: const ChatScreen(),
          ),
        ),
      );

      // Enter text and pump a frame so _canSend updates the button state
      await tester.enterText(find.byType(TextField), 'Hello Smriti');
      await tester.pump();

      // Tap send
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(find.text('Hello Smriti'), findsOneWidget);
      expect(chatProvider.messages.length, equals(2));
    });

    testWidgets('displays raw error banner and dismiss button clears it',
        (tester) async {
      final vs = InMemoryVectorStore();
      await vs.initialize();
      final rag = RagService(
        embeddingService: const MockEmbeddingService(),
        vectorStoreService: vs,
        llmService: _ErrorLlmService(),
      );
      final errorProvider = ChatProvider(ragService: rag);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ChatProvider>.value(
            value: errorProvider,
            child: const ChatScreen(),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'Trigger error');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('RESOURCE_EXHAUSTED: 3574 >= 2048'),
        findsWidgets,
      );
      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(errorProvider.errorMessage, isNull);
      expect(find.byIcon(Icons.close), findsNothing);
    });
  });
}
