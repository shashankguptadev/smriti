import 'dart:io';
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

    test('initializes and streams tokens with valid model file', () async {
      final modelFile = File('${tempDir.path}/model.litertlm');
      await modelFile.writeAsBytes(List.filled(200, 42)); // valid size > 100

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
  });
}
