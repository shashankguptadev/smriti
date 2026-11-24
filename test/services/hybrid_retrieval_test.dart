import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/services/edge_embedding_service.dart';
import 'package:smriti/services/in_memory_vector_store.dart';
import 'package:smriti/services/mock_llm_service.dart';
import 'package:smriti/services/rag_service.dart';

void main() {
  group('Hybrid Retrieval & Conversational Routing', () {
    late InMemoryVectorStore vectorStore;
    late EdgeEmbeddingService embeddingService;
    late MockLlmService llmService;
    late RagService ragService;

    setUp(() async {
      vectorStore = InMemoryVectorStore();
      await vectorStore.initialize();

      embeddingService = EdgeEmbeddingService(dimensions: 384);
      await embeddingService.initialize();

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

    test('conversational greeting "Hello" and "thanks" return zero source chunks', () async {
      // Ingest arbitrary document
      final emb = await embeddingService.embed('Document chunk');
      await vectorStore.insert(
        documentId: 'doc1',
        chunkText: 'Some general notes and documentation here.',
        embedding: emb,
        fileName: 'notes.txt',
      );

      final helloSources = await ragService.getSourceChunks('Hello');
      expect(helloSources, isEmpty);

      final hiSources = await ragService.getSourceChunks('hi!');
      expect(hiSources, isEmpty);

      final thanksSources = await ragService.getSourceChunks('thank you');
      expect(thanksSources, isEmpty);
    });

    test('timetable query "5th semester CSE first exam" accurately retrieves the exact schedule chunk', () async {
      // Chunk 1: 3rd semester ECE
      final c1 = '3rd semester ECE exam schedule: ECT201 Logic Circuit Design on Nov 10, ECT203 Signals and Systems on Nov 14.';
      await vectorStore.insert(
        documentId: 'timetable.pdf',
        fileName: 'timetable.pdf',
        chunkIndex: 0,
        chunkText: c1,
        embedding: await embeddingService.embed(c1),
      );

      // Chunk 2: 5th semester CSE
      final c2 = '5th semester CSE first exam: CST309 Operating Systems on Oct 24. Second exam: CST301 Formal Languages on Oct 28.';
      await vectorStore.insert(
        documentId: 'timetable.pdf',
        fileName: 'timetable.pdf',
        chunkIndex: 1,
        chunkText: c2,
        embedding: await embeddingService.embed(c2),
      );

      // Chunk 3: 7th semester ME
      final c3 = '7th semester ME schedule: MET401 Design of Machine Elements on Nov 05, MET403 Thermal Engineering on Nov 08.';
      await vectorStore.insert(
        documentId: 'timetable.pdf',
        fileName: 'timetable.pdf',
        chunkIndex: 2,
        chunkText: c3,
        embedding: await embeddingService.embed(c3),
      );

      final sources = await ragService.getSourceChunks('5th semester CSE first exam');
      expect(sources, isNotEmpty);
      expect(sources.first['chunkText'], contains('5th semester CSE first exam: CST309 Operating Systems'));
      expect(sources.first['chunkIndex'], equals(1));
    });
  });
}

