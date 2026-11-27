import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/models/chat_message.dart';
import 'package:smriti/core/services/llm_service.dart';
import 'package:smriti/providers/chat_provider.dart';
import 'package:smriti/providers/model_manager_provider.dart';
import 'package:smriti/services/in_memory_vector_store.dart';
import 'package:smriti/services/mock_embedding_service.dart';
import 'package:smriti/services/mock_llm_service.dart';
import 'package:smriti/services/rag_service.dart';

class _FailingLlmService implements LlmService {
  final Object error;
  _FailingLlmService(this.error);

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
    throw error;
  }
}

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

    test('sendMessage preserves raw SDK error message and clearError resets it',
        () async {
      const sdkError =
          'ContextLimitException: RESOURCE_EXHAUSTED: 3574 >= 2048';
      final failingRag = RagService(
        embeddingService: embeddingService,
        vectorStoreService: vectorStore,
        llmService: _FailingLlmService(Exception(sdkError)),
      );
      final failingProvider = ChatProvider(ragService: failingRag);

      await failingProvider.sendMessage('Hello');

      expect(failingProvider.status, equals(ChatStatus.error));
      expect(failingProvider.errorMessage, contains(sdkError));
      expect(failingProvider.messages.last.text, contains(sdkError));

      failingProvider.clearError();
      expect(failingProvider.errorMessage, isNull);
      expect(failingProvider.status, equals(ChatStatus.idle));
    });

    test('shows "Model is loading..." then greeting when real model loads',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('cp_mm_');
      addTearDown(() async {
        if (tempDir.existsSync()) await tempDir.delete(recursive: true);
      });
      final modelFile = File('${tempDir.path}/models/qwen.litertlm');
      await modelFile.create(recursive: true);
      await modelFile.writeAsString('weights');

      final mm = ModelManagerProvider(
        documentsDirectoryResolver: () async => tempDir,
      );
      await mm.checkModelAvailability();
      mm.setModelLoadingInBackground(true);

      final provider = ChatProvider(ragService: ragService, modelManager: mm);
      addTearDown(provider.dispose);

      expect(provider.messages.length, equals(1));
      expect(provider.messages.first.isStreaming, isTrue);
      expect(provider.messages.first.loadingText, equals('Model is loading...'));
      expect(provider.messages.first.text, isEmpty);

      mm.setModelLoadingInBackground(false);

      expect(provider.messages.length, equals(1));
      expect(provider.messages.first.isStreaming, isFalse);
      expect(
        provider.messages.first.text,
        equals('Hello, I am Smriti. Your offline personal knowledge assistant'),
      );
    });

    test('removes loading bubble and surfaces error if background load fails',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('cp_err_');
      addTearDown(() async {
        if (tempDir.existsSync()) await tempDir.delete(recursive: true);
      });
      final modelFile = File('${tempDir.path}/models/qwen.litertlm');
      await modelFile.create(recursive: true);
      await modelFile.writeAsString('weights');

      final mm = ModelManagerProvider(
        documentsDirectoryResolver: () async => tempDir,
      );
      await mm.checkModelAvailability();
      mm.setModelLoadingInBackground(true);

      final provider = ChatProvider(ragService: ragService, modelManager: mm);
      addTearDown(provider.dispose);

      expect(provider.messages.length, equals(1));

      mm.setEngineError('Model failed to load: corrupt file');

      expect(provider.messages, isEmpty);
      expect(provider.errorMessage, contains('corrupt file'));
    });
  });
}
