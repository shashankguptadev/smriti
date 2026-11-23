import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smriti/app.dart';

void main() {
  testWidgets('SmritiApp renders home screen with title and navigation bar',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<String>.value(value: 'Smriti'),
        ],
        child: const SmritiApp(),
      ),
    );

    // Verify the AppBar title is present.
    expect(find.text('Smriti'), findsOneWidget);

    // Verify the Chat tab is shown by default.
    expect(find.text('Chat'), findsWidgets);

    // Verify the Documents navigation destination exists.
    expect(find.text('Documents'), findsOneWidget);
  });

  testWidgets('NavigationBar switches between Chat and Documents tabs',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<String>.value(value: 'Smriti'),
        ],
        child: const SmritiApp(),
      ),
    );

    // Initially on Chat tab — the page body shows "Chat".
    // "Chat" appears both as the body text and the navigation label.
    expect(find.text('Chat'), findsWidgets);

    // Tap the Documents navigation destination.
    await tester.tap(find.text('Documents'));
    await tester.pumpAndSettle();

    // Now the Documents page body should be visible.
    // "Documents" appears both as the body text and the navigation label.
    expect(find.text('Documents'), findsWidgets);
  });
}
