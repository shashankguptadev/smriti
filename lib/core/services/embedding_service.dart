/// Converts text chunks into vector embeddings.
abstract class EmbeddingService {
  /// Generates a vector embedding for the given [text].
  /// Returns a list of doubles representing the embedding vector.
  Future<List<double>> embed(String text);

  /// Generates embeddings for multiple [texts] in a batch.
  Future<List<List<double>>> embedBatch(List<String> texts);

  /// The dimensionality of vectors produced by this service.
  int get dimensions;
}
