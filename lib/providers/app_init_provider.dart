import 'package:flutter/foundation.dart';

/// Stages of the application initialisation sequence.
/// Used by [SplashScreen] to show meaningful progress to the user.
enum InitStage {
  starting,
  initializingEngine,
  checkingModels,
  openingDatabase,
  loadingModel,
  ready,
  error,
}

/// [ChangeNotifier] that exposes app startup progress so the [SplashScreen]
/// can display the current stage, a progress bar, and any error.
///
/// Call [advance] from [main.dart] as each initialisation step begins, and
/// [complete] once the full app widget tree is ready to take over.
class AppInitProvider extends ChangeNotifier {
  InitStage _stage = InitStage.starting;
  String _message = 'Starting Smriti…';
  double _progress = 0.0;
  String? _errorMessage;

  InitStage get stage => _stage;
  String get message => _message;
  double get progress => _progress;
  String? get errorMessage => _errorMessage;
  bool get isReady => _stage == InitStage.ready;
  bool get hasError => _stage == InitStage.error;

  /// Moves to the next [stage] with a human-readable [message] and [progress]
  /// value in the range [0.0, 1.0].
  void advance(InitStage stage, String message, double progress) {
    _stage = stage;
    _message = message;
    _progress = progress.clamp(0.0, 1.0);
    _errorMessage = null;
    notifyListeners();
  }

  /// Transitions to [InitStage.error] and stores the [error] message.
  void fail(String error) {
    _stage = InitStage.error;
    _errorMessage = error;
    notifyListeners();
  }

  /// Marks initialisation as complete, triggering navigation in [main.dart].
  void complete() {
    _stage = InitStage.ready;
    _message = 'Ready!';
    _progress = 1.0;
    _errorMessage = null;
    notifyListeners();
  }
}
