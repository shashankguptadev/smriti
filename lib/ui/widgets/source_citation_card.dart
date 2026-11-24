import 'package:flutter/material.dart';
import '../../core/models/chat_message.dart';

/// Expandable card displaying a source document citation and excerpt.
class SourceCitationCard extends StatelessWidget {
  final CitationSource source;

  const SourceCitationCard({super.key, required this.source});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final distance = source.score.toStringAsFixed(2);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        leading: Icon(
          Icons.description_outlined,
          size: 20,
          color: theme.colorScheme.primary,
        ),
        title: Text(
          source.fileName.isNotEmpty ? source.fileName : 'Document chunk',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          'Chunk ${source.chunkIndex + 1} • Distance $distance',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        children: [
          SelectableText(
            source.chunkText,
            style: theme.textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
