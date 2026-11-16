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

    testWidgets('capture can pause and resume from the existing header',
        (tester) async {
      await runTest(tester, () async {
        BlackBox.setup(enabled: true);
        await pumpOverlay(tester);
        BlackBox.open();
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Pause capture'));
        await tester.pump();
        expect(BlackBox.isCapturing, isFalse);
        expect(find.byTooltip('Resume capture'), findsOneWidget);

        await tester.tap(find.byTooltip('Resume capture'));
        await tester.pump();
        expect(BlackBox.isCapturing, isTrue);
      });
    });

    testWidgets('overlay header renders without overflow on small screens',
        (tester) async {
      for (final width in [320.0, 360.0, 390.0]) {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());
        addTearDown(() => tester.view.resetDevicePixelRatio());

        await runTest(tester, () async {
          BlackBox.setup(enabled: true);
          await pumpOverlay(tester);
          BlackBox.open();
          await tester.pumpAndSettle();

          expect(find.byTooltip('Pause capture'), findsOneWidget);
          expect(find.byTooltip('Capture actions'), findsOneWidget);
          expect(find.byTooltip('Search'), findsOneWidget);
          expect(find.byTooltip('Pin to HUD'), findsOneWidget);
          expect(find.byTooltip('Close'), findsOneWidget);
        });
      }
    });

    testWidgets('floating button can be dragged without error', (tester) async {
      await runTest(tester, () async {
        BlackBox.setup(
          enabled: true,
          trigger: const BlackBoxTrigger.floatingButton(),
        );
        await pumpOverlay(tester);

        final buttonFinder = find.byIcon(Icons.bug_report);
        expect(buttonFinder, findsOneWidget);

        // Drag the button
        await tester.drag(buttonFinder, const Offset(-100, -100));
        await tester.pumpAndSettle();

        expect(buttonFinder, findsOneWidget);
      });
    });

    testWidgets('pinning to HUD mode displays live counters and unpins cleanly',
        (tester) async {
      await runTest(tester, () async {
        BlackBox.setup(
          enabled: true,
          trigger: const BlackBoxTrigger.floatingButton(),
        );
        await pumpOverlay(tester);

        BlackBox.open();
        await tester.pumpAndSettle();

        // Tap pin to HUD
        await tester.tap(find.byTooltip('Pin to HUD'));
        await tester.pumpAndSettle();

        // Speed icon should be visible in HUD
        expect(find.byIcon(Icons.speed), findsOneWidget);
        expect(find.byIcon(Icons.wifi), findsOneWidget);

        // Tap close / unpin icon on HUD
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        // Should return to normal floating bug button
        expect(find.byIcon(Icons.bug_report), findsOneWidget);
      });
    });

    testWidgets(
        'floating button mounts safely when screen size is zero or very small',
        (tester) async {
      tester.view.physicalSize = const Size(0, 0);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await runTest(tester, () async {
        BlackBox.setup(
          enabled: true,
          trigger: const BlackBoxTrigger.floatingButton(),
        );
        await pumpOverlay(tester);
        expect(tester.takeException(), isNull);
      });
    });
  });
}
