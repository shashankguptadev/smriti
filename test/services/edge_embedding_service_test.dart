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

    test('is always ready after initialize (projection-based, no model file needed)',
        () async {
      // EdgeEmbeddingService uses local feature hashing — it does not require
      // a model file on disk. isReady is always true after initialize().
      final service = EdgeEmbeddingService(
        modelPath: '/non/existent/path.bin',
        dimensions: 384,
      );
      await service.initialize();
      expect(service.isReady, isTrue);

      // Should generate normalized embeddings without throwing
      final emb = await service.embed('Fallback text');
      expect(emb.length, equals(384));
      double sumSq = 0.0;
      for (final v in emb) {
        sumSq += v * v;
      }
      expect(math.sqrt(sumSq), closeTo(1.0, 0.001));
    });

    test('semantically similar texts produce more similar embeddings than unrelated texts',
        () async {
      final service = EdgeEmbeddingService(dimensions: 384);
      await service.initialize();

      final examEmb = await service.embed('exam schedule timetable assessment');
      final scheduleEmb = await service.embed('exam schedule semester dates');
      final foodEmb = await service.embed('recipe cooking ingredients pasta');

      // Cosine similarity between similar texts should exceed dissimilar ones
      double dotSimilar = 0.0, dotDissimilar = 0.0;
      for (int i = 0; i < examEmb.length; i++) {
        dotSimilar += examEmb[i] * scheduleEmb[i];
        dotDissimilar += examEmb[i] * foodEmb[i];
      }
      expect(dotSimilar, greaterThan(dotDissimilar));
    });

    test('TF weighting: repeated key term increases embedding component', () async {
      final service = EdgeEmbeddingService(dimensions: 384);
      await service.initialize();

      // The text with the keyword repeated should differ from text with one mention
      final e1 = await service.embed('budget');
      final e2 = await service.embed('budget budget budget allocation cost');

      // They should not be identical (TF weighting changes the vector)
      bool identical = true;
      for (int i = 0; i < e1.length; i++) {
        if ((e1[i] - e2[i]).abs() > 1e-6) {
          identical = false;
          break;
        }
      }
      expect(identical, isFalse);
    });

    test('empty string returns zero vector without throwing', () async {
      final service = EdgeEmbeddingService(dimensions: 384);
      await service.initialize();

      final emb = await service.embed('');
      expect(emb.length, equals(384));
      expect(emb.every((v) => v == 0.0), isTrue);
    });

    test('dispose sets isReady to false', () async {
      final service = EdgeEmbeddingService(dimensions: 384);
      await service.initialize();
      expect(service.isReady, isTrue);

      await service.dispose();
      expect(service.isReady, isFalse);
    });
  });
}
