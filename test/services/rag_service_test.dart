import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/services/in_memory_vector_store.dart';
import 'package:smriti/services/mock_embedding_service.dart';
import 'package:smriti/services/mock_llm_service.dart';
import 'package:smriti/services/rag_service.dart';

void main() {
  group('RagService', () {
    late InMemoryVectorStore vectorStore;
    late MockEmbeddingService embeddingService;
    late MockLlmService llmService;
    late RagService ragService;

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
        topK: 2,
      );
    });

    tearDown(() async {
      await vectorStore.dispose();
      await llmService.dispose();
    });

    test('getSourceChunks queries vector store with question embedding', () async {
      final emb = await embeddingService.embed('Offline search');
      await vectorStore.insert(
        documentId: 'doc1',
        chunkText: 'Offline search is fast and private.',
        embedding: emb,
        fileName: 'privacy.txt',
      );

      final sources = await ragService.getSourceChunks('Offline search');
      expect(sources, isNotEmpty);
      expect(sources.first['chunkText'], contains('Offline search is fast'));
      expect(sources.first['fileName'], equals('privacy.txt'));
    });

    test('ask retrieves context and streams LLM answer', () async {
      final emb = await embeddingService.embed('Architecture');
      await vectorStore.insert(
        documentId: 'doc2',
        chunkText: 'Smriti uses ObjectBox and LiteRT.',
        embedding: emb,
        fileName: 'arch.txt',
      );

      final tokens = <String>[];
      await for (final token in ragService.ask('Tell me about Architecture')) {
        tokens.add(token);
      }

      final fullAnswer = tokens.join();
      expect(fullAnswer, contains('Smriti uses ObjectBox and LiteRT.'));
    });
  });
}
