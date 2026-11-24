import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/document_info.dart';
import '../../providers/knowledge_base_provider.dart';

/// Screen for managing indexed documents, picking new files, and tracking ingestion progress.
class DocumentsScreen extends StatelessWidget {
  const DocumentsScreen({super.key});

  Future<void> _pickAndIngestFile(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final provider = context.read<KnowledgeBaseProvider>();

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'txt', 'md'],
      );

      if (result == null || result.files.isEmpty) return;

      final path = result.files.first.path;
      if (path == null) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Could not access selected file path.')),
        );
        return;
      }

      final success = await provider.ingestFile(File(path));
      if (success) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Indexed "${result.files.first.name}" successfully'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      } else if (provider.errorMessage != null) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(provider.errorMessage!),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error selecting file: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, DocumentInfo doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Document'),
        content: Text('Remove "${doc.fileName}" and its indexed vectors?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await context.read<KnowledgeBaseProvider>().deleteDocument(doc.documentId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Consumer<KnowledgeBaseProvider>(
        builder: (context, provider, _) {
          return Column(
            children: [
              if (provider.isIngesting) ...[
                LinearProgressIndicator(
                  value: provider.progress > 0 ? provider.progress : null,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Ingesting and indexing document...',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              Expanded(
                child: provider.documents.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.folder_open_outlined,
                              size: 64,
                              color: theme.colorScheme.outline,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No documents indexed yet',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              child: Text(
                                'Tap the button below to add PDF, TXT, or Markdown documents to your personal knowledge base.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: provider.documents.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final doc = provider.documents[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              child: Icon(
                                Icons.description_outlined,
                                color: theme.colorScheme.onPrimaryContainer,
                                size: 22,
                              ),
                            ),
                            title: Text(
                              doc.fileName,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '${doc.chunkCount} chunks indexed',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              color: theme.colorScheme.error,
                              tooltip: 'Delete document',
                              onPressed: () => _confirmDelete(context, doc),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _pickAndIngestFile(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Document'),
      ),
    );
  }
}
