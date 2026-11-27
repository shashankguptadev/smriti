import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../services/edge_llm_service.dart';

/// Status of the local LLM model weights.
enum ModelStatus {
  checking,
  missing,
  importing,
  ready,
  mockBypass,
  error,
}

/// [ChangeNotifier] managing on-device `.litertlm` model weight discovery,
/// storage space checks, and file import.
class ModelManagerProvider extends ChangeNotifier {
  final Future<Directory> Function() _documentsDirResolver;

  ModelStatus _status = ModelStatus.checking;
  String? _activeModelPath;
  double _progress = 0.0;
  String? _errorMessage;
  int _modelSizeBytes = 0;
  int _maxContextChars = EdgeLlmService.defaultMaxContextChars;
  bool _isModelLoadingInBackground = false;
  Future<void> _persistChain = Future<void>.value();

  ModelManagerProvider({
    Future<Directory> Function()? documentsDirectoryResolver,
  }) : _documentsDirResolver =
            documentsDirectoryResolver ?? getApplicationDocumentsDirectory;

  ModelStatus get status => _status;
  String? get activeModelPath => _activeModelPath;
  double get progress => _progress;
  String? get errorMessage => _errorMessage;
  int get modelSizeBytes => _modelSizeBytes;
  int get maxContextChars => _maxContextChars;
  bool get isModelLoadingInBackground => _isModelLoadingInBackground;
  bool get hasRealModel => _status == ModelStatus.ready && _activeModelPath != null;
  bool get isModelReady => _status == ModelStatus.ready || _status == ModelStatus.mockBypass;

  /// Marks whether the native LiteRT model is currently loading in the background.
  void setModelLoadingInBackground(bool value) {
    if (_isModelLoadingInBackground == value) return;
    _isModelLoadingInBackground = value;
    notifyListeners();
  }

  /// Updates the runtime context character budget used by [EdgeLlmService]
  /// and persists it sequentially (best-effort) to app documents storage.
  Future<void> setMaxContextChars(int value) {
    final clamped = value.clamp(
      EdgeLlmService.minContextChars,
      EdgeLlmService.maxContextCharsLimit,
    );
    if (_maxContextChars == clamped) return _persistChain;
    _maxContextChars = clamped;
    notifyListeners();
    _persistChain = _persistChain.then((_) => _persistMaxContextChars());
    return _persistChain;
  }

  Future<void> _persistMaxContextChars() async {
    try {
      final docDir = await _documentsDirResolver();
      final configFile = File(p.join(docDir.path, 'context_chars.txt'));
      await configFile.writeAsString(_maxContextChars.toString());
    } catch (_) {
      // Best-effort persistence; ignore in tests without platform channels.
    }
  }

  Future<void> _loadMaxContextChars(Directory docDir) async {
    try {
      final configFile = File(p.join(docDir.path, 'context_chars.txt'));
      if (configFile.existsSync()) {
        final raw = (await configFile.readAsString()).trim();
        final parsed = int.tryParse(raw);
        if (parsed != null) {
          _maxContextChars = parsed.clamp(
            EdgeLlmService.minContextChars,
            EdgeLlmService.maxContextCharsLimit,
          );
        }
      }
    } catch (_) {}
  }

  /// Checks the application documents directory for an existing `.litertlm` model.
  Future<void> checkModelAvailability() async {
    _status = ModelStatus.checking;
    _errorMessage = null;
    notifyListeners();

    try {
      final docDir = await _documentsDirResolver();
      await _loadMaxContextChars(docDir);
      final modelsDir = Directory(p.join(docDir.path, 'models'));

      if (!modelsDir.existsSync()) {
        await modelsDir.create(recursive: true);
      }

      final files = modelsDir.listSync().whereType<File>();
      final litertFile = files.where((f) => f.path.endsWith('.litertlm')).firstOrNull;

      if (litertFile != null && litertFile.existsSync()) {
        _activeModelPath = litertFile.path;
        _modelSizeBytes = await litertFile.length();
        _status = ModelStatus.ready;
      } else {
        _activeModelPath = null;
        _modelSizeBytes = 0;
        _status = ModelStatus.missing;
      }
      notifyListeners();
    } catch (e) {
      _status = ModelStatus.error;
      _errorMessage = 'Failed to inspect model storage: $e';
      notifyListeners();
    }
  }

  /// Imports a user-selected `.litertlm` file into application storage.
  Future<bool> importLocalModel(File sourceFile) async {
    if (!sourceFile.existsSync()) {
      _status = ModelStatus.error;
      _errorMessage = 'Selected model file does not exist.';
      notifyListeners();
      return false;
    }

    _status = ModelStatus.importing;
    _progress = 0.1;
    _errorMessage = null;
    notifyListeners();

    try {
      final docDir = await _documentsDirResolver();
      final modelsDir = Directory(p.join(docDir.path, 'models'));
      if (!modelsDir.existsSync()) {
        await modelsDir.create(recursive: true);
      }

      final fileName = p.basename(sourceFile.path);
      final targetPath = p.join(modelsDir.path, fileName);

      _progress = 0.5;
      notifyListeners();

      final sourcePath = sourceFile.path;
      await Isolate.run(() async {
        final src = File(sourcePath);
        await src.copy(targetPath);
      });
      final targetFile = File(targetPath);

      // Clean up temporary cache files created during file picking
      try {
        await FilePicker.platform.clearTemporaryFiles();
      } catch (_) {}

      _activeModelPath = targetPath;
      _modelSizeBytes = await targetFile.length();
      _progress = 1.0;
      _status = ModelStatus.ready;
      notifyListeners();
      return true;
    } catch (e) {
      _status = ModelStatus.error;
      _errorMessage = 'Failed to import model: $e';
      notifyListeners();
      return false;
    }
  }

  /// Activates an already-on-device `.litertlm` model at [modelPath] **without
  /// copying** it into app storage. Use this when the user has already downloaded
  /// the model to their device (e.g. Downloads folder) and just wants Smriti to
  /// use it in-place via the LiteRT engine.
  Future<bool> activateExistingModel(String modelPath) async {
    final file = File(modelPath);
    if (!file.existsSync()) {
      _status = ModelStatus.error;
      _errorMessage = 'Model file not found at: $modelPath';
      notifyListeners();
      return false;
    }
    if (!modelPath.toLowerCase().endsWith('.litertlm')) {
      _status = ModelStatus.error;
      _errorMessage = 'Selected file is not a .litertlm model.';
      notifyListeners();
      return false;
    }
    _errorMessage = null;
    try {
      _activeModelPath = modelPath;
      _modelSizeBytes = await file.length();
      _status = ModelStatus.ready;
      notifyListeners();
      return true;
    } catch (e) {
      _status = ModelStatus.error;
      _errorMessage = 'Failed to activate model: $e';
      notifyListeners();
      return false;
    }
  }

  /// Called by [main.dart] when the LiteRT engine fails to initialize after a
  /// successful file import. Reverts the status to [ModelStatus.error] so the
  /// UI can show the failure and let the user retry or switch to mock mode.
  void setEngineError(String message) {
    _status = ModelStatus.error;
    _errorMessage = message;
    _activeModelPath = null;
    _modelSizeBytes = 0;
    _isModelLoadingInBackground = false;
    notifyListeners();
  }

  /// Sets the provider to ready state via mock bypass mode.
  void useMockOrBypass() {
    _status = ModelStatus.mockBypass;
    _isModelLoadingInBackground = false;
    notifyListeners();
  }

  /// Deletes the imported on-device model and reverts to missing state.
  Future<void> deleteActiveModel() async {
    try {
      if (_activeModelPath != null) {
        final file = File(_activeModelPath!);
        if (file.existsSync()) {
          await file.delete();
        }
      }
    } catch (_) {}
    _activeModelPath = null;
    _modelSizeBytes = 0;
    _isModelLoadingInBackground = false;
    _status = ModelStatus.missing;
    notifyListeners();
  }
}
