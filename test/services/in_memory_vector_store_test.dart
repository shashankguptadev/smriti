import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/services/in_memory_vector_store.dart';

void main() {
  group('InMemoryVectorStore', () {
    late InMemoryVectorStore store;

    setUp(() async {
      store = InMemoryVectorStore();
      await store.initialize();
    });

    tearDown(() async {
      await store.dispose();
    });

    test('lifecycle initializes and disposes correctly', () async {
      final s = InMemoryVectorStore();
      await s.initialize();
      await s.insert(
        documentId: 'doc1',
        chunkText: 'test',
        embedding: [1.0, 0.0],
      );
      await s.dispose();
      expect(() => s.listDocumentIds(), throwsStateError);
    });

    test('inserts and lists unique document IDs', () async {
      await store.insert(
        documentId: 'doc1',
        chunkText: 'chunk 0',
        embedding: [1.0, 0.0, 0.0],
        chunkIndex: 0,
      );
      await store.insert(
        documentId: 'doc1',
        chunkText: 'chunk 1',
        embedding: [0.9, 0.1, 0.0],
        chunkIndex: 1,
      );
      await store.insert(
        documentId: 'doc2',
        chunkText: 'chunk 0',
        embedding: [0.0, 1.0, 0.0],
        chunkIndex: 0,
      );

      final docIds = await store.listDocumentIds();
      expect(docIds, containsAll(['doc1', 'doc2']));
      expect(docIds.length, equals(2));
    });

    test('queries nearest neighbors by cosine distance', () async {
      await store.insert(
        documentId: 'doc_exact',
        chunkText: 'Exact match chunk',
        embedding: [1.0, 0.0, 0.0],
        fileName: 'exact.txt',
      );
      await store.insert(
        documentId: 'doc_orthogonal',
        chunkText: 'Orthogonal chunk',
        embedding: [0.0, 1.0, 0.0],
        fileName: 'ortho.txt',
      );
      await store.insert(
        documentId: 'doc_opposite',
        chunkText: 'Opposite chunk',
        embedding: [-1.0, 0.0, 0.0],
        fileName: 'oppo.txt',
      );

      final results = await store.query([1.0, 0.0, 0.0], k: 3);

      expect(results.length, equals(3));
      // Exact match has cosine distance ~ 0.0
      expect(results[0]['documentId'], equals('doc_exact'));
      expect(results[0]['score'], closeTo(0.0, 0.001));

      // Orthogonal has cosine distance ~ 1.0
      expect(results[1]['documentId'], equals('doc_orthogonal'));
      expect(results[1]['score'], closeTo(1.0, 0.001));

      // Opposite has cosine distance ~ 2.0
      expect(results[2]['documentId'], equals('doc_opposite'));
      expect(results[2]['score'], closeTo(2.0, 0.001));
    });

    test('deletes chunks by documentId', () async {
      await store.insert(
        documentId: 'doc_to_keep',
        chunkText: 'Keep this',
        embedding: [0.5, 0.5],
      );
      await store.insert(
        documentId: 'doc_to_delete',
        chunkText: 'Delete this 1',
        embedding: [0.1, 0.9],
      );
      await store.insert(
        documentId: 'doc_to_delete',
        chunkText: 'Delete this 2',
        embedding: [0.2, 0.8],
      );

      expect(await store.listDocumentIds(), containsAll(['doc_to_keep', 'doc_to_delete']));

      await store.deleteByDocumentId('doc_to_delete');

      final remaining = await store.listDocumentIds();
      expect(remaining, equals(['doc_to_keep']));

      final queryResults = await store.query([0.1, 0.9], k: 10);
      expect(queryResults.every((r) => r['documentId'] == 'doc_to_keep'), isTrue);
    });

    test('query returns empty list when store is empty', () async {
      final results = await store.query([1.0, 2.0], k: 5);
      expect(results, isEmpty);
    });

    test('getChunksByDocumentId returns sorted chunks for the given doc', () async {
      // Insert 2 chunks for doc-A (in reverse order) and 1 for doc-B.
      await store.insert(
        documentId: 'doc-A',
        chunkText: 'Second chunk of A',
        embedding: [0.1, 0.2],
        chunkIndex: 1,
      );
      await store.insert(
        documentId: 'doc-A',
        chunkText: 'First chunk of A',
        embedding: [0.3, 0.4],
        chunkIndex: 0,
      );
      await store.insert(
        documentId: 'doc-B',
        chunkText: 'Only chunk of B',
        embedding: [0.5, 0.6],
        chunkIndex: 0,
      );

      final chunksA = await store.getChunksByDocumentId('doc-A');
      expect(chunksA.length, equals(2));
      // Must be sorted ascending by chunkIndex.
      expect(chunksA[0]['chunkIndex'], equals(0));
      expect(chunksA[0]['chunkText'], equals('First chunk of A'));
      expect(chunksA[1]['chunkIndex'], equals(1));
      expect(chunksA[1]['chunkText'], equals('Second chunk of A'));

      // doc-B isolation.
      final chunksB = await store.getChunksByDocumentId('doc-B');
      expect(chunksB.length, equals(1));
      expect(chunksB[0]['chunkText'], equals('Only chunk of B'));

      // Non-existent doc returns empty list.
      final chunksNone = await store.getChunksByDocumentId('doc-X');
      expect(chunksNone, isEmpty);
    });
  });
}

