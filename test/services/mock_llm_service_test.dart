import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/services/mock_llm_service.dart';

void main() {
  group('MockLlmService', () {
    test('lifecycle transitions isReady properly', () async {
      final service = MockLlmService();
      expect(service.isReady, isFalse);

      await service.initialize();
      expect(service.isReady, isTrue);

      await service.dispose();
      expect(service.isReady, isFalse);
    });

    test('streams tokens for a prompt', () async {
      final service = MockLlmService(
        tokenDelay: Duration.zero,
        fixedResponse: 'Smriti is offline knowledge base',
      );

      final tokens = <String>[];
      await for (final token in service.generateResponse(prompt: 'What is Smriti?')) {
        tokens.add(token);
      }

      expect(tokens, isNotEmpty);
      final reconstructed = tokens.join();
      expect(reconstructed, equals('Smriti is offline knowledge base'));
    });

    test('incorporates context chunks in default response', () async {
      final service = MockLlmService(tokenDelay: Duration.zero);

      final tokens = <String>[];
      await for (final token in service.generateResponse(
        prompt: 'Who founded Smriti?',
        contextChunks: ['Created by team offline.'],
      )) {
        tokens.add(token);
      }

      final fullResponse = tokens.join();
      expect(fullResponse, contains('Created by team offline.'));
    });

    test('auto-initializes if generateResponse is called before initialize', () async {
      final service = MockLlmService(tokenDelay: Duration.zero);
      expect(service.isReady, isFalse);

      await service.generateResponse(prompt: 'Hello').drain();
      expect(service.isReady, isTrue);
    });
  });
}

