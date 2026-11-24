import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smriti/providers/model_manager_provider.dart';
import 'package:smriti/ui/screens/model_manager_screen.dart';

void main() {
  group('ModelManagerScreen', () {
    late ModelManagerProvider provider;

    setUp(() {
      provider = ModelManagerProvider();
    });

    testWidgets('renders onboarding headers and action buttons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ModelManagerProvider>.value(
            value: provider,
            child: const ModelManagerScreen(),
          ),
        ),
      );

      expect(find.text('AI Model Setup'), findsOneWidget);
      expect(find.text('On-Device AI Engine'), findsOneWidget);
      expect(find.text('Import .litertlm Model'), findsOneWidget);
      expect(find.text('Skip / Use Mock Engine'), findsOneWidget);
    });

    testWidgets('skip button invokes onSetupComplete callback', (tester) async {
      bool completed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ModelManagerProvider>.value(
            value: provider,
            child: ModelManagerScreen(
              onSetupComplete: () {
                completed = true;
              },
            ),
          ),
        ),
      );

      final skipButton = find.text('Skip / Use Mock Engine');
      await tester.ensureVisible(skipButton);
      await tester.tap(skipButton);
      await tester.pumpAndSettle();

      expect(completed, isTrue);
      expect(provider.isModelReady, isTrue);
    });
  });
}
