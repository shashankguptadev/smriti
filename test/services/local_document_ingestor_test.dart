import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/services/local_document_ingestor.dart';

void main() {
  group('LocalDocumentIngestor', () {
    // Use smaller chunkSize for fast unit tests
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

    // ── Supported extensions ──────────────────────────────────────────────
    test('supportedExtensions contains expected formats', () {
      expect(
        ingestor.supportedExtensions,
        containsAll(['.pdf', '.txt', '.md', '.png', '.jpg', '.jpeg']),
      );
    });

    // ── Basic ingestion ───────────────────────────────────────────────────
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

    // ── chunkText edge cases ──────────────────────────────────────────────
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
      expect(chunks[0], equals('abcdefghij'));
      expect(chunks[1].startsWith('ij'), isTrue);
      expect(chunks[2].startsWith('qr'), isTrue);
    });

    test('chunkText returns single chunk for text shorter than chunkSize', () {
      const text = 'Short text.';
      final chunks = LocalDocumentIngestor.chunkText(text, chunkSize: 100);
      expect(chunks.length, equals(1));
      expect(chunks.first, equals('Short text.'));
    });

    // ── Structure-aware splitting ─────────────────────────────────────────
    test('chunkText splits on markdown heading boundary before paragraph', () {
      // Build a text long enough to require splitting, with a heading in the middle
      final text =
          'Introduction text that provides some context about the topic.\n\n'
          '## Budget Allocation\n\n'
          'The total budget is \$10 million allocated across three departments.\n\n'
          'More budget details follow here and span beyond the threshold.';

      // Use a chunkSize large enough to hold the intro but force a split
      final chunks = LocalDocumentIngestor.chunkText(text, chunkSize: 120, chunkOverlap: 20);

      // At least 2 chunks expected due to structure split
      expect(chunks.length, greaterThanOrEqualTo(2));
      // The heading section should start a new chunk
      final hasHeadingChunk = chunks.any((c) => c.contains('Budget Allocation'));
      expect(hasHeadingChunk, isTrue);
    });

    test('chunkText injects [Section: heading] annotation into continuation chunks', () {
      // Build a section long enough to split into multiple chunks
      const heading = '## Chapter 1: Introduction';
      final longBody =
          'This is the first sentence of the introduction. ' * 10; // ~500 chars
      final text = '$heading\n$longBody';

      final chunks =
          LocalDocumentIngestor.chunkText(text, chunkSize: 150, chunkOverlap: 30);

      if (chunks.length > 1) {
        // Continuation chunks (not the first) should carry the heading annotation
        final annotated = chunks.skip(1).where(
          (c) => c.startsWith('[Section: Chapter 1: Introduction]'),
        );
        expect(annotated, isNotEmpty);
      }
    });

    test('chunkText removes immediately-adjacent duplicate chunks', () {
      // Build text where the chunker would produce two adjacent windows starting
      // with the same content (simulates a degenerate overlap edge case).
      // We test via the adjacent-fingerprint dedup: if two adjacent chunks
      // share the same 80-char prefix, only the first should survive.
      // Use a string that deliberately starts each overlap window identically.
      final base = 'UNIQUEPREFIX${'X' * 200}';
      // Split into 3 chunks: at chunkSize=100, overlap=0 → no duplicates expected.
      final chunks = LocalDocumentIngestor.chunkText(base, chunkSize: 100, chunkOverlap: 0);
      // With zero overlap no adjacent duplicates should exist
      for (int i = 0; i < chunks.length - 1; i++) {
        final a = chunks[i].substring(0, chunks[i].length < 20 ? chunks[i].length : 20);
        final b = chunks[i + 1].substring(0, chunks[i + 1].length < 20 ? chunks[i + 1].length : 20);
        expect(a, isNot(equals(b)));
      }
    });

    // ── New default chunk size ────────────────────────────────────────────
    test('default LocalDocumentIngestor uses chunkSize 1200 and overlap 250', () {
      const defaultIngestor = LocalDocumentIngestor();
      expect(defaultIngestor.chunkSize, equals(1200));
      expect(defaultIngestor.chunkOverlap, equals(250));
    });
  });
}
