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

    test('setMaxContextChars clamps, notifies, and persists across checks', () async {
      expect(provider.maxContextChars, equals(5000));

      await provider.setMaxContextChars(500);
      expect(provider.maxContextChars, equals(1000));

      await provider.setMaxContextChars(99999);
      expect(provider.maxContextChars, equals(12000));

      await provider.setMaxContextChars(6500);
      expect(provider.maxContextChars, equals(6500));

      final freshProvider = ModelManagerProvider(
        documentsDirectoryResolver: () async => tempDir,
      );
      await freshProvider.checkModelAvailability();
      expect(freshProvider.maxContextChars, equals(6500));
    });

    test('tracks background loading flag and resets it on error or mock bypass',
        () {
      expect(provider.isModelLoadingInBackground, isFalse);

      provider.setModelLoadingInBackground(true);
      expect(provider.isModelLoadingInBackground, isTrue);

      provider.setEngineError('Load failed');
      expect(provider.isModelLoadingInBackground, isFalse);

      provider.setModelLoadingInBackground(true);
      provider.useMockOrBypass();
      expect(provider.isModelLoadingInBackground, isFalse);
    });
  });
}
