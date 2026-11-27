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
      // Write > 10 MB so it passes the minimum-size guard (real models are
      // hundreds of MB; we simulate a valid file just large enough to pass).
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
      await modelFile.writeAsBytes([1, 2, 3]); // corrupt / < 100 bytes

      final service = EdgeLlmService(
        modelPath: modelFile.path,
      );

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

    test('buildSystemPrompt allows general knowledge alongside document context', () {
      final service = EdgeLlmService();

      final emptyCtxPrompt = service.buildSystemPrompt(const []);
      expect(emptyCtxPrompt, contains('own knowledge'));

      final withCtxPrompt = service.buildSystemPrompt(['Exam starts at 9 AM.']);
      expect(withCtxPrompt, contains('general knowledge'));
      expect(withCtxPrompt, isNot(contains('I could not find this information in your uploaded documents.')));
    });

    test('buildUserPrompt does not restrict model to only provided context', () {
      final service = EdgeLlmService();
      final userPrompt = service.buildUserPrompt(
        'What is photosynthesis?',
        ['Exam starts at 9 AM.'],
      );

      expect(userPrompt, contains('Question: What is photosynthesis?'));
      expect(userPrompt, contains('Exam starts at 9 AM.'));
      expect(userPrompt, isNot(contains('using only the context provided')));
      expect(userPrompt, contains('own general knowledge'));
    });
  });
}
