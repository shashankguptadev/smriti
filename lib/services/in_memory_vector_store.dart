import 'dart:math' as math;
import '../core/models/document_info.dart';
import '../core/services/vector_store_service.dart';

class _StoredChunk {
  final String documentId;
  final String fileName;
  final int chunkIndex;
  final String chunkText;
  final List<double> embedding;

  _StoredChunk({
    required this.documentId,
    required this.fileName,
    required this.chunkIndex,
    required this.chunkText,
    required this.embedding,
  });
}

/// In-memory implementation of [VectorStoreService] for host unit tests.
/// Uses brute-force cosine distance without native library dependencies.
class InMemoryVectorStore implements VectorStoreService {
  final List<_StoredChunk> _chunks = [];
  bool _isDisposed = false;

  void _checkState() {
    if (_isDisposed) {
      throw StateError('InMemoryVectorStore has already been disposed.');
    }
  }

  @override
  Future<void> initialize() async {
    _isDisposed = false;
  }

  @override
  Future<void> dispose() async {
    _chunks.clear();
    _isDisposed = true;
  }

  @override
  Future<void> insert({
    required String documentId,
    required String chunkText,
    required List<double> embedding,
    String fileName = '',
    int chunkIndex = 0,
  }) async {
    _checkState();
    _chunks.add(_StoredChunk(
      documentId: documentId,
      fileName: fileName,
      chunkIndex: chunkIndex,
      chunkText: chunkText,
      embedding: List<double>.unmodifiable(embedding),
    ));
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    List<double> queryEmbedding, {
    int k = 5,
  }) async {
    _checkState();
    if (_chunks.isEmpty) return [];

    final scored = _chunks.map((chunk) {
      final distance = _cosineDistance(queryEmbedding, chunk.embedding);
      return {
        'documentId': chunk.documentId,
        'fileName': chunk.fileName,
        'chunkIndex': chunk.chunkIndex,
        'chunkText': chunk.chunkText,
        'score': distance,
      };
    }).toList();

    scored.sort((a, b) => (a['score'] as double).compareTo(b['score'] as double));

    return scored.take(k).toList();
  }

  @override
  Future<void> deleteByDocumentId(String documentId) async {
    _checkState();
    _chunks.removeWhere((chunk) => chunk.documentId == documentId);
  }

  @override
  Future<List<String>> listDocumentIds() async {
    _checkState();
    return _chunks.map((chunk) => chunk.documentId).toSet().toList();
  }

  @override
  Future<List<DocumentInfo>> listDocumentSummaries() async {
    _checkState();
    final Map<String, List<_StoredChunk>> grouped = {};
    for (final chunk in _chunks) {
      grouped.putIfAbsent(chunk.documentId, () => []).add(chunk);
    }
    return grouped.entries.map((entry) {
      final docId = entry.key;
      final chunks = entry.value;
      final fileName = chunks.first.fileName.isNotEmpty
          ? chunks.first.fileName
          : (docId.contains('/') || docId.contains(r'\')
              ? docId.split(RegExp(r'[/\\]')).last
              : docId);
      return DocumentInfo(
        documentId: docId,
        fileName: fileName,
        chunkCount: chunks.length,
      );
    }).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getAllChunks() async {
    _checkState();
    return _chunks.map((chunk) => {
      'documentId': chunk.documentId,
      'fileName': chunk.fileName,
      'chunkIndex': chunk.chunkIndex,
      'chunkText': chunk.chunkText,
    }).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getChunksByDocumentId(
    String documentId,
  ) async {
    _checkState();
    final filtered = _chunks
        .where((c) => c.documentId == documentId)
        .toList()
      ..sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));
    return filtered
        .map((c) => {'chunkIndex': c.chunkIndex, 'chunkText': c.chunkText})
        .toList();
  }

  /// Calculates cosine distance (1.0 - cosine similarity). Range: [0.0, 2.0].
  double _cosineDistance(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 2.0;

    double dot = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    if (normA <= 0.0 || normB <= 0.0) return 1.0;
    final similarity = dot / (math.sqrt(normA) * math.sqrt(normB));
    return (1.0 - similarity).clamp(0.0, 2.0);
  }
}
