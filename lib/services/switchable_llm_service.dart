import '../core/services/llm_service.dart';

/// Dynamic [LlmService] wrapper that allows hot-swapping between
/// [MockLlmService] and [EdgeLlmService] at runtime without restarting the app.
class SwitchableLlmService implements LlmService {
  LlmService _activeService;

  SwitchableLlmService(this._activeService);

  LlmService get activeService => _activeService;

  /// Hot-swaps the underlying active inference service.
  void switchTo(LlmService newService) {
    _activeService = newService;
  }

  @override
  bool get isReady => _activeService.isReady;

  @override
  Future<void> initialize() => _activeService.initialize();

  @override
  Future<void> dispose() => _activeService.dispose();

  @override
  Stream<String> generateResponse({
    required String prompt,
    List<String> contextChunks = const [],
  }) {
    return _activeService.generateResponse(
      prompt: prompt,
      contextChunks: contextChunks,
    );
  }
}
