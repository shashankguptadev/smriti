import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smriti/providers/knowledge_base_provider.dart';
import 'package:smriti/services/in_memory_vector_store.dart';
import 'package:smriti/services/local_document_ingestor.dart';
import 'package:smriti/services/mock_embedding_service.dart';
import 'package:smriti/ui/screens/documents_screen.dart';

void main() {
  group('DocumentsScreen', () {
    late KnowledgeBaseProvider provider;

    setUp(() {
      provider = KnowledgeBaseProvider(
        ingestor: const LocalDocumentIngestor(),
        embeddingService: const MockEmbeddingService(),
        vectorStoreService: InMemoryVectorStore(),
      );
    });

    testWidgets('renders empty state when no documents exist', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<KnowledgeBaseProvider>.value(
            value: provider,
            child: const DocumentsScreen(),
          ),
        ),
      );

      expect(find.text('No documents indexed yet'), findsOneWidget);
      expect(find.text('Add Document'), findsOneWidget);
    });

    testWidgets('renders floating action button to add document', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<KnowledgeBaseProvider>.value(
            value: provider,
            child: const DocumentsScreen(),
          ),
        ),
      );

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });
  });
}
