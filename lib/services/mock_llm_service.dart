import 'dart:async';
import '../core/services/llm_service.dart';

/// Mock implementation of [LlmService] that yields tokens via a stream
/// to simulate on-device LLM streaming responses during development and testing.
class MockLlmService implements LlmService {
  final Duration tokenDelay;
  final String? fixedResponse;
  bool _isReady = false;

  MockLlmService({
    this.tokenDelay = const Duration(milliseconds: 15),
    this.fixedResponse,
  });

  @override
  bool get isReady => _isReady;

  @override
  Future<void> initialize() async {
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

    final responseText = fixedResponse ?? _buildResponse(prompt, contextChunks);
    final words = responseText.split(' ');

    for (int i = 0; i < words.length; i++) {
      if (tokenDelay > Duration.zero) {
        await Future.delayed(tokenDelay);
      }
      final token = i == words.length - 1 ? words[i] : '${words[i]} ';
      yield token;
    }
  }

  String _buildResponse(String prompt, List<String> contextChunks) {
    if (contextChunks.isEmpty) {
      return 'I could not find relevant information in your documents to answer "$prompt".';
    }
    // Extract a brief snippet rather than dumping the entire chunk
    final snippet = contextChunks.first.length > 200
        ? '${contextChunks.first.substring(0, 200)}...'
        : contextChunks.first;
    return 'Based on your documents, here is the answer regarding "$prompt": $snippet';
  }
}
