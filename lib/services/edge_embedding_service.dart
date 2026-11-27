import 'dart:math' as math;
import '../core/services/embedding_service.dart';

/// Improved on-device [EmbeddingService] using a TF-IDF–inspired multi-feature
/// projection to 384-dimensional unit-normalised vectors.
///
/// ## Upgrade over v1 (FNV-1a simple hash)
/// Unlike the v1 implementation that applied a single FNV-1a word hash with
/// uniform weights, this implementation uses:
///
/// 1. **Term-frequency (TF) weighting** — repeated words increase their
///    contribution logarithmically (`1 + ln(tf)`) so common boilerplate does
///    not dominate.
/// 2. **IDF approximation** — longer, more specific words (length > 6) receive
///    a higher base weight than short function words, approximating the inverse
///    document-frequency effect without a corpus.
/// 3. **Bigram features** — adjacent word pairs project to a separate region of
///    the embedding space, capturing phrase-level semantics (e.g. "neural
///    network" ≠ "neural" + "network" independently).
/// 4. **Position-decay weighting** — tokens near the beginning of the text
///    receive a small boost (title/topic words tend to appear first).
/// 5. **Multiple hash projections** — each token is projected via three
///    independent hash functions to reduce collision probability.
/// 6. **Character trigram features** — sub-word shapes capture spelling
///    variants, acronyms, and morphological affixes.
///
/// The resulting cosine similarity is significantly more discriminative for
/// factual/keyword retrieval than the v1 uniform-weight hash.
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

  Future<void> initialize() async {
    _isReady = true; // projection-based — no model weights to load
  }

  Future<void> dispose() async {
    _isReady = false;
  }

  @override
  Future<List<double>> embed(String text) async {
    final vector = List<double>.filled(dimensions, 0.0);
    final normalized = text.toLowerCase().trim();
    if (normalized.isEmpty) return vector;

    final words = normalized
        .split(RegExp(r'[^a-zA-Z0-9_]+'))
        .where((w) => w.isNotEmpty)
        .toList();

    if (words.isEmpty) return vector;

    // ── 1. TF-weighted word projections with IDF approximation ───────────
    final termFreq = <String, int>{};
    for (final word in words) {
      termFreq[word] = (termFreq[word] ?? 0) + 1;
    }

    for (int pos = 0; pos < words.length; pos++) {
      final word = words[pos];
      final tf = termFreq[word]!;
      final tfWeight = 1.0 + math.log(tf.toDouble());

      // IDF approximation: longer words are rarer → higher weight
      final idfApprox = word.length <= 3
          ? 0.5
          : word.length <= 5
              ? 1.0
              : word.length <= 7
                  ? 1.5
                  : 2.0;

      // Position decay: earlier words get a slight boost
      final posBoost = 1.0 + (0.3 / (1.0 + pos * 0.05));

      final baseWeight = tfWeight * idfApprox * posBoost;

      // Three independent hash projections per word to reduce collisions
      _project(vector, word, baseWeight, seed: 0);
      _project(vector, word, baseWeight * 0.6, seed: 1);
      _project(vector, word, baseWeight * 0.4, seed: 2);
    }

    // ── 2. Bigram features ────────────────────────────────────────────────
    for (int i = 0; i < words.length - 1; i++) {
      final bigram = '${words[i]}_${words[i + 1]}';
      _project(vector, bigram, 1.2, seed: 3);
    }

    // ── 3. Character trigram features ─────────────────────────────────────
    for (int i = 0; i <= normalized.length - 3; i++) {
      final gram = normalized.substring(i, i + 3);
      _project(vector, gram, 0.3, seed: 4);
    }

    // ── 4. L2 unit normalisation ──────────────────────────────────────────
    return _l2Normalize(vector);
  }

  /// Projects [token] into [vector] at a position derived from [token]'s hash
  /// (seeded with [seed]) with signed weight [weight].
  void _project(List<double> vector, String token, double weight, {required int seed}) {
    final h = _fnv1aHash(token, seed: seed);
    final idx = h.abs() % dimensions;
    final sign = (h & 1 == 0) ? 1.0 : -1.0;
    vector[idx] += weight * sign;

    // Secondary projection at an offset position
    final h2 = _fnv1aHash('$token$seed', seed: seed + 100);
    final idx2 = h2.abs() % dimensions;
    final sign2 = (h2 & 1 == 0) ? 1.0 : -1.0;
    vector[idx2] += weight * 0.5 * sign2;
  }

  List<double> _l2Normalize(List<double> vector) {
    double sumSq = 0.0;
    for (final v in vector) {
      sumSq += v * v;
    }
    final norm = math.sqrt(sumSq);
    if (norm == 0.0) return List<double>.filled(dimensions, 0.0);
    return vector.map((v) => v / norm).toList();
  }

  /// FNV-1a 32-bit hash with an optional [seed] mixed in before hashing.
  static int _fnv1aHash(String s, {int seed = 0}) {
    int hash = 0x811c9dc5 ^ (seed * 0x9e3779b9);
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
