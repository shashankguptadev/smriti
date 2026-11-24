import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../core/models/document_info.dart';
import '../core/services/document_ingestor.dart';
import '../core/services/embedding_service.dart';
import '../core/services/vector_store_service.dart';

/// Status of the document ingestion workflow.
enum IngestionStatus {
  idle,
  ingesting,
  error,
}

/// [ChangeNotifier] managing the personal knowledge base index, document ingestion,
/// and document deletions.
class KnowledgeBaseProvider extends ChangeNotifier {
  final DocumentIngestor ingestor;
  final EmbeddingService embeddingService;
  final VectorStoreService vectorStoreService;

  final List<DocumentInfo> _documents = [];
  IngestionStatus _status = IngestionStatus.idle;
  String? _errorMessage;
  double _progress = 0.0;

  KnowledgeBaseProvider({
    required this.ingestor,
    required this.embeddingService,
    required this.vectorStoreService,
  });

  List<DocumentInfo> get documents => List.unmodifiable(_documents);
  IngestionStatus get status => _status;
  String? get errorMessage => _errorMessage;
  double get progress => _progress;
  bool get isIngesting => _status == IngestionStatus.ingesting;

  /// Loads stored documents from the vector store on startup.
  Future<void> loadDocuments() async {
    try {
      final docIds = await vectorStoreService.listDocumentIds();
      // Keep existing metadata or create fresh entries from IDs
      final currentMap = {for (final d in _documents) d.documentId: d};
      _documents.clear();
      for (final id in docIds) {
        if (currentMap.containsKey(id)) {
          _documents.add(currentMap[id]!);
        } else {
          _documents.add(DocumentInfo(
            documentId: id,
            fileName: p.basename(id),
          ));
        }
      }
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load documents: $e';
      notifyListeners();
    }
  }

  /// Ingests [file], generates embeddings for its chunks, and persists them into the vector store.
  Future<bool> ingestFile(File file) async {
    _status = IngestionStatus.ingesting;
    _errorMessage = null;
    _progress = 0.0;
    notifyListeners();

    try {
      final fileName = p.basename(file.path);
      final documentId = file.path;

      // 1. Chunk document via Isolate
      final chunks = await ingestor.ingest(file);
      if (chunks.isEmpty) {
        throw FormatException('No readable text found in $fileName');
      }
      _progress = 0.35;
      notifyListeners();

      // 2. Generate vector embeddings in batch
      final embeddings = await embeddingService.embedBatch(chunks);
      _progress = 0.70;
      notifyListeners();

      // 3. Remove any previous chunks for the same document ID to prevent duplicates
      await vectorStoreService.deleteByDocumentId(documentId);

      // 4. Insert all chunks and embeddings into the vector store
      for (int i = 0; i < chunks.length; i++) {
        await vectorStoreService.insert(
          documentId: documentId,
          fileName: fileName,
          chunkIndex: i,
          chunkText: chunks[i],
          embedding: embeddings[i],
        );
      }

      // 5. Update state
      _documents.removeWhere((doc) => doc.documentId == documentId);
      _documents.add(DocumentInfo(
        documentId: documentId,
        fileName: fileName,
        chunkCount: chunks.length,
      ));

      _status = IngestionStatus.idle;
      _progress = 1.0;
      notifyListeners();
      return true;
    } catch (e) {
      _status = IngestionStatus.error;
      _errorMessage = e.toString();
      _progress = 0.0;
      notifyListeners();
      return false;
    }
  }

  /// Deletes a document and its indexed vectors.
  Future<void> deleteDocument(String documentId) async {
    try {
      await vectorStoreService.deleteByDocumentId(documentId);
      _documents.removeWhere((doc) => doc.documentId == documentId);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to delete document: $e';
      notifyListeners();
    }
  }
}
