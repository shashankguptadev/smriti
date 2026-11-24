import '../models/document_info.dart';

/// Persists and queries vector embeddings with associated metadata.
abstract class VectorStoreService {
  /// Opens or prepares the vector store.
  Future<void> initialize();

  /// Closes the vector store and releases resources.
  Future<void> dispose();

  /// Inserts a vector [embedding] with its [documentId], [chunkText],
  /// and optional metadata ([fileName], [chunkIndex]).
  Future<void> insert({
    required String documentId,
    required String chunkText,
    required List<double> embedding,
    String fileName = '',
    int chunkIndex = 0,
  });

  /// Finds the top [k] nearest neighbors to the [queryEmbedding].
  /// Returns a list of maps containing:
  /// - 'documentId': String
  /// - 'fileName': String
  /// - 'chunkIndex': int
  /// - 'chunkText': String
  /// - 'score': double
  Future<List<Map<String, dynamic>>> query(
    List<double> queryEmbedding, {
    int k = 5,
  });

  /// Removes all vectors associated with [documentId].
  Future<void> deleteByDocumentId(String documentId);

  /// Returns a list of unique document IDs currently stored.
  Future<List<String>> listDocumentIds();

  /// Returns high-level summaries for all persisted documents.
  Future<List<DocumentInfo>> listDocumentSummaries();

  /// Returns all stored chunks across all documents.
  Future<List<Map<String, dynamic>>> getAllChunks();
}
