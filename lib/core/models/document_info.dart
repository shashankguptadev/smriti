/// Represents high-level metadata for an indexed document in the knowledge base.
class DocumentInfo {
  final String documentId;
  final String fileName;
  final int chunkCount;
  final DateTime indexedAt;

  DocumentInfo({
    required this.documentId,
    required this.fileName,
    this.chunkCount = 0,
    DateTime? indexedAt,
  }) : indexedAt = indexedAt ?? DateTime.now();
}
