/// Role of the entity that sent the message.
enum MessageRole {
  user,
  assistant,
}

/// Represents a source citation referencing a document chunk.
class CitationSource {
  final String documentId;
  final String fileName;
  final int chunkIndex;
  final String chunkText;
  final double score;

  const CitationSource({
    required this.documentId,
    required this.fileName,
    required this.chunkIndex,
    required this.chunkText,
    required this.score,
  });

  factory CitationSource.fromMap(Map<String, dynamic> map) {
    return CitationSource(
      documentId: map['documentId'] as String? ?? '',
      fileName: map['fileName'] as String? ?? '',
      chunkIndex: map['chunkIndex'] as int? ?? 0,
      chunkText: map['chunkText'] as String? ?? '',
      score: (map['score'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Represents a chat message in the conversation history.
class ChatMessage {
  final String id;
  final MessageRole role;
  String text;
  final List<CitationSource> sources;
  bool isStreaming;
  final String? loadingText;
  final DateTime timestamp;

  ChatMessage({
    String? id,
    required this.role,
    required this.text,
    List<CitationSource>? sources,
    this.isStreaming = false,
    this.loadingText,
    DateTime? timestamp,
  })  : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        sources = sources ?? const [],
        timestamp = timestamp ?? DateTime.now();
}
