import '../core/models/document_chunk.dart';
import '../core/services/vector_store_service.dart';
import '../objectbox.g.dart';

/// Concrete [VectorStoreService] backed by an ObjectBox database with HNSW indexing.
class ObjectBoxVectorStore implements VectorStoreService {
  Store? _store;
  Box<DocumentChunk>? _box;
  final String? _directory;

  ObjectBoxVectorStore({Store? store, String? directory})
      : _store = store,
        _directory = directory {
    if (_store != null) {
      _box = _store!.box<DocumentChunk>();
    }
  }

  Box<DocumentChunk> get _checkedBox {
    final box = _box;
    if (box == null) {
      throw StateError(
        'ObjectBoxVectorStore is not initialized. Call initialize() first.',
      );
    }
    return box;
  }

  @override
  Future<void> initialize() async {
    if (_store == null) {
      if (_directory != null) {
        _store = await openStore(directory: _directory);
      } else {
        _store = await openStore();
      }
      _box = _store!.box<DocumentChunk>();
    }
  }

  @override
  Future<void> dispose() async {
    _store?.close();
    _store = null;
    _box = null;
  }

  @override
  Future<void> insert({
    required String documentId,
    required String chunkText,
    required List<double> embedding,
    String fileName = '',
    int chunkIndex = 0,
  }) async {
    final chunk = DocumentChunk(
      documentId: documentId,
      fileName: fileName,
      chunkIndex: chunkIndex,
      chunkText: chunkText,
      embedding: embedding,
    );
    _checkedBox.put(chunk);
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    List<double> queryEmbedding, {
    int k = 5,
  }) async {
    final query = _checkedBox
        .query(DocumentChunk_.embedding.nearestNeighborsF32(queryEmbedding, k))
        .build();
    try {
      final resultsWithScores = query.findWithScores();
      return resultsWithScores.map((item) {
        final chunk = item.object;
        return {
          'documentId': chunk.documentId,
          'fileName': chunk.fileName,
          'chunkIndex': chunk.chunkIndex,
          'chunkText': chunk.chunkText,
          'score': item.score,
        };
      }).toList();
    } finally {
      query.close();
    }
  }

  @override
  Future<void> deleteByDocumentId(String documentId) async {
    final query = _checkedBox
        .query(DocumentChunk_.documentId.equals(documentId))
        .build();
    try {
      query.remove();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<String>> listDocumentIds() async {
    final query = _checkedBox.query().build();
    try {
      final propQuery = query.property(DocumentChunk_.documentId);
      final allIds = propQuery.find();
      return allIds.toSet().toList();
    } finally {
      query.close();
    }
  }
}
