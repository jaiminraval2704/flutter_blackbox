import 'package:flutter/foundation.dart';
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
    FlutterExceptionHandler? originalOnError;
    bool Function(Object, StackTrace)? originalPlatformOnError;
    DebugPrintCallback? originalDebugPrint;

    setUp(() {
      originalOnError = FlutterError.onError;
      originalPlatformOnError = PlatformDispatcher.instance.onError;
      originalDebugPrint = debugPrint;
      // Clear configuration before each test
      BlackBox.dispose();
    });

    tearDown(() {
      BlackBox.dispose();
      // Force restore standard test binding handlers to prevent invariant failures
      FlutterError.onError = originalOnError;
      PlatformDispatcher.instance.onError = originalPlatformOnError;
      if (originalDebugPrint != null) {
        debugPrint = originalDebugPrint!;
      }
    });

    Future<void> runTest(
        WidgetTester tester, Future<void> Function() body) async {
      try {
        await body();
      } finally {
        // Dispose active BlackBox instance inside the test body (before _verifyInvariants runs)
        BlackBox.dispose();
        // Force restore standard test binding handlers to prevent invariant failures
        FlutterError.onError = originalOnError;
        PlatformDispatcher.instance.onError = originalPlatformOnError;
        if (originalDebugPrint != null) {
          debugPrint = originalDebugPrint!;
        }
      }
    }

    Future<void> pumpOverlay(WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BlackBoxOverlay(
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
        expect(find.byType(TabBar), findsOneWidget);

        // Verify we have tabs for Network, Logs, Perf, Rebuilds, Routes, Device, QA
        expect(find.text('Network'), findsOneWidget);
        expect(find.text('Logs'), findsOneWidget);
        expect(find.text('Perf'), findsOneWidget);
        expect(find.text('Rebuilds'), findsOneWidget);
        expect(find.text('Routes'), findsOneWidget);
        expect(find.text('Device'), findsOneWidget);
        expect(find.text('QA'), findsOneWidget);

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
        expect(find.text('Storage'), findsOneWidget);
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
        expect(find.text('Socket IO'), findsOneWidget);
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
        expect(find.text('Network'), findsOneWidget);
        expect(find.text('Logs'), findsOneWidget);
        expect(find.text('Perf'), findsOneWidget);
        expect(find.text('Rebuilds'), findsOneWidget);
        expect(find.text('Storage'), findsOneWidget);
        expect(find.text('Routes'), findsOneWidget);
        expect(find.text('Socket IO'), findsOneWidget);
        expect(find.text('Device'), findsOneWidget);
        expect(find.text('QA'), findsOneWidget);
      });
    });
  });
}
