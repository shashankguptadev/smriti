import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/services/mock_llm_service.dart';
import 'package:smriti/services/switchable_llm_service.dart';

void main() {
  group('SwitchableLlmService Hot-Swapping', () {
    test('delegates to initial service and hot-swaps to new service seamlessly', () async {
      final mockA = MockLlmService(tokenDelay: Duration.zero);
      await mockA.initialize();

      final switchable = SwitchableLlmService(mockA);
      expect(switchable.isReady, isTrue);

      // 1. Initial generation with mockA
      final tokensA = <String>[];
      await for (final token in switchable.generateResponse(
        prompt: 'First prompt',
        contextChunks: ['Context A'],
      )) {
        tokensA.add(token);
      }
      expect(tokensA.join(), contains('Context A'));

      // 2. Hot-swap to mockB with distinct behavior
      final mockB = MockLlmService(tokenDelay: Duration.zero);
      await mockB.initialize();

      switchable.switchTo(mockB);
      expect(switchable.activeService, equals(mockB));

      final tokensB = <String>[];
      await for (final token in switchable.generateResponse(
        prompt: 'Second prompt',
        contextChunks: ['Context B'],
      )) {
        tokensB.add(token);
      }
      expect(tokensB.join(), contains('Context B'));
    });
  });
}

