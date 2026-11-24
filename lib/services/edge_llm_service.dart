import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import '../core/services/llm_service.dart';

/// Exception thrown when on-device inference fails due to insufficient memory.
class LowMemoryException implements Exception {
  final String message;
  const LowMemoryException([this.message = 'Device RAM is too low to load the LLM.']);

  @override
  String toString() => 'LowMemoryException: $message';
}

/// Concrete [LlmService] executing on-device `.litertlm` models via [FlutterEdgeAi]
/// with real token streaming, prompt grounding, and fallback guards for host environments.
class EdgeLlmService implements LlmService {
  final String? modelPath;
  final Duration tokenDelay;
  bool _isReady = false;
  InferenceModel? _model;
  bool _hasNativeModel = false;

  EdgeLlmService({
    this.modelPath,
    this.tokenDelay = const Duration(milliseconds: 15),
  });

  @override
  bool get isReady => _isReady;

  bool get hasNativeModel => _hasNativeModel;

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

      try {
        await FlutterEdgeAi.installModel(
          modelType: ModelType.gemmaIt,
          fileType: ModelFileType.litertlm,
        )
            .fromFile(modelPath!)
            .install();

        _model = await FlutterEdgeAi.getActiveModel(maxTokens: 4096);
        _hasNativeModel = true;
        debugPrint('EdgeLlmService: native model loaded successfully.');
      } catch (e) {
        debugPrint('EdgeLlmService: native install failed ($e), will use host fallback.');
        _hasNativeModel = false;
      }
    }
    _isReady = true;
  }

  @override
  Future<void> dispose() async {
    _model = null;
    _hasNativeModel = false;
    _isReady = false;
  }

  /// Builds a structured system instruction for the model session.
  String _buildSystemPrompt(List<String> contextChunks) {
    if (contextChunks.isEmpty) {
      return 'You are Smriti, a helpful offline assistant. '
          'Respond naturally and concisely in complete sentences.';
    }
    return 'You are Smriti, an offline personal knowledge assistant. '
        'The user has uploaded documents into their local knowledge base. '
        'You will be given relevant excerpts from those documents. '
        'Your task:\n'
        '1. Read the excerpts carefully.\n'
        '2. Answer the user\'s question using ONLY information from the excerpts.\n'
        '3. Write your answer in clear, natural English sentences. '
        'Do NOT copy-paste raw text from the excerpts.\n'
        '4. If the excerpts do not contain enough information, '
        'say "I could not find the answer in your documents."\n'
        '5. Keep your answer concise — a few sentences at most.';
  }

  /// Builds a structured user prompt with numbered document excerpts.
  String _buildUserPrompt(String prompt, List<String> contextChunks) {
    if (contextChunks.isEmpty) return prompt;

    final buffer = StringBuffer();
    buffer.writeln('Here are the relevant excerpts from your documents:');
    buffer.writeln();
    for (int i = 0; i < contextChunks.length; i++) {
      // Trim each chunk to avoid bloating the context window with whitespace
      final trimmed = contextChunks[i].trim();
      if (trimmed.isEmpty) continue;
      buffer.writeln('[Excerpt ${i + 1}]');
      buffer.writeln(trimmed);
      buffer.writeln();
    }
    buffer.writeln('Question: $prompt');
    buffer.writeln();
    buffer.writeln('Answer the question using only the information above. '
        'Write a clear, natural answer in complete sentences.');
    return buffer.toString();
  }

  @override
  Stream<String> generateResponse({
    required String prompt,
    List<String> contextChunks = const [],
  }) async* {
    if (!_isReady) {
      await initialize();
    }

    final systemPrompt = _buildSystemPrompt(contextChunks);
    final userPrompt = _buildUserPrompt(prompt, contextChunks);

    if (_hasNativeModel && _model != null) {
      InferenceModelSession? session;
      try {
        session = await _model!.openSession(
          systemInstruction: systemPrompt,
          temperature: 0.3,
          topP: 0.85,
        );
        await session.addQueryChunk(Message(text: userPrompt, isUser: true));
        yield* session.getResponseAsync();
      } on OutOfMemoryError {
        throw const LowMemoryException('Out of memory while generating response.');
      } catch (e) {
        if (e is LowMemoryException) rethrow;
        debugPrint('EdgeLlmService native inference error: $e');
        // Fall through to host fallback instead of crashing
        yield* _hostFallbackStream(prompt, contextChunks);
      } finally {
        await session?.close();
      }
    } else {
      // Hermetic host fallback for tests and environments without native support
      yield* _hostFallbackStream(prompt, contextChunks);
    }
  }

  Stream<String> _hostFallbackStream(
    String prompt,
    List<String> contextChunks,
  ) async* {
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

  /// Host-side fallback: extracts key information from context chunks and
  /// presents it as a structured readable answer instead of raw text dump.
  String _buildGroundedResponse(String prompt, List<String> contextChunks) {
    if (contextChunks.isEmpty) {
      return 'I could not find relevant information in your documents to answer "$prompt".';
    }

    // Extract meaningful lines from the chunks, deduplicating
    final seen = <String>{};
    final meaningfulLines = <String>[];
    for (final chunk in contextChunks) {
      final lines = chunk.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        // Skip empty or very short lines (single words, stray punctuation)
        if (trimmed.isEmpty || trimmed.length < 3) {
          continue;
        }
        final key = trimmed.toLowerCase();
        if (!seen.contains(key)) {
          seen.add(key);
          meaningfulLines.add(trimmed);
        }
      }
    }

    if (meaningfulLines.isEmpty) {
      return 'I found some documents related to "$prompt" but could not extract a clear answer. '
          'Try rephrasing your question with more specific details.';
    }

    // Build a readable summary
    final buffer = StringBuffer();
    buffer.writeln('Based on your documents, here is what I found about "$prompt":');
    buffer.writeln();
    // Take at most 15 meaningful lines to keep it readable
    final linesToShow = meaningfulLines.take(15);
    for (final line in linesToShow) {
      buffer.writeln('• $line');
    }
    if (meaningfulLines.length > 15) {
      buffer.writeln();
      buffer.writeln('(${meaningfulLines.length - 15} more lines available in the source documents.)');
    }
    return buffer.toString().trim();
  }
}
