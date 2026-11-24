import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

  ModelManagerProvider({
    Future<Directory> Function()? documentsDirectoryResolver,
  }) : _documentsDirResolver =
            documentsDirectoryResolver ?? getApplicationDocumentsDirectory;

  ModelStatus get status => _status;
  String? get activeModelPath => _activeModelPath;
  double get progress => _progress;
  String? get errorMessage => _errorMessage;
  int get modelSizeBytes => _modelSizeBytes;
  bool get hasRealModel => _status == ModelStatus.ready && _activeModelPath != null;
  bool get isModelReady => _status == ModelStatus.ready || _status == ModelStatus.mockBypass;

  /// Checks the application documents directory for an existing `.litertlm` model.
  Future<void> checkModelAvailability() async {
    _status = ModelStatus.checking;
    _errorMessage = null;
    notifyListeners();

    try {
      final docDir = await _documentsDirResolver();
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

      await sourceFile.copy(targetPath);
      final targetFile = File(targetPath);

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

  /// Sets the provider to ready state via mock bypass mode.
  void useMockOrBypass() {
    _status = ModelStatus.mockBypass;
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
    _status = ModelStatus.missing;
    notifyListeners();
  }
}
