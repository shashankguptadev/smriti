import 'dart:io';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/services/edge_llm_service.dart';

void main() {
  group('EdgeLlmService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('edge_llm_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    // ── Model detection ──────────────────────────────────────────────────
    test('detectModelType correctly identifies model families', () {
      expect(
        EdgeLlmService.detectModelType('models/gemma-4-E2B-it.litertlm'),
        equals(ModelType.gemma4),
      );
      expect(
        EdgeLlmService.detectModelType('gemma4-instruct.bin'),
        equals(ModelType.gemma4),
      );
      expect(
        EdgeLlmService.detectModelType('gemma-2b-it.litertlm'),
        equals(ModelType.gemmaIt),
      );
      expect(
        EdgeLlmService.detectModelType('qwen3.5-coder.litertlm'),
        equals(ModelType.qwen35),
      );
      expect(
        EdgeLlmService.detectModelType('qwen-2.5-7b.litertlm'),
        equals(ModelType.qwen),
      );
      expect(
        EdgeLlmService.detectModelType('deepseek-r1-distill.litertlm'),
        equals(ModelType.deepSeek),
      );
      expect(
        EdgeLlmService.detectModelType('llama-3.2-1b.litertlm'),
        equals(ModelType.llama),
      );
      expect(
        EdgeLlmService.detectModelType('custom_weights.litertlm'),
        equals(ModelType.general),
      );
    });

    test('isGemma4File correctly identifies Gemma 4 paths', () {
      expect(
        EdgeLlmService.isGemma4File('models/gemma-4-E2B-it.litertlm'),
        isTrue,
      );
      expect(
        EdgeLlmService.isGemma4File('gemma4-instruct.bin'),
        isTrue,
      );
      expect(
        EdgeLlmService.isGemma4File('deepseek-r1.litertlm'),
        isFalse,
      );
    });

    // ── Lifecycle ────────────────────────────────────────────────────────
    test('initializes Gemma 4 file without throwing UnsupportedError', () async {
      final modelFile = File('${tempDir.path}/gemma-4-E2B-it.litertlm');
      await modelFile.writeAsBytes(List.filled(10 * 1024 * 1024 + 1, 42));

      final service = EdgeLlmService(
        modelPath: modelFile.path,
        tokenDelay: Duration.zero,
      );
      await service.initialize();
      expect(service.isReady, isTrue);
    });

    test('initializes and streams tokens with valid model file', () async {
      final modelFile = File('${tempDir.path}/model.litertlm');
      await modelFile.writeAsBytes(List.filled(10 * 1024 * 1024 + 1, 42));

      final service = EdgeLlmService(
        modelPath: modelFile.path,
        tokenDelay: Duration.zero,
      );

      await service.initialize();
      expect(service.isReady, isTrue);

      final tokens = <String>[];
      await for (final token in service.generateResponse(
        prompt: 'Query',
        contextChunks: ['Smriti architecture context.'],
      )) {
        tokens.add(token);
      }

      final full = tokens.join();
      expect(full, contains('Smriti architecture context.'));
    });

    test('throws FileSystemException when model file is missing', () async {
      final service = EdgeLlmService(
        modelPath: '${tempDir.path}/missing.litertlm',
      );

      expect(() => service.initialize(), throwsA(isA<FileSystemException>()));
    });

    test('throws FormatException if model file is corrupt or too small', () async {
      final modelFile = File('${tempDir.path}/small.litertlm');
      await modelFile.writeAsBytes([1, 2, 3]);

      final service = EdgeLlmService(modelPath: modelFile.path);

      expect(() => service.initialize(), throwsA(isA<FormatException>()));
    });

    test('falls back with no-context message when contextChunks is empty', () async {
      final service = EdgeLlmService(tokenDelay: Duration.zero);
      await service.initialize();

      final tokens = <String>[];
      await for (final token in service.generateResponse(prompt: 'Hello')) {
        tokens.add(token);
      }

      final answer = tokens.join();
      expect(answer, contains('could not find relevant information'));
    });

    // ── System prompt ────────────────────────────────────────────────────
    test('buildSystemPrompt includes no-evidence instruction when contextChunks is empty',
        () {
      final service = EdgeLlmService();

      final emptyCtxPrompt = service.buildSystemPrompt(const []);
      // Must tell model to admit it couldn't find info, not to guess
      expect(emptyCtxPrompt, contains('could not find this in the uploaded documents'));
    });

    test('buildSystemPrompt encourages cross-referencing when context is provided', () {
      final service = EdgeLlmService();

      final withCtxPrompt =
          service.buildSystemPrompt(['Exam starts at 9 AM.']);
      expect(withCtxPrompt, contains('Cross-reference'));
      expect(withCtxPrompt, contains('general knowledge'));
    });

    // ── User prompt ──────────────────────────────────────────────────────
    test('buildUserPrompt includes Question: label and instruction', () {
      final service = EdgeLlmService();
      final userPrompt = service.buildUserPrompt(
        'What is photosynthesis?',
        ['Exam starts at 9 AM.'],
      );

      expect(userPrompt, contains('Question: What is photosynthesis?'));
      expect(userPrompt, contains('Exam starts at 9 AM.'));
      expect(userPrompt, isNot(contains('using only the context provided')));
    });

    test('buildUserPrompt includes fileName and chunkIndex label when provided', () {
      final service = EdgeLlmService();
      final userPrompt = service.buildUserPrompt(
        'Tell me about OS.',
        ['Operating Systems are complex.'],
        fileNames: ['lecture_notes.pdf'],
        chunkIndexes: [3],
      );

      expect(userPrompt, contains('[Excerpt 1 — lecture_notes.pdf, chunk 3]'));
    });

    test('buildUserPrompt falls back to [Excerpt N] label when metadata absent', () {
      final service = EdgeLlmService();
      final userPrompt = service.buildUserPrompt(
        'Tell me about OS.',
        ['Operating Systems are complex.'],
      );

      expect(userPrompt, contains('[Excerpt 1]'));
      expect(userPrompt, isNot(contains('[Excerpt 1 —')));
    });

    test('buildUserPrompt respects 10 000 char context limit', () {
      final service = EdgeLlmService();
      // Create chunks whose combined length exceeds 10 000 chars
      final bigChunks = List.generate(20, (i) => 'chunk $i: ${'word ' * 120}');
      final prompt = service.buildUserPrompt('question?', bigChunks);

      // The final prompt must not contain all 20 excerpts
      expect(prompt, isNot(contains('[Excerpt 20]')));
      // But it must contain at least the first excerpt
      expect(prompt, contains('[Excerpt 1]'));
    });
  });
}
