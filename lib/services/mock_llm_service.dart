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
      return 'I could not find a matching passage for "$prompt". '
          'This is mock mode, so I cannot reason beyond the retrieved text. '
          'Go to AI Model Setup and tap "Activate Downloaded Model" to enable on-device inference.';
    }
    // Be explicit that this is a retrieval preview, not a generated answer.
    final snippet = contextChunks.first.length > 200
        ? '${contextChunks.first.substring(0, 200)}...'
        : contextChunks.first;
    return 'I found this passage that may help with "$prompt":\n\n'
        '“$snippet”\n\n'
        'This is a retrieval preview from mock mode, not an AI-generated answer. '
        'Go to AI Model Setup → "Activate Downloaded Model" to get real synthesized responses.';
  }
}
