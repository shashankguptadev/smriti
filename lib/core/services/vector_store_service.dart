/// Persists and queries vector embeddings with associated metadata.
abstract class VectorStoreService {
  /// Inserts a vector [embedding] with its [documentId] and [chunkText].
  Future<void> insert({
    required String documentId,
    required String chunkText,
    required List<double> embedding,
  });

  /// Finds the top [k] nearest neighbors to the [queryEmbedding].
  /// Returns a list of maps containing 'documentId', 'chunkText', and 'score'.
  Future<List<Map<String, dynamic>>> query(
    List<double> queryEmbedding, {
    int k = 5,
  });

  /// Removes all vectors associated with [documentId].
  Future<void> deleteByDocumentId(String documentId);
}
