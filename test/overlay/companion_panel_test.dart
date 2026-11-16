import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blackbox/src/overlay/panels/companion_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'CompanionPanel renders support buttons and companion url actions',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CompanionPanel(),
        ),
      ),
    );

    expect(find.text('flutter-blackbox-companion.web.app'), findsOneWidget);
    expect(find.text('Support BlackBox'), findsOneWidget);
    expect(find.text('Support (UPI)'), findsOneWidget);
    expect(find.text('Portfolio'), findsOneWidget);

    // Tap Support (UPI) button
    await tester.tap(find.text('Support (UPI)'));
    await tester.pumpAndSettle();

    // Tap Portfolio button
    await tester.tap(find.text('Portfolio'));
    await tester.pumpAndSettle();

    // Tap Step 1 text
    await tester.tap(find.text('flutter-blackbox-companion.web.app'));
    await tester.pumpAndSettle();

    // Tap copy button in Step 1
    await tester.tap(find.byIcon(Icons.copy_rounded));
    await tester.pump();
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

    // Fast-forward past the 2-second checkmark reset timer
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });
}
