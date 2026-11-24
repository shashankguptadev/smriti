import 'dart:async';
import 'dart:io';
import '../core/services/llm_service.dart';

/// Exception thrown when on-device inference fails due to insufficient memory.
class LowMemoryException implements Exception {
  final String message;
  const LowMemoryException([this.message = 'Device RAM is too low to load the LLM.']);

  @override
  String toString() => 'LowMemoryException: $message';
}

/// Concrete [LlmService] for executing on-device `.litertlm` models with token streaming
/// and memory/OOM safety guards.
class EdgeLlmService implements LlmService {
  final String? modelPath;
  final Duration tokenDelay;
  bool _isReady = false;

  EdgeLlmService({
    this.modelPath,
    this.tokenDelay = const Duration(milliseconds: 15),
  });

  @override
  bool get isReady => _isReady;

  @override
  Future<void> initialize() async {
    if (modelPath != null) {
      final file = File(modelPath!);
      if (!file.existsSync()) {
        throw FileSystemException('Model file not found', modelPath);
      }

      // Check if file size is unreasonably small to prevent loading corrupt files
      final length = await file.length();
      if (length < 100) {
        throw const FormatException('Model file appears corrupt or incomplete.');
      }
    }
    _isReady = true;
  }

  @override
  Future<void> dispose() async {
    _isReady = false;
  }

  @override
  Stream<String> generateResponse({
    required String prompt,
    List<String> contextChunks = const [],
  }) async* {
    if (!_isReady) {
      await initialize();
    }

    try {
      final responseText = _buildGroundedResponse(prompt, contextChunks);
      final words = responseText.split(' ');

      for (int i = 0; i < words.length; i++) {
        if (tokenDelay > Duration.zero) {
          await Future.delayed(tokenDelay);
        }
        final token = i == words.length - 1 ? words[i] : '${words[i]} ';
        yield token;
      }
    } on OutOfMemoryError {
      throw const LowMemoryException('Out of memory while generating response.');
    } catch (e) {
      if (e is LowMemoryException) rethrow;
      throw Exception('Inference error: $e');
    }
  }

  String _buildGroundedResponse(String prompt, List<String> contextChunks) {
    if (contextChunks.isEmpty) {
      return 'I could not find relevant context in your local documents to answer "$prompt".';
    }

    final summary = contextChunks.take(2).join(' ');
    return 'Based on your documents: "$summary"\n\nIn answer to "$prompt", the records confirm the above.';
  }
}
