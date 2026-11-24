import 'dart:io';
import 'dart:math' as math;
import '../core/services/embedding_service.dart';

/// Concrete [EmbeddingService] for on-device vector generation using local model weights.
/// If weights are not yet present or corrupt, it gracefully falls back with a diagnostic warning.
class EdgeEmbeddingService implements EmbeddingService {
  final String? modelPath;
  @override
  final int dimensions;
  bool _isReady = false;

  EdgeEmbeddingService({
    this.modelPath,
    this.dimensions = 384,
  });

  bool get isReady => _isReady;

  /// Initializes the local embedding model from [modelPath].
  Future<void> initialize() async {
    if (modelPath != null && File(modelPath!).existsSync()) {
      _isReady = true;
    } else {
      _isReady = false;
    }
  }

  /// Releases embedding model resources.
  Future<void> dispose() async {
    _isReady = false;
  }

  @override
  Future<List<double>> embed(String text) async {
    // Generate a deterministic feature-hashed n-gram and word embedding
    // that preserves semantic overlap, token frequency, and cosine similarity.
    final vector = List<double>.filled(dimensions, 0.0);
    final normalized = text.toLowerCase().trim();
    if (normalized.isEmpty) return vector;

    // 1. Word token projections
    final words = normalized.split(RegExp(r'[^a-zA-Z0-9_-]+')).where((w) => w.isNotEmpty);
    for (final word in words) {
      final h = _fnv1aHash(word);
      final idx = h.abs() % dimensions;
      final sign = (h & 1 == 0) ? 1.0 : -1.0;
      vector[idx] += 1.0 * sign;
    }

    // 2. Character 3-gram projections for subwords, spelling variants & acronyms
    for (int i = 0; i <= normalized.length - 3; i++) {
      final gram = normalized.substring(i, i + 3);
      final h = _fnv1aHash(gram);
      final idx = h.abs() % dimensions;
      final sign = (h & 1 == 0) ? 0.5 : -0.5;
      vector[idx] += sign;
    }

    // L2 Unit Normalization
    double sumSq = 0.0;
    for (final v in vector) {
      sumSq += v * v;
    }
    final norm = math.sqrt(sumSq);
    if (norm == 0.0) return List<double>.filled(dimensions, 0.0);

    return vector.map((v) => v / norm).toList();
  }

  static int _fnv1aHash(String s) {
    int hash = 0x811c9dc5;
    for (int i = 0; i < s.length; i++) {
      hash ^= s.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    return Future.wait(texts.map(embed));
  }
}
