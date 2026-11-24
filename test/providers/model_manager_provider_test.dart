import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/providers/model_manager_provider.dart';

void main() {
  group('ModelManagerProvider', () {
    late Directory tempDir;
    late ModelManagerProvider provider;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mm_test_');
      provider = ModelManagerProvider(
        documentsDirectoryResolver: () async => tempDir,
      );
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('detects missing model when directory has no .litertlm file', () async {
      await provider.checkModelAvailability();
      expect(provider.status, equals(ModelStatus.missing));
      expect(provider.isModelReady, isFalse);
    });

    test('detects existing .litertlm file and sets status to ready', () async {
      final modelsDir = Directory('${tempDir.path}/models');
      await modelsDir.create(recursive: true);
      final modelFile = File('${modelsDir.path}/gemma.litertlm');
      await modelFile.writeAsString('mock model weights binary');

      await provider.checkModelAvailability();
      expect(provider.status, equals(ModelStatus.ready));
      expect(provider.isModelReady, isTrue);
      expect(provider.activeModelPath, equals(modelFile.path));
    });

    test('imports local model file into application storage', () async {
      final source = File('${tempDir.path}/source.litertlm');
      await source.writeAsString('sample weights');

      final success = await provider.importLocalModel(source);
      expect(success, isTrue);
      expect(provider.status, equals(ModelStatus.ready));
      expect(provider.activeModelPath, isNotNull);
      expect(File(provider.activeModelPath!).existsSync(), isTrue);
    });

    test('useMockOrBypass sets status to mockBypass and marks model ready', () {
      expect(provider.isModelReady, isFalse);
      provider.useMockOrBypass();
      expect(provider.status, equals(ModelStatus.mockBypass));
      expect(provider.isModelReady, isTrue);
      expect(provider.hasRealModel, isFalse);
    });
  });
}
