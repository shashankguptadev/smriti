import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/providers/knowledge_base_provider.dart';
import 'package:smriti/services/in_memory_vector_store.dart';
import 'package:smriti/services/local_document_ingestor.dart';
import 'package:smriti/services/mock_embedding_service.dart';

void main() {
  group('KnowledgeBaseProvider', () {
    late InMemoryVectorStore vectorStore;
    late MockEmbeddingService embeddingService;
    late LocalDocumentIngestor ingestor;
    late KnowledgeBaseProvider provider;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('kb_test_');
      vectorStore = InMemoryVectorStore();
      await vectorStore.initialize();
      embeddingService = const MockEmbeddingService();
      ingestor = const LocalDocumentIngestor(chunkSize: 100, chunkOverlap: 10);

      provider = KnowledgeBaseProvider(
        ingestor: ingestor,
        embeddingService: embeddingService,
        vectorStoreService: vectorStore,
      );
    });

    tearDown(() async {
      await vectorStore.dispose();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('initial state is idle with empty documents', () {
      expect(provider.documents, isEmpty);
      expect(provider.status, equals(IngestionStatus.idle));
      expect(provider.isIngesting, isFalse);
      expect(provider.errorMessage, isNull);
    });

    test('ingests .txt file and updates documents and vector store', () async {
      final file = File('${tempDir.path}/manual.txt');
      await file.writeAsString('Flutter is an open source framework by Google for building apps.');

      final success = await provider.ingestFile(file);

      expect(success, isTrue);
      expect(provider.status, equals(IngestionStatus.idle));
      expect(provider.documents.length, equals(1));
      expect(provider.documents.first.fileName, equals('manual.txt'));
      expect(provider.documents.first.chunkCount, greaterThanOrEqualTo(1));

      final storedIds = await vectorStore.listDocumentIds();
      expect(storedIds, contains(file.path));
    });

    test('deletes document and removes vectors', () async {
      final file = File('${tempDir.path}/notes.txt');
      await file.writeAsString('Meeting notes for project Smriti.');
      await provider.ingestFile(file);

      expect(provider.documents.length, equals(1));

      await provider.deleteDocument(file.path);

      expect(provider.documents, isEmpty);
      final storedIds = await vectorStore.listDocumentIds();
      expect(storedIds, isEmpty);
    });

    test('handles unsupported file gracefully with error status', () async {
      final file = File('${tempDir.path}/image.png');
      await file.writeAsString('fake image data');

      final success = await provider.ingestFile(file);

      expect(success, isFalse);
      expect(provider.status, equals(IngestionStatus.error));
      expect(provider.errorMessage, isNotNull);
    });
  });
}
