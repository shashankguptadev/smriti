import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/services/local_document_ingestor.dart';

void main() {
  group('LocalDocumentIngestor', () {
    const ingestor = LocalDocumentIngestor(chunkSize: 100, chunkOverlap: 20);
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('smriti_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('supportedExtensions contains expected formats', () {
      expect(
        ingestor.supportedExtensions,
        containsAll(['.pdf', '.txt', '.md', '.png', '.jpg', '.jpeg']),
      );
    });

    test('ingests .txt file with overlapping chunks', () async {
      final file = File('${tempDir.path}/sample.txt');
      final content = 'A' * 250;
      await file.writeAsString(content);

      final chunks = await ingestor.ingest(file);

      expect(chunks, isNotEmpty);
      expect(chunks.length, greaterThanOrEqualTo(2));
      for (final chunk in chunks) {
        expect(chunk.length, lessThanOrEqualTo(100));
      }
    });

    test('ingests .md file correctly', () async {
      final file = File('${tempDir.path}/notes.md');
      await file.writeAsString('# Offline Knowledge\n\nSmriti stores local documents.');

      final chunks = await ingestor.ingest(file);

      expect(chunks.length, equals(1));
      expect(chunks.first, contains('Smriti stores local documents.'));
    });

    test('rejects unsupported file extension', () async {
      final file = File('${tempDir.path}/data.docx');
      await file.writeAsString('Word document text');

      expect(() => ingestor.ingest(file), throwsA(isA<UnsupportedError>()));
    });

    test('throws when file does not exist', () async {
      final file = File('${tempDir.path}/non_existent.txt');
      expect(() => ingestor.ingest(file), throwsA(isA<FileSystemException>()));
    });

    test('chunkText handles empty string', () {
      expect(LocalDocumentIngestor.chunkText(''), isEmpty);
      expect(LocalDocumentIngestor.chunkText('   \n  '), isEmpty);
    });

    test('chunkText respects chunkOverlap', () {
      const text = 'abcdefghijklmnopqrstuvwxyz';
      final chunks = LocalDocumentIngestor.chunkText(
        text,
        chunkSize: 10,
        chunkOverlap: 2,
      );

      expect(chunks.length, equals(3));
      // First chunk: abcdefghij (length 10)
      // Step: 10 - 2 = 8, next starts at index 8 ('ij...')
      expect(chunks[0], equals('abcdefghij'));
      expect(chunks[1].startsWith('ij'), isTrue);
      // Step: 8 + 8 = 16, next starts at index 16 ('qr...')
      expect(chunks[2].startsWith('qr'), isTrue);
    });
  });
}
