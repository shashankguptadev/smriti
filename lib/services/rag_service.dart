import 'dart:math' as math;
import '../core/services/embedding_service.dart';
import '../core/services/llm_service.dart';
import '../core/services/vector_store_service.dart';

/// Orchestrates Retrieval-Augmented Generation (RAG) by combining BM25 lexical
/// keyword search and vector similarity (Hybrid Retrieval) with Reciprocal Rank
/// Fusion (RRF), conversational routing, and streaming generation from [LlmService].
///
/// ## v2 Retrieval Improvements
/// - **Query expansion:** generates 2–3 lightweight variants of the user question
///   (stripped question words, keyword-only subset) to improve recall on queries
///   that use different vocabulary than the indexed text.
/// - **Multi-query retrieval:** BM25 and vector search are run for each expanded
///   query variant; results are unioned before RRF fusion.
/// - **topK raised 5 → 8:** captures more relevant sections for multi-part questions.
/// - **Score gating:** chunks whose aggregated RRF score falls below a minimum
///   threshold are dropped before building the LLM context, preventing
///   weakly-related content from confusing the model.
/// - **Deduplication:** overlapping window chunks whose first 80 characters match
///   are removed so the LLM never sees the same content twice.
class RagService {
  final EmbeddingService embeddingService;
  final VectorStoreService vectorStoreService;
  final LlmService llmService;
  final int topK;

  /// Minimum RRF score a chunk must reach to be included in the LLM context.
  /// Chunks below this threshold are almost certainly unrelated to the query.
  static const double _minRrfScore = 0.004;

  static final Set<String> _commonGreetings = {
    'hi',
    'hello',
    'hey',
    'hola',
    'greetings',
    'good morning',
    'good afternoon',
    'good evening',
    'howdy',
    'who are you',
    'what are you',
    'what is your name',
    'what can you do',
    'help',
    'thanks',
    'thank you',
    'bye',
    'goodbye',
  };

  /// Stopwords ignored during token matching to prevent noise.
  static final Set<String> _stopwords = {
    'the', 'a', 'an', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
    'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'shall',
    'should', 'may', 'might', 'must', 'can', 'could', 'of', 'in', 'to',
    'for', 'with', 'on', 'at', 'from', 'by', 'about', 'as', 'into',
    'through', 'during', 'before', 'after', 'above', 'below', 'between',
    'and', 'but', 'or', 'not', 'no', 'nor', 'so', 'yet', 'both', 'each',
    'all', 'any', 'few', 'more', 'most', 'other', 'some', 'such', 'than',
    'that', 'this', 'these', 'those', 'it', 'its', 'my', 'your', 'his',
    'her', 'our', 'their', 'what', 'which', 'who', 'whom', 'when', 'where',
    'why', 'how', 'me', 'him', 'them', 'we', 'you', 'i', 'he', 'she',
    'they', 'up', 'out', 'if', 'then', 'tell', 'give', 'show', 'list',
    'explain', 'describe', 'find', 'get',
  };

  RagService({
    required this.embeddingService,
    required this.vectorStoreService,
    required this.llmService,
    this.topK = 8,
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns [true] if [query] is conversational chitchat or a greeting.
  bool isConversationalQuery(String query) {
    final clean = query
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .trim();
    if (clean.isEmpty) return true;
    return _commonGreetings.contains(clean);
  }

  /// Retrieves the top [k] most relevant context chunks using Hybrid Retrieval
  /// (multi-query BM25 keyword matching + vector similarity with RRF).
  ///
  /// Returns an empty list when:
  /// - the query is a conversational greeting, or
  /// - no chunks satisfy the minimum [_minRrfScore] threshold.
  Future<List<Map<String, dynamic>>> getSourceChunks(
    String question, {
    int? k,
  }) async {
    final effectiveK = k ?? topK;
    if (isConversationalQuery(question)) {
      return [];
    }

    final allChunks = await vectorStoreService.getAllChunks();
    if (allChunks.isEmpty) {
      return [];
    }

    // ── Query expansion ───────────────────────────────────────────────────
    final queryVariants = _expandQuery(question);

    // ── Multi-query RRF accumulation ──────────────────────────────────────
    const kRrf = 60.0;
    final Map<String, double> rrfScores = {};
    final Map<String, Map<String, dynamic>> chunkMap = {};

    for (final variant in queryVariants) {
      // 1. Lexical BM25 scoring for this variant
      final lexicalRanked = _rankChunksLexically(variant, allChunks);
      for (int i = 0; i < lexicalRanked.length; i++) {
        final chunk = lexicalRanked[i];
        final key = _chunkKey(chunk);
        chunkMap[key] ??= chunk;
        // Lexical gets 2× weight — more reliable than hash-based embedding
        rrfScores[key] = (rrfScores[key] ?? 0.0) + 2.0 / (kRrf + (i + 1));
      }

      // 2. Vector similarity for this variant
      final queryEmbedding = await embeddingService.embed(variant);
      final vectorResults =
          await vectorStoreService.query(queryEmbedding, k: effectiveK * 3);
      for (int i = 0; i < vectorResults.length; i++) {
        final chunk = vectorResults[i];
        final key = _chunkKey(chunk);
        chunkMap[key] ??= chunk;
        rrfScores[key] = (rrfScores[key] ?? 0.0) + 1.0 / (kRrf + (i + 1));
      }
    }

    if (rrfScores.isEmpty) {
      return [];
    }

    // ── Sort by aggregated RRF score ──────────────────────────────────────
    final sortedKeys = rrfScores.keys.toList()
      ..sort((a, b) => rrfScores[b]!.compareTo(rrfScores[a]!));

    // ── Score gate + deduplication + topK cap ─────────────────────────────
    final results = <Map<String, dynamic>>[];
    final fingerprintsSeen = <String>{};

    for (final key in sortedKeys) {
      if (results.length >= effectiveK) break;

      // Drop below-threshold chunks
      if (rrfScores[key]! < _minRrfScore) break; // sorted, so rest are lower

      final chunk = chunkMap[key]!;
      final text = (chunk['chunkText'] as String? ?? '').trim();

      // Deduplication by leading 80-char fingerprint
      final fingerprint =
          text.substring(0, text.length < 80 ? text.length : 80);
      if (fingerprintsSeen.contains(fingerprint)) continue;
      fingerprintsSeen.add(fingerprint);

      results.add({
        'documentId': chunk['documentId'],
        'fileName': chunk['fileName'],
        'chunkIndex': chunk['chunkIndex'],
        'chunkText': text,
        'score': rrfScores[key],
      });
    }

    return results;
  }

  /// Queries relevant documents and streams the generated answer.
  /// If [contextChunks] is provided, uses those chunks directly.
  Stream<String> ask(
    String question, {
    List<Map<String, dynamic>>? contextChunks,
  }) async* {
    final sources = contextChunks ?? await getSourceChunks(question);
    final texts = sources
        .map((chunk) => chunk['chunkText'] as String? ?? '')
        .where((text) => text.isNotEmpty)
        .toList();

    yield* llmService.generateResponse(
      prompt: question,
      contextChunks: texts,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Query expansion
  // ─────────────────────────────────────────────────────────────────────────

  /// Generates up to 3 lightweight query variants to improve recall on queries
  /// that use different vocabulary than the indexed document text.
  ///
  /// Strategies applied:
  /// 1. Original query (always included).
  /// 2. Question-preamble stripping: "What is X?" → "X".
  /// 3. Key-noun subset: non-stopword tokens longer than 3 chars joined.
  List<String> _expandQuery(String query) {
    final variants = <String>[query];
    final lower = query.toLowerCase().trim();

    // 1. Strip common question preambles
    final stripped = lower
        .replaceAll(
          RegExp(
            r'^(what (is|are|was|were|does|do)|how (does|do|is|are|was|were)|'
            r'why (is|are|does|do|was|were)|when (is|are|was|were)|'
            r'where (is|are|was|were)|who (is|are|was|were)|'
            r'tell me about|explain|describe|summarize|summarise|'
            r'give me|show me|list|find)\s+',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'[?!]+$'), '')
        .trim();

    final cleanOriginal = lower.replaceAll(RegExp(r'[?!]+$'), '').trim();
    if (stripped.isNotEmpty && stripped != cleanOriginal) {
      variants.add(stripped);
    }

    // 2. Key-noun token subset (non-stopword, length > 3)
    final tokens = lower
        .split(RegExp(r'[^a-zA-Z0-9]+'))
        .where((t) => t.length > 3 && !_stopwords.contains(t))
        .toList();
    if (tokens.length >= 2) {
      final keywordQuery = tokens.join(' ');
      if (!variants.contains(keywordQuery)) {
        variants.add(keywordQuery);
      }
    }

    return variants.where((v) => v.isNotEmpty).toSet().toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BM25-inspired lexical scoring
  // ─────────────────────────────────────────────────────────────────────────

  /// BM25-inspired lexical scoring with multi-token proximity bonus,
  /// query-coverage requirements, and stopword filtering.
  List<Map<String, dynamic>> _rankChunksLexically(
    String query,
    List<Map<String, dynamic>> chunks,
  ) {
    final queryTokens = query
        .toLowerCase()
        .split(RegExp(r'[^a-zA-Z0-9]+'))
        .where((t) => t.isNotEmpty && !_stopwords.contains(t))
        .toList();

    if (queryTokens.isEmpty) return [];

    final scored = <Map<String, dynamic>>[];
    final lowerQuery = query.toLowerCase();
    final totalTokens = queryTokens.length;

    for (final chunk in chunks) {
      final text = (chunk['chunkText'] as String? ?? '').toLowerCase();
      if (text.isEmpty) continue;

      double score = 0.0;
      int matchedTokens = 0;

      // Exact full-query substring bonus (strongest signal)
      if (text.contains(lowerQuery)) {
        score += 15.0;
      }

      // Token match scores with type-aware weighting
      for (final token in queryTokens) {
        if (text.contains(token)) {
          matchedTokens++;
          if (RegExp(r'^[0-9]').hasMatch(token)) {
            score += 5.0; // Numbers / codes — high precision signal
          } else if (token.length <= 4) {
            score += 4.0; // Short acronyms like "cse", "ece"
          } else {
            score += 2.0; // General words like "semester", "exam"
          }
        }
      }

      // Require at least half the non-stopword query tokens to match
      if (totalTokens > 1 && matchedTokens < (totalTokens * 0.5).ceil()) {
        continue;
      }

      // Multi-token proximity bonus
      if (matchedTokens >= 2) {
        final positions = <int>[];
        for (final token in queryTokens) {
          final idx = text.indexOf(token);
          if (idx >= 0) positions.add(idx);
        }
        if (positions.length >= 2) {
          positions.sort();
          final span = positions.last - positions.first;
          if (span < 200) {
            score += math.max(0.0, 10.0 - (span / 20.0));
          }
        }
      }

      // Coverage bonus
      score += (matchedTokens / totalTokens) * 3.0;

      if (score > 0.0) {
        scored.add({...chunk, 'lexicalScore': score});
      }
    }

    scored.sort(
      (a, b) =>
          (b['lexicalScore'] as double).compareTo(a['lexicalScore'] as double),
    );
    return scored;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  static String _chunkKey(Map<String, dynamic> chunk) =>
      '${chunk['documentId']}_${chunk['chunkIndex']}';
}
