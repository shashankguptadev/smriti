import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../core/services/document_ingestor.dart';

/// Concrete [DocumentIngestor] supporting PDF, TXT, and Markdown files.
/// Heavy file I/O, parsing, and text chunking run inside [Isolate.run]
/// to keep the main UI isolate responsive.
class LocalDocumentIngestor implements DocumentIngestor {
  final int chunkSize;
  final int chunkOverlap;

  const LocalDocumentIngestor({
    this.chunkSize = 500,
    this.chunkOverlap = 50,
  });

  @override
  List<String> get supportedExtensions => const ['.pdf', '.txt', '.md'];

  @override
  Future<List<String>> ingest(File file) async {
    final ext = p.extension(file.path).toLowerCase();
    if (!supportedExtensions.contains(ext)) {
      throw UnsupportedError(
        'Unsupported file extension "$ext". Supported: ${supportedExtensions.join(', ')}',
      );
    }

    final filePath = file.path;
    final size = chunkSize;
    final overlap = chunkOverlap;

    return Isolate.run(() => _extractAndChunk(filePath, ext, size, overlap));
  }

  static List<String> _extractAndChunk(
    String filePath,
    String ext,
    int chunkSize,
    int chunkOverlap,
  ) {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileSystemException('File not found', filePath);
    }

    String fullText;
    if (ext == '.pdf') {
      final bytes = file.readAsBytesSync();
      final document = PdfDocument(inputBytes: bytes);
      try {
        final extractor = PdfTextExtractor(document);
        fullText = extractor.extractText();
      } finally {
        document.dispose();
      }
    } else {
      fullText = file.readAsStringSync();
    }

    return chunkText(fullText, chunkSize: chunkSize, chunkOverlap: chunkOverlap);
  }

  /// Splits [text] into overlapping chunks of approximately [chunkSize] characters.
  static List<String> chunkText(
    String text, {
    int chunkSize = 500,
    int chunkOverlap = 50,
  }) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (normalized.isEmpty) return [];

    if (normalized.length <= chunkSize) {
      return [normalized];
    }

    final chunks = <String>[];
    final step = (chunkSize - chunkOverlap) > 0 ? (chunkSize - chunkOverlap) : 1;
    int start = 0;

    while (start < normalized.length) {
      int end = start + chunkSize;
      if (end > normalized.length) {
        end = normalized.length;
      }

      final chunk = normalized.substring(start, end).trim();
      if (chunk.isNotEmpty) {
        chunks.add(chunk);
      }

      if (end >= normalized.length) break;
      start += step;
    }

    return chunks;
  }
}
