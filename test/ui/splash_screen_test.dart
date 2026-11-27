import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smriti/providers/app_init_provider.dart';
import 'package:smriti/ui/screens/splash_screen.dart';

void main() {
  group('SplashScreen', () {
    Widget buildTestApp(AppInitProvider provider) {
      return ChangeNotifierProvider<AppInitProvider>.value(
        value: provider,
        child: const MaterialApp(home: SplashScreen()),
      );
    }

    testWidgets('shows app name "Smriti"', (tester) async {
      final provider = AppInitProvider();
      await tester.pumpWidget(buildTestApp(provider));
      await tester.pump();

      expect(find.text('Smriti'), findsOneWidget);
    });

    testWidgets('shows subtitle', (tester) async {
      final provider = AppInitProvider();
      await tester.pumpWidget(buildTestApp(provider));
      await tester.pump();

      expect(find.text('Offline Knowledge Assistant'), findsOneWidget);
    });

    testWidgets('shows stage message from provider', (tester) async {
      final provider = AppInitProvider();
      provider.advance(InitStage.openingDatabase, 'Opening knowledge base…', 0.45);

      await tester.pumpWidget(buildTestApp(provider));
      await tester.pump();

      expect(find.text('Opening knowledge base…'), findsOneWidget);
    });

    testWidgets('shows error message when provider is in error state', (tester) async {
      final provider = AppInitProvider();
      provider.fail('Database failed to open.');

      await tester.pumpWidget(buildTestApp(provider));
      await tester.pump();

      expect(find.text('Database failed to open.'), findsOneWidget);
    });

    testWidgets('progress bar is indeterminate initially', (tester) async {
      final provider = AppInitProvider();
      // progress == 0.0 initially → indeterminate LinearProgressIndicator
      await tester.pumpWidget(buildTestApp(provider));
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });

  group('AppInitProvider', () {
    test('initial state is starting with 0 progress', () {
      final provider = AppInitProvider();
      expect(provider.stage, equals(InitStage.starting));
      expect(provider.progress, equals(0.0));
      expect(provider.isReady, isFalse);
      expect(provider.hasError, isFalse);
    });

    test('advance updates stage message and progress', () {
      final provider = AppInitProvider();
      provider.advance(InitStage.checkingModels, 'Checking models…', 0.25);

      expect(provider.stage, equals(InitStage.checkingModels));
      expect(provider.message, equals('Checking models…'));
      expect(provider.progress, closeTo(0.25, 0.001));
      expect(provider.isReady, isFalse);
      expect(provider.hasError, isFalse);
    });

    test('fail transitions to error state', () {
      final provider = AppInitProvider();
      provider.fail('Something went wrong.');

      expect(provider.stage, equals(InitStage.error));
      expect(provider.hasError, isTrue);
      expect(provider.errorMessage, equals('Something went wrong.'));
      expect(provider.isReady, isFalse);
    });

    test('complete transitions to ready state with full progress', () {
      final provider = AppInitProvider();
      provider.complete();

      expect(provider.stage, equals(InitStage.ready));
      expect(provider.isReady, isTrue);
      expect(provider.progress, equals(1.0));
      expect(provider.hasError, isFalse);
    });

    test('advance clears error state', () {
      final provider = AppInitProvider();
      provider.fail('Error!');
      expect(provider.hasError, isTrue);

      provider.advance(InitStage.loadingModel, 'Loading…', 0.6);
      expect(provider.hasError, isFalse);
      expect(provider.errorMessage, isNull);
    });

    test('progress is clamped to [0.0, 1.0]', () {
      final provider = AppInitProvider();
      provider.advance(InitStage.loadingModel, 'msg', 1.5);
      expect(provider.progress, equals(1.0));

      provider.advance(InitStage.loadingModel, 'msg', -0.1);
      expect(provider.progress, equals(0.0));
    });

    test('notifies listeners on advance', () {
      final provider = AppInitProvider();
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.advance(InitStage.checkingModels, 'msg', 0.5);
      expect(notifyCount, equals(1));

      provider.complete();
      expect(notifyCount, equals(2));
    });
  });
}
