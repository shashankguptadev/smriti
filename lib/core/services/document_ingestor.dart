import 'dart:io';

/// Reads a document file, extracts text, and splits it into chunks.
abstract class DocumentIngestor {
  /// Ingests the given [file] and returns a list of text chunks.
  /// Each chunk is a substring of the document suitable for embedding.
  Future<List<String>> ingest(File file);

  /// The file extensions this ingestor supports (e.g., ['.pdf', '.txt']).
  List<String> get supportedExtensions;
}
