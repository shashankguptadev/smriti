import 'dart:math' as math;
import '../core/services/embedding_service.dart';

/// Deterministic mock implementation of [EmbeddingService] producing
/// 384-dimensional unit-normalized vectors based on the input text's hash code.
class MockEmbeddingService implements EmbeddingService {
  @override
  final int dimensions;

  const MockEmbeddingService({this.dimensions = 384});

  @override
  Future<List<double>> embed(String text) async {
    // Seed with text.hashCode for deterministic output per text input
    final random = math.Random(text.hashCode);
    final raw = List<double>.generate(
      dimensions,
      (_) => random.nextDouble() * 2.0 - 1.0,
    );

    // Calculate L2 norm to produce unit-length vectors
    double sumSq = 0.0;
    for (final v in raw) {
      sumSq += v * v;
    }
    final norm = math.sqrt(sumSq);
    if (norm == 0.0) return List<double>.filled(dimensions, 0.0);

    return raw.map((v) => v / norm).toList();
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    return Future.wait(texts.map(embed));
  }
}
