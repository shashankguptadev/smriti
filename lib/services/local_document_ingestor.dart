import 'dart:io';
import 'dart:isolate';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../core/services/document_ingestor.dart';

class _PdfExtractResult {
  final String text;
  final bool isSparse;

  _PdfExtractResult(this.text, this.isSparse);
}

/// Concrete [DocumentIngestor] supporting PDF, TXT, Markdown, PNG, JPG, and JPEG.
/// Heavy file I/O, parsing, and text chunking run inside [Isolate.run].
/// Scanned/image-based PDFs and images fall back to on-device OCR via Google ML Kit.
class LocalDocumentIngestor implements DocumentIngestor {
  final int chunkSize;
  final int chunkOverlap;

  const LocalDocumentIngestor({
    this.chunkSize = 800,
    this.chunkOverlap = 150,
  });

  @override
  List<String> get supportedExtensions =>
      const ['.pdf', '.txt', '.md', '.png', '.jpg', '.jpeg'];

  @override
  Future<List<String>> ingest(File file) async {
    final ext = p.extension(file.path).toLowerCase();
    if (!supportedExtensions.contains(ext)) {
      throw UnsupportedError(
        'Unsupported file extension "$ext". Supported: ${supportedExtensions.join(', ')}',
      );
    }

    if (!file.existsSync()) {
      throw FileSystemException('File not found', file.path);
    }

    String fullText = '';
    if (ext == '.png' || ext == '.jpg' || ext == '.jpeg') {
      fullText = await _performOcrOnImage(file.path);
    } else if (ext == '.pdf') {
      // 1. First try native PDF text extraction inside Isolate
      final pdfResult = await Isolate.run(() => _extractPdfText(file.path));
      if (pdfResult.text.trim().isNotEmpty && !pdfResult.isSparse) {
        fullText = pdfResult.text;
      } else {
        // 2. Scanned or sparse PDF: fall back to page image rendering + ML Kit OCR
        final ocrText = await _performOcrOnPdf(file.path);
        fullText = ocrText.isNotEmpty ? ocrText : pdfResult.text;
      }
    } else {
      fullText = await Isolate.run(() => File(file.path).readAsStringSync());
    }

    return chunkText(fullText, chunkSize: chunkSize, chunkOverlap: chunkOverlap);
  }

  static _PdfExtractResult _extractPdfText(String filePath) {
    final file = File(filePath);
    final bytes = file.readAsBytesSync();
    final document = PdfDocument(inputBytes: bytes);
    try {
      final extractor = PdfTextExtractor(document);
      final text = extractor.extractText();
      final pageCount = document.pages.count;
      final nonWhitespace = text.replaceAll(RegExp(r'\s+'), '').length;
      final isSparse = pageCount > 0 && (nonWhitespace / pageCount) < 30;
      return _PdfExtractResult(text, isSparse);
    } finally {
      document.dispose();
    }
  }

  Future<String> _performOcrOnImage(String filePath) async {
    try {
      final inputImage = InputImage.fromFilePath(filePath);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final recognizedText = await textRecognizer.processImage(inputImage);
        return recognizedText.text;
      } finally {
        await textRecognizer.close();
      }
    } catch (_) {
      // Fallback for host runner or non-platform environments
      return '';
    }
  }

  Future<String> _performOcrOnPdf(String filePath) async {
    try {
      final pdfDoc = await pdfx.PdfDocument.openFile(filePath);
      final buffer = StringBuffer();
      final tempDir = await Directory.systemTemp.createTemp('smriti_ocr_');

      try {
        for (int i = 1; i <= pdfDoc.pagesCount; i++) {
          final page = await pdfDoc.getPage(i);
          try {
            final pageImage = await page.render(
              width: page.width * 2,
              height: page.height * 2,
              format: pdfx.PdfPageImageFormat.png,
            );
            if (pageImage != null) {
              final pageFile = File('${tempDir.path}/page_$i.png');
              await pageFile.writeAsBytes(pageImage.bytes);
              final pageText = await _performOcrOnImage(pageFile.path);
              if (pageText.isNotEmpty) {
                buffer.writeln(pageText);
              }
            }
          } finally {
            await page.close();
          }
        }
      } finally {
        await pdfDoc.close();
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      }
      return buffer.toString();
    } catch (_) {
      return '';
    }
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
