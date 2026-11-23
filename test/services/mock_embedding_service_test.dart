import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/services/mock_embedding_service.dart';

void main() {
  group('MockEmbeddingService', () {
    const service = MockEmbeddingService(dimensions: 384);

    test('returns embedding of configured dimensionality', () async {
      final embedding = await service.embed('Hello world');
      expect(embedding.length, equals(384));
    });

    test('is deterministic for identical text', () async {
      final emb1 = await service.embed('Machine learning in Flutter');
      final emb2 = await service.embed('Machine learning in Flutter');
      expect(emb1, equals(emb2));
    });

    test('produces distinct vectors for different text', () async {
      final emb1 = await service.embed('First text');
      final emb2 = await service.embed('Second distinct text');
      expect(emb1, isNot(equals(emb2)));
    });

    test('produces L2 unit-normalized vectors', () async {
      final embedding = await service.embed('Normalization test');
      double sumSq = 0.0;
      for (final v in embedding) {
        sumSq += v * v;
      }
      final norm = math.sqrt(sumSq);
      expect(norm, closeTo(1.0, 0.0001));
    });

    test('embedBatch returns list of embeddings matching input length', () async {
      final texts = ['alpha', 'beta', 'gamma'];
      final batch = await service.embedBatch(texts);
      expect(batch.length, equals(3));
      for (int i = 0; i < texts.length; i++) {
        expect(batch[i].length, equals(384));
        final individual = await service.embed(texts[i]);
        expect(batch[i], equals(individual));
      }
    });
  });
}
