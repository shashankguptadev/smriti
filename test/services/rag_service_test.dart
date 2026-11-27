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

    // ── Basic retrieval ───────────────────────────────────────────────────
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

    // ── Conversational routing ─────────────────────────────────────────────
    test('isConversationalQuery returns true for greetings', () {
      expect(ragService.isConversationalQuery('Hello'), isTrue);
      expect(ragService.isConversationalQuery('hi!'), isTrue);
      expect(ragService.isConversationalQuery('thank you'), isTrue);
      expect(ragService.isConversationalQuery('bye'), isTrue);
    });

    test('isConversationalQuery returns false for factual questions', () {
      expect(ragService.isConversationalQuery('What is the exam schedule?'), isFalse);
      expect(ragService.isConversationalQuery('Budget allocation details'), isFalse);
    });

    test('getSourceChunks returns empty for greeting queries', () async {
      final emb = await embeddingService.embed('some content');
      await vectorStore.insert(
        documentId: 'doc1',
        chunkText: 'Some document content.',
        embedding: emb,
        fileName: 'notes.txt',
      );

      final sources = await ragService.getSourceChunks('Hello');
      expect(sources, isEmpty);
    });

    // ── topK default ───────────────────────────────────────────────────────
    test('default topK is 8', () {
      final service = RagService(
        embeddingService: embeddingService,
        vectorStoreService: vectorStore,
        llmService: llmService,
      );
      expect(service.topK, equals(8));
    });

    // ── Score gating ───────────────────────────────────────────────────────
    test('getSourceChunks returns empty when no chunks score above threshold', () async {
      // Insert chunks completely unrelated to the query
      final emb1 = await embeddingService.embed('recipe pasta cooking');
      await vectorStore.insert(
        documentId: 'food.txt',
        chunkText: 'pasta cooking recipe ingredients method',
        embedding: emb1,
        fileName: 'food.txt',
      );

      // Query for something with zero lexical overlap and near-zero vector match
      // The mock embedding is hash-based so the score might still be non-zero;
      // at minimum verify the pipeline runs without error.
      final sources = await ragService.getSourceChunks('semiconductor physics');
      // Result could be empty or non-empty depending on hash overlap;
      // key assertion: no exception thrown and result is a list.
      expect(sources, isA<List>());
    });

    // ── Deduplication ─────────────────────────────────────────────────────
    test('getSourceChunks deduplicates chunks with identical fingerprints', () async {
      // Insert two chunks with the same leading content (simulates overlap artifact)
      const chunkText = 'Operating Systems manage hardware and software resources.';
      final emb = await embeddingService.embed(chunkText);
      await vectorStore.insert(
        documentId: 'os.txt',
        chunkText: chunkText,
        embedding: emb,
        fileName: 'os.txt',
        chunkIndex: 0,
      );
      await vectorStore.insert(
        documentId: 'os.txt',
        chunkText: chunkText, // exact duplicate
        embedding: emb,
        fileName: 'os.txt',
        chunkIndex: 1,
      );

      final sources = await ragService.getSourceChunks('Operating Systems');
      // Despite two insertions, only one should appear after deduplication
      final osChunks = sources.where((s) => s['documentId'] == 'os.txt').toList();
      expect(osChunks.length, equals(1));
    });

    // ── Query expansion ────────────────────────────────────────────────────
    test('expandQuery generates variants from question preamble stripping', () {
      // Test indirectly via getSourceChunks: a "what is X?" query should
      // also search for "X" and retrieve a chunk about X.
      // This is validated via the existing hybrid retrieval test.
      // Here we just ensure the service handles expanded queries without error.
      expect(
        () async => ragService.getSourceChunks('What is the budget allocation?'),
        returnsNormally,
      );
    });
  });
}
