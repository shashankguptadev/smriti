import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/services/in_memory_vector_store.dart';

void main() {
  group('VectorStore Persistence & Summaries', () {
    late InMemoryVectorStore store;

    setUp(() async {
      store = InMemoryVectorStore();
      await store.initialize();
    });

    tearDown(() async {
      await store.dispose();
    });

    test('listDocumentSummaries groups chunks and returns correct counts', () async {
      await store.insert(
        documentId: '/docs/syllabus.pdf',
        fileName: 'syllabus.pdf',
        chunkIndex: 0,
        chunkText: 'Module 1: Operating Systems',
        embedding: List.filled(384, 0.1),
      );
      await store.insert(
        documentId: '/docs/syllabus.pdf',
        fileName: 'syllabus.pdf',
        chunkIndex: 1,
        chunkText: 'Module 2: Process Scheduling',
        embedding: List.filled(384, 0.2),
      );
      await store.insert(
        documentId: '/docs/notes.txt',
        fileName: 'notes.txt',
        chunkIndex: 0,
        chunkText: 'Antigravity offline knowledge base notes',
        embedding: List.filled(384, 0.3),
      );

      final summaries = await store.listDocumentSummaries();
      expect(summaries.length, equals(2));

      final syllabus = summaries.firstWhere((s) => s.documentId == '/docs/syllabus.pdf');
      expect(syllabus.fileName, equals('syllabus.pdf'));
      expect(syllabus.chunkCount, equals(2));

      final notes = summaries.firstWhere((s) => s.documentId == '/docs/notes.txt');
      expect(notes.fileName, equals('notes.txt'));
      expect(notes.chunkCount, equals(1));
    });

    test('getAllChunks returns every chunk across documents', () async {
      await store.insert(
        documentId: 'docA',
        fileName: 'docA.txt',
        chunkIndex: 0,
        chunkText: 'First chunk',
        embedding: List.filled(384, 0.1),
      );
      await store.insert(
        documentId: 'docB',
        fileName: 'docB.txt',
        chunkIndex: 0,
        chunkText: 'Second chunk',
        embedding: List.filled(384, 0.2),
      );

      final chunks = await store.getAllChunks();
      expect(chunks.length, equals(2));
      expect(chunks.map((c) => c['chunkText']), containsAll(['First chunk', 'Second chunk']));
    });
  });
}
