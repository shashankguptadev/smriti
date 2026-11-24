import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/model_manager_provider.dart';

/// First-launch onboarding screen for configuring local .litertlm model weights.
class ModelManagerScreen extends StatelessWidget {
  final VoidCallback? onSetupComplete;

  const ModelManagerScreen({super.key, this.onSetupComplete});

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
                  const SizedBox(height: 32),
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
                                Icons.info_outline,
                                size: 20,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Model Requirements',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '• File format: .litertlm\n• Target architecture: Android ARM64\n• Recommended quantization: 4-bit (1B–2B params)',
                            style: theme.textTheme.bodySmall,
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
                      label: const Text('Import .litertlm Model'),
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
                      child: const Text('Skip / Use Mock Engine'),
                      onPressed: () {
                        provider.useMockOrBypass();
                        onSetupComplete?.call();
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
