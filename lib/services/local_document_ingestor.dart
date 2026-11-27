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
///
/// ## Improvements over v1
/// - **Focused chunk sizing:** `chunkSize` 700, `chunkOverlap` 150 so chunks
///   stay granular for retrieval precision while preserving complete thoughts.
/// - **Layout-aware PDF extraction:** uses `layoutText: true` (with whole-doc
///   and per-page fallbacks) to preserve inter-word spaces and table/column
///   structure on multi-column papers and timetables.
/// - **Structure-aware splitting:** headings (`##`, `#`, `---`) are treated as
///   the highest-priority split boundary, so section introductions stay with
///   their content.
/// - **Section heading injection:** when a chunk is split away from the nearest
///   preceding heading, a `[Section: …]` annotation is prepended so the LLM
///   always has a navigational anchor.
/// - **Table/list block preservation:** lines starting with `|`, `- `, `* ` or
///   `1. ` are never cut mid-block; the chunker keeps them intact even when
///   slightly over `chunkSize`.
///
/// Heavy file I/O, parsing, and chunking run inside [Isolate.run].
/// Scanned/image-based PDFs fall back to on-device OCR via Google ML Kit.
class LocalDocumentIngestor implements DocumentIngestor {
  final int chunkSize;
  final int chunkOverlap;

  const LocalDocumentIngestor({
    this.chunkSize = 700,
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
      // 1. Try native PDF text extraction inside Isolate
      final pdfResult = await Isolate.run(() => _extractPdfText(file.path));
      if (pdfResult.text.trim().isNotEmpty && !pdfResult.isSparse) {
        fullText = pdfResult.text;
      } else {
        // 2. Scanned / sparse PDF → page image rendering + ML Kit OCR
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
      final pageCount = document.pages.count;

      // Layout-preserving extraction keeps word spaces in multi-column papers
      // and keeps table rows aligned instead of concatenating adjacent tokens.
      final layoutText = extractor.extractText(layoutText: true);
      int bestNonWs = layoutText.replaceAll(RegExp(r'\s+'), '').length;
      String bestText = layoutText;

      // If layout extraction yields sparse output (< 200 non-whitespace chars/page),
      // try standard extraction and page-by-page extraction and keep whichever
      // yields the most text before deciding whether OCR fallback is needed.
      if (pageCount > 0 && (bestNonWs / pageCount) < 200) {
        final rawText = extractor.extractText();
        final rawNonWs = rawText.replaceAll(RegExp(r'\s+'), '').length;
        if (rawNonWs > bestNonWs) {
          bestText = rawText;
          bestNonWs = rawNonWs;
        }

        final pageBuffer = StringBuffer();
        for (int i = 0; i < pageCount; i++) {
          try {
            final pageText = extractor.extractText(
              startPageIndex: i,
              endPageIndex: i,
              layoutText: true,
            );
            if (pageText.trim().isNotEmpty) {
              pageBuffer.writeln(pageText.trim());
            }
          } catch (_) {
            // Skip unreadable pages
          }
        }
        final perPageText = pageBuffer.toString();
        final perPageNonWs = perPageText.replaceAll(RegExp(r'\s+'), '').length;
        if (perPageNonWs > bestNonWs) {
          bestText = perPageText;
          bestNonWs = perPageNonWs;
        }
      }

      final isSparse = pageCount > 0 && (bestNonWs / pageCount) < 200;
      return _PdfExtractResult(bestText, isSparse);
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

  // ─────────────────────────────────────────────────────────────────────────
  // Public chunking API
  // ─────────────────────────────────────────────────────────────────────────

  /// Splits [text] into overlapping chunks of approximately [chunkSize]
  /// characters with structure-aware boundaries and section heading injection.
  ///
  /// Split priority (highest → lowest):
  ///  0. Markdown/document heading boundary (`## `, `# `, `---`)
  ///  1. Double newline (paragraph boundary)
  ///  2. Single newline
  ///  3. Sentence boundary (`. ! ?`)
  ///  4. Word boundary (space)
  ///
  /// Table rows and list items are treated as atomic units and are never split
  /// mid-block even if slightly over [chunkSize].
  static List<String> chunkText(
    String text, {
    int chunkSize = 700,
    int chunkOverlap = 150,
  }) {
    final normalized = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    if (normalized.isEmpty) return [];

    if (normalized.length <= chunkSize) {
      return [normalized];
    }

    // Pre-split at heading boundaries first so each section starts a new chunk
    final sections = _splitAtHeadings(normalized);

    final chunks = <String>[];

    for (final section in sections) {
      final sectionChunks = _chunkSection(
        section,
        chunkSize: chunkSize,
        chunkOverlap: chunkOverlap,
      );
      for (final chunk in sectionChunks) {
        final trimmed = chunk.trim();
        if (trimmed.isNotEmpty) chunks.add(trimmed);
      }
    }

    return chunks;
  }

  /// Splits [text] at Markdown heading lines (`# `, `## `, …) and horizontal
  /// rules (`---`, `===`) so each section can be chunked independently with
  /// its heading preserved at the top.
  static List<String> _splitAtHeadings(String text) {
    final lines = text.split('\n');
    final sections = <String>[];
    final current = StringBuffer();

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final isHeading = RegExp(r'^#{1,6}\s').hasMatch(line);
      final isRule = RegExp(r'^(-{3,}|={3,})\s*$').hasMatch(line.trim());

      if ((isHeading || isRule) && current.isNotEmpty) {
        // Flush the current section before starting a new one
        final sec = current.toString().trim();
        if (sec.isNotEmpty) sections.add(sec);
        current.clear();
      }
      current.writeln(line);
    }

    final last = current.toString().trim();
    if (last.isNotEmpty) sections.add(last);
    return sections.isEmpty ? [text] : sections;
  }

  /// Chunks a single [section] of text using sliding-window logic with
  /// boundary-aware splitting. Tables and list blocks are kept intact.
  static List<String> _chunkSection(
    String section, {
    required int chunkSize,
    required int chunkOverlap,
  }) {
    if (section.length <= chunkSize) return [section];

    // Extract the heading line (first line, if it starts with # or is short)
    String? headingAnnotation;
    final firstLine = section.split('\n').first.trim();
    if (RegExp(r'^#{1,6}\s').hasMatch(firstLine)) {
      final headingText = firstLine.replaceAll(RegExp(r'^#{1,6}\s*'), '').trim();
      headingAnnotation = '[Section: $headingText]';
    }

    final chunks = <String>[];
    int start = 0;

    while (start < section.length) {
      int end = start + chunkSize;
      if (end >= section.length) {
        final chunk = section.substring(start).trim();
        if (chunk.isNotEmpty) {
          chunks.add(_annotate(chunk, headingAnnotation, chunks.isEmpty));
        }
        break;
      }

      // If we are inside a table or list block, extend to its end
      final candidateSlice = section.substring(start, end);
      final extendedEnd = _extendForBlock(section, end);
      if (extendedEnd > end && extendedEnd <= section.length) {
        end = extendedEnd;
      }

      // Look for a clean boundary in the last 30 % of the chunk window
      final searchFrom = start + (chunkSize * 0.70).toInt();
      int breakIndex = -1;

      // 1. Heading boundary (highest priority)
      final headingSubstr =
          section.substring(searchFrom, end < section.length ? end : section.length);
      final headingMatches = RegExp(r'\n#{1,6}\s').allMatches(headingSubstr);
      if (headingMatches.isNotEmpty) {
        breakIndex = searchFrom + headingMatches.last.start + 1; // +1 to keep \n
      }

      if (breakIndex < 0) {
        // 2. Double newline (paragraph)
        final paraBreak = section.lastIndexOf('\n\n', end);
        if (paraBreak >= searchFrom) {
          breakIndex = paraBreak + 2;
        }
      }

      if (breakIndex < 0) {
        // 3. Single newline
        final lineBreak = section.lastIndexOf('\n', end);
        if (lineBreak >= searchFrom) {
          breakIndex = lineBreak + 1;
        }
      }

      if (breakIndex < 0) {
        // 4. Sentence boundary (. ! ?)
        final sentenceRegex = RegExp(r'[.!?]\s+');
        final sub = section.substring(searchFrom, end);
        final matches = sentenceRegex.allMatches(sub);
        if (matches.isNotEmpty) {
          breakIndex = searchFrom + matches.last.end;
        }
      }

      if (breakIndex < 0) {
        // 5. Word boundary (space)
        final spaceIndex = section.lastIndexOf(' ', end);
        if (spaceIndex >= searchFrom) {
          breakIndex = spaceIndex + 1;
        }
      }

      final actualEnd = (breakIndex > start) ? breakIndex : end;
      final chunk = section.substring(start, actualEnd).trim();
      if (chunk.isNotEmpty) {
        chunks.add(_annotate(chunk, headingAnnotation, chunks.isEmpty));
      }

      // Advance with overlap, snapping to nearest word boundary
      int nextStart = actualEnd - chunkOverlap;
      if (nextStart <= start) {
        nextStart = actualEnd;
      } else {
        final spaceAhead = section.indexOf(' ', nextStart);
        if (spaceAhead != -1 && spaceAhead < actualEnd) {
          nextStart = spaceAhead + 1;
        }
      }
      start = nextStart;

      // Safety: ensure we always advance
      if (candidateSlice.isEmpty) break;
    }

    return chunks;
  }

  /// If [end] lands in the middle of a table row (`|`) or list item (`- `,
  /// `* `, `N. `), returns the index after the block ends; otherwise [end].
  static int _extendForBlock(String text, int end) {
    if (end >= text.length) return end;
    // Find the start of the current line
    final lineStart = text.lastIndexOf('\n', end - 1) + 1;
    final lineContent = text.substring(lineStart, end).trim();
    final isTableRow = lineContent.startsWith('|');
    final isListItem = RegExp(r'^[-*]\s|^\d+\.\s').hasMatch(lineContent);
    if (!isTableRow && !isListItem) return end;

    // Extend to the end of the block (until a non-table/list line)
    int i = end;
    while (i < text.length) {
      final nl = text.indexOf('\n', i);
      if (nl == -1) {
        i = text.length;
        break;
      }
      final nextLine = text.substring(nl + 1, text.indexOf('\n', nl + 1) == -1 ? text.length : text.indexOf('\n', nl + 1)).trim();
      final nextIsTable = nextLine.startsWith('|');
      final nextIsList = RegExp(r'^[-*]\s|^\d+\.\s').hasMatch(nextLine);
      if (!nextIsTable && !nextIsList && nextLine.isNotEmpty) break;
      i = nl + 1;
    }
    return i;
  }

  /// Prepends a `[Section: …]` annotation to [chunk] when it is not the first
  /// chunk of its section (first chunk already starts with the heading text)
  /// and a [headingAnnotation] is available.
  static String _annotate(
    String chunk,
    String? headingAnnotation,
    bool isFirstChunk,
  ) {
    if (headingAnnotation == null || isFirstChunk) return chunk;
    if (chunk.startsWith('[Section:')) return chunk;
    return '$headingAnnotation\n$chunk';
  }
}
