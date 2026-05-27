import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blackbox/flutter_blackbox.dart';

// Stub Storage and Socket Adapters for testing
class MockStorageAdapter extends BlackBoxStorageAdapter {
  @override
  String get name => 'MockStorage';
  @override
  Future<Map<String, String>> readAll() async => {};
  @override
  Future<void> write(String key, dynamic value) async {}
  @override
  Future<void> delete(String key) async {}
  @override
  Future<void> clear() async {}
}

class MockSocketAdapter extends BlackBoxSocketAdapter {
  @override
  String get name => 'MockSocket';
  @override
  void attach() {}
  @override
  void detach() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BlackBoxOverlay Dynamic Tabs Tests', () {
    setUp(() {
      // Clear configuration before each test
      BlackBox.dispose();
    });

    tearDown(() {
      BlackBox.dispose();
    });

    Future<void> runTest(
        WidgetTester tester, Future<void> Function() body) async {
      try {
        await body();
      } finally {
        // Dispose active BlackBox instance inside the test body (before _verifyInvariants runs)
        BlackBox.dispose();
      }
    }

    Future<void> pumpOverlay(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [BlackBox.journeyObserver],
          home: const BlackBoxOverlay(
            child: Scaffold(
              body: Center(child: Text('App Content')),
            ),
          ),
        ),
      );
    }

    testWidgets(
        'Overlay renders minimal tabs (7 tabs) by default without storage/socket adapters',
        (tester) async {
      await runTest(tester, () async {
        // Setup BlackBox
        BlackBox.setup(enabled: true);

        await pumpOverlay(tester);

        // Open the overlay programmatically
        BlackBox.open();
        await tester.pumpAndSettle();

        // Verify the overlay panel is visible
        expect(find.byType(TabBar), findsWidgets);

        // Verify we have tabs for Network, Logs, Perf, Rebuilds, Routes, Device, QA
        expect(find.text('Network'), findsWidgets);
        expect(find.text('Logs'), findsWidgets);
        expect(find.text('Perf'), findsWidgets);
        expect(find.text('Rebuilds'), findsWidgets);
        expect(find.text('Routes'), findsWidgets);
        expect(find.text('Device'), findsWidgets);
        expect(find.text('QA'), findsWidgets);

        // Verify that Storage and Socket IO tabs are NOT present
        expect(find.text('Storage'), findsNothing);
        expect(find.text('Socket IO'), findsNothing);
      });
    });

    testWidgets(
        'Overlay renders Storage tab when storage adapter is registered',
        (tester) async {
      await runTest(tester, () async {
        // Setup BlackBox with storage adapter
        BlackBox.setup(
          enabled: true,
          storageAdapters: [MockStorageAdapter()],
        );

        await pumpOverlay(tester);

        // Open the overlay programmatically
        BlackBox.open();
        await tester.pumpAndSettle();

        // Verify Storage tab is visible but Socket IO is not
        expect(find.text('Storage'), findsWidgets);
        expect(find.text('Socket IO'), findsNothing);
      });
    });

    testWidgets(
        'Overlay renders Socket IO tab when socket adapter is registered',
        (tester) async {
      await runTest(tester, () async {
        // Setup BlackBox with socket adapter
        BlackBox.setup(
          enabled: true,
          socketAdapters: [MockSocketAdapter()],
        );

        await pumpOverlay(tester);

        // Open the overlay programmatically
        BlackBox.open();
        await tester.pumpAndSettle();

        // Verify Socket IO tab is visible but Storage is not
        expect(find.text('Socket IO'), findsWidgets);
        expect(find.text('Storage'), findsNothing);
      });
    });

    testWidgets(
        'Overlay renders all 9 tabs when both storage and socket adapters are registered',
        (tester) async {
      await runTest(tester, () async {
        // Setup BlackBox with both adapters
        BlackBox.setup(
          enabled: true,
          storageAdapters: [MockStorageAdapter()],
          socketAdapters: [MockSocketAdapter()],
        );

        await pumpOverlay(tester);

        // Open the overlay programmatically
        BlackBox.open();
        await tester.pumpAndSettle();

        // Verify all tabs are visible
        expect(find.text('Network'), findsWidgets);
        expect(find.text('Logs'), findsWidgets);
        expect(find.text('Perf'), findsWidgets);
        expect(find.text('Rebuilds'), findsWidgets);
        expect(find.text('Storage'), findsWidgets);
        expect(find.text('Routes'), findsWidgets);
        expect(find.text('Socket IO'), findsWidgets);
        expect(find.text('Device'), findsWidgets);
        expect(find.text('QA'), findsWidgets);
      });
    });
  });
}
