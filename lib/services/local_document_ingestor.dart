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
    this.chunkSize = 800,
    this.chunkOverlap = 150,
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

  /// Splits [text] into overlapping chunks of approximately [chunkSize] characters,
  /// preferring clean sentence, line, or word boundaries.
  static List<String> chunkText(
    String text, {
    int chunkSize = 800,
    int chunkOverlap = 150,
  }) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (normalized.isEmpty) return [];

    if (normalized.length <= chunkSize) {
      return [normalized];
    }

    final chunks = <String>[];
    int start = 0;

    while (start < normalized.length) {
      int end = start + chunkSize;
      if (end >= normalized.length) {
        final chunk = normalized.substring(start).trim();
        if (chunk.isNotEmpty) {
          chunks.add(chunk);
        }
        break;
      }

      // Look for a clean boundary in the last 30% of the chunk window
      final searchFrom = start + (chunkSize * 0.70).toInt();
      int breakIndex = -1;

      // 1. Double newline (paragraph)
      final paragraphBreak = normalized.lastIndexOf('\n\n', end);
      if (paragraphBreak >= searchFrom) {
        breakIndex = paragraphBreak + 2;
      } else {
        // 2. Single newline
        final lineBreak = normalized.lastIndexOf('\n', end);
        if (lineBreak >= searchFrom) {
          breakIndex = lineBreak + 1;
        } else {
          // 3. Sentence boundary (. ! ?)
          final sentenceRegex = RegExp(r'[.!?]\s+');
          final sub = normalized.substring(searchFrom, end);
          final matches = sentenceRegex.allMatches(sub);
          if (matches.isNotEmpty) {
            breakIndex = searchFrom + matches.last.end;
          } else {
            // 4. Word boundary (space)
            final spaceIndex = normalized.lastIndexOf(' ', end);
            if (spaceIndex >= searchFrom) {
              breakIndex = spaceIndex + 1;
            }
          }
        }
      }

      final actualEnd = (breakIndex > start) ? breakIndex : end;
      final chunk = normalized.substring(start, actualEnd).trim();
      if (chunk.isNotEmpty) {
        chunks.add(chunk);
      }

      // Compute step with overlap, snapping to a space if available
      int nextStart = actualEnd - chunkOverlap;
      if (nextStart <= start) {
        nextStart = actualEnd;
      } else {
        final spaceAhead = normalized.indexOf(' ', nextStart);
        if (spaceAhead != -1 && spaceAhead < actualEnd) {
          nextStart = spaceAhead + 1;
        }
      }
      start = nextStart;
    }

    return chunks;
  }
}
