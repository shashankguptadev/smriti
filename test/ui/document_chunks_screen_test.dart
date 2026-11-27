import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smriti/core/services/vector_store_service.dart';
import 'package:smriti/core/models/document_info.dart';
import 'package:smriti/ui/screens/document_chunks_screen.dart';

// ---------------------------------------------------------------------------
// Minimal stub — only getChunksByDocumentId needs to work in these tests.
// ---------------------------------------------------------------------------
class _StubVectorStore implements VectorStoreService {
  final List<Map<String, dynamic>> _response;
  final Object? _error;

  _StubVectorStore({List<Map<String, dynamic>>? response, Object? error})
      : _response = response ?? [],
        _error = error;

  @override
  Future<List<Map<String, dynamic>>> getChunksByDocumentId(
    String documentId,
  ) async {
    if (_error != null) throw _error;
    return _response;
  }

  // ── Unused stubs ──────────────────────────────────────────────────────────
  @override Future<void> initialize() async {}
  @override Future<void> dispose() async {}
  @override Future<void> insert({
    required String documentId,
    required String chunkText,
    required List<double> embedding,
    String fileName = '',
    int chunkIndex = 0,
  }) async {}
  @override Future<List<Map<String, dynamic>>> query(
    List<double> queryEmbedding, {int k = 5}) async => [];
  @override Future<void> deleteByDocumentId(String documentId) async {}
  @override Future<List<String>> listDocumentIds() async => [];
  @override Future<List<DocumentInfo>> listDocumentSummaries() async => [];
  @override Future<List<Map<String, dynamic>>> getAllChunks() async => [];
}

// ---------------------------------------------------------------------------
// Helper to pump the screen with a given stub store.
// ---------------------------------------------------------------------------
Widget _buildScreen(
  _StubVectorStore store, {
  String documentId = 'doc-1',
  String fileName = 'test.pdf',
}) {
  return MaterialApp(
    home: Provider<VectorStoreService>.value(
      value: store,
      child: DocumentChunksScreen(
        documentId: documentId,
        fileName: fileName,
      ),
    ),
  );
}

void main() {
  group('DocumentChunksScreen', () {
    testWidgets('shows CircularProgressIndicator while loading', (tester) async {
      // Use a completer-based store so the future never completes during the
      // first pump, letting us observe the loading state.
      final store = _StubVectorStore(response: []);

      await tester.pumpWidget(_buildScreen(store));
      // After first frame the FutureBuilder is in "waiting" state.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders chunk list with correct labels and text', (tester) async {
      final store = _StubVectorStore(response: [
        {'chunkIndex': 0, 'chunkText': 'First chunk content'},
        {'chunkIndex': 1, 'chunkText': 'Second chunk content'},
      ]);

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      expect(find.text('Chunk 1'), findsOneWidget);
      expect(find.text('Chunk 2'), findsOneWidget);
      expect(find.text('First chunk content'), findsOneWidget);
      expect(find.text('Second chunk content'), findsOneWidget);
    });

    testWidgets('shows empty state when no chunks found', (tester) async {
      final store = _StubVectorStore(response: []);

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      expect(find.text('No chunks indexed for this document.'), findsOneWidget);
    });

    testWidgets('shows error message on failure', (tester) async {
      final store = _StubVectorStore(error: Exception('DB error'));

      await tester.pumpWidget(_buildScreen(store));
      await tester.pumpAndSettle();

      expect(find.textContaining('Error loading chunks'), findsOneWidget);
    });

    testWidgets('AppBar shows file name', (tester) async {
      final store = _StubVectorStore(response: []);

      await tester.pumpWidget(_buildScreen(store, fileName: 'lecture.pdf'));
      await tester.pumpAndSettle();

      expect(find.text('lecture.pdf'), findsOneWidget);
    });
  });
}
