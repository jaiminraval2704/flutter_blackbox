import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blackbox/flutter_blackbox.dart';

class _TestHttpAdapter extends BlackBoxHttpAdapter {
  @override
  String get name => 'test';
}

class _ThrowingHttpAdapter extends BlackBoxHttpAdapter {
  bool detached = false;

  @override
  String get name => 'throwing';

  @override
  void attach() => throw StateError('attach failed');

  @override
  void detach() => detached = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BlackBox setup & store resetting', () {
    tearDown(() {
      BlackBox.dispose();
    });

    test('setup clears all stores on re-initialisation', () {
      // 1. Initial setup
      BlackBox.setup(enabled: true);

      // 2. Add some mock data into various stores
      BlackBox.log('Test log');
      BlackBox.instance.navigationStore.onPush('/route', null);
      BlackBox.instance.rebuildStore.record('WidgetA');
      BlackBox.logSocketEvent('my_event', 'my_data');

      // Verify they are populated
      expect(BlackBox.instance.logStore.entries, isNotEmpty);
      expect(BlackBox.instance.navigationStore.currentStack, isNotEmpty);
      expect(BlackBox.instance.rebuildStore.counts, isNotEmpty);
      expect(BlackBox.instance.socketStore.events, isNotEmpty);

      // 3. Call setup again
      BlackBox.setup(enabled: true);

      // 4. Verify they are all cleared
      expect(BlackBox.instance.logStore.entries, isEmpty);
      expect(BlackBox.instance.navigationStore.currentStack, isEmpty);
      expect(BlackBox.instance.rebuildStore.counts, isEmpty);
      expect(BlackBox.instance.socketStore.events, isEmpty);
    });

    test('store subscriptions survive dispose and setup', () async {
      BlackBox.setup(enabled: true);
      final messages = <String>[];
      final sub = BlackBox.instance.logStore.stream.listen(
        (entries) => messages.addAll(entries.map((entry) => entry.message)),
      );

      BlackBox.dispose();
      BlackBox.setup(enabled: true);
      BlackBox.log('after restart');
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(messages, contains('after restart'));
      await sub.cancel();
    });

    test('dispose cancels pending store notifications', () async {
      BlackBox.setup(enabled: true);
      var emissions = 0;
      final sub = BlackBox.instance.logStore.stream.listen((_) => emissions++);

      BlackBox.log('pending');
      BlackBox.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(emissions, 0);
      await sub.cancel();
    });

    test('pause rejects new capture but completes an in-flight request',
        () async {
      final adapter = _TestHttpAdapter();
      BlackBox.setup(enabled: true, httpAdapters: [adapter]);
      final now = DateTime(2026);

      adapter.onRequest(NetworkRequest(
        id: 'before-pause',
        method: 'GET',
        url: 'https://example.test/one',
        timestamp: now,
      ));
      BlackBox.pauseCapture();
      BlackBox.log('ignored');
      adapter.onRequest(NetworkRequest(
        id: 'while-paused',
        method: 'GET',
        url: 'https://example.test/two',
        timestamp: now,
      ));
      adapter.onResponse(NetworkResponse(
        requestId: 'before-pause',
        statusCode: 200,
        headers: const {},
        durationMs: 12,
      ));

      expect(BlackBox.isCapturing, isFalse);
      expect(BlackBox.instance.logStore.entries, isEmpty);
      expect(BlackBox.instance.networkStore.entries, hasLength(1));
      expect(BlackBox.instance.networkStore.entries.single.isPending, isFalse);

      BlackBox.resumeCapture();
      BlackBox.log('recorded');
      expect(BlackBox.isCapturing, isTrue);
      expect(BlackBox.instance.logStore.entries.single.message, 'recorded');
    });

    test('clear retains capture state and resets all captured stores', () {
      BlackBox.setup(enabled: true);
      BlackBox.log('log');
      BlackBox.logSocketEvent('event', {'value': 1});
      BlackBox.instance.navigationStore.onPush('/route', {'id': 1});
      BlackBox.pauseCapture();

      BlackBox.clearCapturedData();

      expect(BlackBox.isCapturing, isFalse);
      expect(BlackBox.instance.logStore.entries, isEmpty);
      expect(BlackBox.instance.socketStore.events, isEmpty);
      expect(BlackBox.instance.navigationStore.history, isEmpty);
    });

    test('dispose restores nullable global error handlers exactly', () {
      final oldFlutterHandler = FlutterError.onError;
      final oldPlatformHandler = PlatformDispatcher.instance.onError;
      void flutterHandler(FlutterErrorDetails details) {}
      bool platformHandler(Object error, StackTrace stack) => true;

      try {
        FlutterError.onError = flutterHandler;
        PlatformDispatcher.instance.onError = platformHandler;
        BlackBox.setup(enabled: true);

        expect(FlutterError.onError, isNot(same(flutterHandler)));
        expect(
            PlatformDispatcher.instance.onError, isNot(same(platformHandler)));

        BlackBox.dispose();
        expect(FlutterError.onError, same(flutterHandler));
        expect(PlatformDispatcher.instance.onError, same(platformHandler));
      } finally {
        BlackBox.dispose();
        FlutterError.onError = oldFlutterHandler;
        PlatformDispatcher.instance.onError = oldPlatformHandler;
      }
    });

    test('failed setup detaches a partially attached adapter', () {
      final adapter = _ThrowingHttpAdapter();

      expect(
        () => BlackBox.setup(enabled: true, httpAdapters: [adapter]),
        throwsStateError,
      );

      expect(adapter.detached, isTrue);
      expect(adapter.onRequestCallback, isNull);
      expect(adapter.onResponseCallback, isNull);
      expect(BlackBox.instance.isEnabled, isFalse);
    });
  });
}
