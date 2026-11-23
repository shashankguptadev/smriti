import 'package:objectbox/objectbox.dart';

/// Represents a single text chunk and its vector embedding persisted in ObjectBox.
@Entity()
class DocumentChunk {
  @Id()
  int id;

  /// Logical identifier of the parent document (e.g. file path or hash).
  String documentId;

  /// Display name of the document file.
  String fileName;

  /// The index position of this chunk within the document.
  int chunkIndex;

  /// The text content of this chunk.
  String chunkText;

  /// The 384-dimensional vector embedding indexed with HNSW cosine distance.
  @HnswIndex(dimensions: 384, distanceType: VectorDistanceType.cosine)
  @Property(type: PropertyType.floatVector)
  List<double>? embedding;

  DocumentChunk({
    this.id = 0,
    required this.documentId,
    this.fileName = '',
    this.chunkIndex = 0,
    required this.chunkText,
    this.embedding,
  });
}

