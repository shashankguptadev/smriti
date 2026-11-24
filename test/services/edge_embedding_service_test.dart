import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/services/edge_embedding_service.dart';

void main() {
  group('EdgeEmbeddingService', () {
    test('produces 384-dimensional unit-normalized embeddings', () async {
      final service = EdgeEmbeddingService(dimensions: 384);
      await service.initialize();

      final emb = await service.embed('Test sentence');
      expect(emb.length, equals(384));

      double sumSq = 0.0;
      for (final v in emb) {
        sumSq += v * v;
      }
      expect(math.sqrt(sumSq), closeTo(1.0, 0.001));
    });

    test('embedBatch returns all vectors matching input count', () async {
      final service = EdgeEmbeddingService(dimensions: 384);
      final list = await service.embedBatch(['one', 'two', 'three']);
      expect(list.length, equals(3));
      for (final item in list) {
        expect(item.length, equals(384));
      }
    });

    test('handles non-existent model path gracefully', () async {
      final service = EdgeEmbeddingService(
        modelPath: '/non/existent/path.bin',
        dimensions: 384,
      );
      await service.initialize();
      expect(service.isReady, isFalse);

      // Should still generate fallback normalized embeddings without throwing
      final emb = await service.embed('Fallback text');
      expect(emb.length, equals(384));
    });
  });
}
