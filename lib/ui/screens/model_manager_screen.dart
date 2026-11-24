import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/model_manager_provider.dart';

/// Screen for downloading, configuring, and inspecting on-device LiteRT models.
class ModelManagerScreen extends StatelessWidget {
  final VoidCallback? onSetupComplete;

  const ModelManagerScreen({super.key, this.onSetupComplete});

  Future<void> _launchExternalUrl(BuildContext context, String urlString) async {
    final uri = Uri.parse(urlString);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open browser for $urlString')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to launch link: $e')),
        );
      }
    }
  }

  Future<void> _pickAndImportModel(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final provider = context.read<ModelManagerProvider>();

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['litertlm', 'bin'],
      );

      if (result == null || result.files.isEmpty) return;

      final path = result.files.first.path;
      if (path == null) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Could not access selected file path.')),
        );
        return;
      }

      final success = await provider.importLocalModel(File(path));
      if (success) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Model weights imported successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        onSetupComplete?.call();
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error selecting model: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Model Setup'),
        centerTitle: true,
      ),
      body: Consumer<ModelManagerProvider>(
        builder: (context, provider, _) {
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.memory,
                    size: 72,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'On-Device AI Engine',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Smriti executes answers completely offline using local LiteRT (.litertlm) model weights.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Active Model Card (if present)
                  if (provider.hasRealModel) ...[
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.primaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Active On-Device Model',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'File: ${p.basename(provider.activeModelPath!)}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                            Text(
                              'Size: ${_formatBytes(provider.modelSizeBytes)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                TextButton.icon(
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                  label: const Text('Delete'),
                                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                                  onPressed: () => provider.deleteActiveModel(),
                                ),
                                const Spacer(),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: const Text('Replace'),
                                  onPressed: () => _pickAndImportModel(context),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ] else if (provider.status == ModelStatus.mockBypass) ...[
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.secondaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              Icons.science_outlined,
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Running in Mock Mode',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.onSecondaryContainer,
                                    ),
                                  ),
                                  Text(
                                    'Simulation engine active without weights.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSecondaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Hugging Face Download Links
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.cloud_download_outlined,
                                size: 20,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Download Model from Hugging Face',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Download a .litertlm file to your device Downloads folder, then tap "Import .litertlm Model" below.',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Gemma 4 E2B (Recommended, ~2.58 GB)'),
                            subtitle: const Text('High accuracy, open license'),
                            trailing: const Icon(Icons.open_in_new, size: 20),
                            onTap: () => _launchExternalUrl(
                              context,
                              'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/tree/main',
                            ),
                          ),
                          const Divider(),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Qwen3 0.6B (Lightweight, ~350 MB)'),
                            subtitle: const Text('Compact for lower-RAM devices'),
                            trailing: const Icon(Icons.open_in_new, size: 20),
                            onTap: () => _launchExternalUrl(
                              context,
                              'https://huggingface.co/litert-community/Qwen3-0.6B/tree/main',
                            ),
                          ),
                          const Divider(),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Browse All Android Models'),
                            subtitle: const Text('LiteRT Android Community Collection'),
                            trailing: const Icon(Icons.open_in_new, size: 20),
                            onTap: () => _launchExternalUrl(
                              context,
                              'https://huggingface.co/collections/litert-community/android-models',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (provider.status == ModelStatus.importing) ...[
                    LinearProgressIndicator(value: provider.progress),
                    const SizedBox(height: 12),
                    Text(
                      'Copying model into app storage...',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  if (provider.errorMessage != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        provider.errorMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.file_upload_outlined),
                      label: Text(provider.hasRealModel ? 'Replace with New Model' : 'Import .litertlm Model'),
                      onPressed: provider.status == ModelStatus.importing
                          ? null
                          : () => _pickAndImportModel(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      child: Text(provider.hasRealModel ? 'Switch to Mock Engine' : 'Skip / Use Mock Engine'),
                      onPressed: () {
                        provider.useMockOrBypass();
                        onSetupComplete?.call();
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
