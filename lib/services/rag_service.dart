import 'dart:math' as math;
import '../core/services/embedding_service.dart';
import '../core/services/llm_service.dart';
import '../core/services/vector_store_service.dart';

/// Orchestrates Retrieval-Augmented Generation (RAG) by combining BM25 lexical
/// keyword search and vector similarity (Hybrid Retrieval) with Reciprocal Rank
/// Fusion (RRF), conversational routing, and streaming generation from [LlmService].
class RagService {
  final EmbeddingService embeddingService;
  final VectorStoreService vectorStoreService;
  final LlmService llmService;
  final int topK;

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
    'they', 'up', 'out', 'if', 'then',
  };

  RagService({
    required this.embeddingService,
    required this.vectorStoreService,
    required this.llmService,
    this.topK = 5,
  });

  /// Evaluates whether a question is conversational chitchat or greeting.
  bool isConversationalQuery(String query) {
    final clean = query
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .trim();
    if (clean.isEmpty) return true;
    return _commonGreetings.contains(clean);
  }

  /// Retrieves the top [k] most relevant context chunks using Hybrid Retrieval
  /// (BM25 keyword matching + vector similarity with Reciprocal Rank Fusion).
  ///
  /// Returns an empty list if the query is a conversational greeting, empty,
  /// or when no chunks satisfy minimum relevance thresholds.
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

    // 1. Lexical BM25 / Keyword Scoring
    final lexicalRanked = _rankChunksLexically(question, allChunks);

    // 2. Vector Similarity Search
    final queryEmbedding = await embeddingService.embed(question);
    final vectorResults = await vectorStoreService.query(queryEmbedding, k: effectiveK * 3);

    // 3. Reciprocal Rank Fusion (RRF)
    const kRrf = 60.0;
    final Map<String, double> rrfScores = {};
    final Map<String, Map<String, dynamic>> chunkMap = {};

    // Ingest lexical rankings — give lexical more weight (2x) since it's
    // more reliable than hash-based embedding for keyword/factual queries.
    for (int i = 0; i < lexicalRanked.length; i++) {
      final chunk = lexicalRanked[i];
      final key = '${chunk['documentId']}_${chunk['chunkIndex']}';
      chunkMap[key] = chunk;
      rrfScores[key] = (rrfScores[key] ?? 0.0) + 2.0 / (kRrf + (i + 1));
    }

    // Ingest vector rankings
    for (int i = 0; i < vectorResults.length; i++) {
      final chunk = vectorResults[i];
      final key = '${chunk['documentId']}_${chunk['chunkIndex']}';
      chunkMap[key] ??= chunk;
      rrfScores[key] = (rrfScores[key] ?? 0.0) + (1.0 / (kRrf + (i + 1)));
    }

    if (rrfScores.isEmpty) {
      return [];
    }

    // Sort by aggregated RRF score
    final sortedKeys = rrfScores.keys.toList()
      ..sort((a, b) => rrfScores[b]!.compareTo(rrfScores[a]!));

    final results = sortedKeys.take(effectiveK).map((key) {
      final chunk = chunkMap[key]!;
      return {
        'documentId': chunk['documentId'],
        'fileName': chunk['fileName'],
        'chunkIndex': chunk['chunkIndex'],
        'chunkText': chunk['chunkText'],
        'score': rrfScores[key],
      };
    }).toList();

    return results;
  }

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
            // Numbers like "5th" — high precision signal
            score += 5.0;
          } else if (token.length <= 4) {
            // Short codes/acronyms like "cse", "ece"
            score += 4.0;
          } else {
            // General words like "semester", "exam"
            score += 2.0;
          }
        }
      }

      // Require at least half the non-stopword query tokens to match
      if (totalTokens > 1 && matchedTokens < (totalTokens * 0.5).ceil()) {
        continue;
      }

      // Multi-token proximity bonus: reward chunks where query tokens
      // appear close together (e.g., "5th semester CSE" within 100 chars)
      if (matchedTokens >= 2) {
        final positions = <int>[];
        for (final token in queryTokens) {
          final idx = text.indexOf(token);
          if (idx >= 0) positions.add(idx);
        }
        if (positions.length >= 2) {
          positions.sort();
          final span = positions.last - positions.first;
          // Tighter spans get higher bonus (max 10 when within 50 chars)
          if (span < 200) {
            score += math.max(0.0, 10.0 - (span / 20.0));
          }
        }
      }

      // Coverage bonus: fraction of query tokens found
      score += (matchedTokens / totalTokens) * 3.0;

      if (score > 0.0) {
        scored.add({
          ...chunk,
          'lexicalScore': score,
        });
      }
    }

    scored.sort((a, b) => (b['lexicalScore'] as double).compareTo(a['lexicalScore'] as double));
    return scored;
  }

  /// Queries relevant documents and streams the generated answer.
  /// If [contextChunks] is provided, uses those chunks directly instead of querying.
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
}
