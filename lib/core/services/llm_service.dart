/// Generates natural-language answers using a local LLM.
abstract class LlmService {
  /// Sends a [prompt] (with optional [contextChunks]) to the model
  /// and yields response tokens as a stream for real-time UI updates.
  Stream<String> generateResponse({
    required String prompt,
    List<String> contextChunks = const [],
  });

  /// Whether the model is currently loaded and ready.
  bool get isReady;

  /// Loads / warms up the model. No-op if already ready.
  Future<void> initialize();

  /// Releases model resources.
  Future<void> dispose();
}
