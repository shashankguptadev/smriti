import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/vector_store_service.dart';

/// Displays every indexed chunk for a single document.
/// Navigate here by tapping a document row in [DocumentsScreen].
class DocumentChunksScreen extends StatefulWidget {
  const DocumentChunksScreen({
    super.key,
    required this.documentId,
    required this.fileName,
  });

  final String documentId;
  final String fileName;

  @override
  State<DocumentChunksScreen> createState() => _DocumentChunksScreenState();
}

class _DocumentChunksScreenState extends State<DocumentChunksScreen> {
  late Future<List<Map<String, dynamic>>> _chunksFuture;

  @override
  void initState() {
    super.initState();
    _chunksFuture = context
        .read<VectorStoreService>()
        .getChunksByDocumentId(widget.documentId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: theme.colorScheme.outlineVariant),
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _chunksFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Error loading chunks:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            );
          }

          final chunks = snapshot.data ?? [];

          if (chunks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.layers_outlined,
                    size: 56,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No chunks indexed for this document.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: chunks.length,
            itemBuilder: (context, index) {
              final chunk = chunks[index];
              final chunkNumber = (chunk['chunkIndex'] as int) + 1;
              final chunkText = chunk['chunkText'] as String;

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                elevation: 0,
                color: theme.colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                    width: 0.5,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Chunk badge ──────────────────────────────────────
                      Chip(
                        label: Text(
                          'Chunk $chunkNumber',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        backgroundColor: theme.colorScheme.primaryContainer,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 0,
                        ),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      const SizedBox(height: 8),
                      // ── Chunk text ───────────────────────────────────────
                      SelectableText(
                        chunkText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                          height: 1.55,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
