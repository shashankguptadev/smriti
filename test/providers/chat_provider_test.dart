import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/models/chat_message.dart';
import 'package:smriti/providers/chat_provider.dart';
import 'package:smriti/services/in_memory_vector_store.dart';
import 'package:smriti/services/mock_embedding_service.dart';
import 'package:smriti/services/mock_llm_service.dart';
import 'package:smriti/services/rag_service.dart';

void main() {
  group('ChatProvider', () {
    late InMemoryVectorStore vectorStore;
    late MockEmbeddingService embeddingService;
    late MockLlmService llmService;
    late RagService ragService;
    late ChatProvider chatProvider;

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

      chatProvider = ChatProvider(ragService: ragService);
    });

    tearDown(() async {
      await vectorStore.dispose();
      await llmService.dispose();
    });

    test('initial state has empty messages and idle status', () {
      expect(chatProvider.messages, isEmpty);
      expect(chatProvider.status, equals(ChatStatus.idle));
      expect(chatProvider.isStreaming, isFalse);
    });

    test('sendMessage adds user and assistant messages with streaming', () async {
      // Add a document chunk so citations are found
      final emb = await embeddingService.embed('Smriti vector');
      await vectorStore.insert(
        documentId: 'doc1',
        chunkText: 'Smriti stores vectors locally.',
        embedding: emb,
        fileName: 'kb.txt',
      );

      await chatProvider.sendMessage('How does Smriti work?');

      expect(chatProvider.messages.length, equals(2));
      expect(chatProvider.messages[0].role, equals(MessageRole.user));
      expect(chatProvider.messages[0].text, equals('How does Smriti work?'));

      expect(chatProvider.messages[1].role, equals(MessageRole.assistant));
      expect(chatProvider.messages[1].text, contains('Smriti stores vectors locally.'));
      expect(chatProvider.messages[1].sources, isNotEmpty);
      expect(chatProvider.messages[1].isStreaming, isFalse);
      expect(chatProvider.status, equals(ChatStatus.idle));
    });

    test('clearChat removes all conversation history', () async {
      await chatProvider.sendMessage('Hello');
      expect(chatProvider.messages, isNotEmpty);

      chatProvider.clearChat();
      expect(chatProvider.messages, isEmpty);
      expect(chatProvider.status, equals(ChatStatus.idle));
    });

    test('sendMessage ignores whitespace-only prompt', () async {
      await chatProvider.sendMessage('   ');
      expect(chatProvider.messages, isEmpty);
    });
  });
}
