import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blackbox/src/core/performance/fps_monitor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FpsSnapshot', () {
    test('isJanky when avgFrameMs > 16.67', () {
      const snap = FpsSnapshot(
        fps: 30,
        avgFrameMs: 33.0,
        worstFrameMs: 33.0,
        samples: [33.0],
      );
      expect(snap.isJanky, isTrue);
    });

    test('not janky at 60fps', () {
      final snap = FpsSnapshot(
        fps: 60,
        avgFrameMs: 16.0,
        worstFrameMs: 16.5,
        samples: List.filled(60, 16.0),
      );
      expect(snap.isJanky, isFalse);
    });

    test('jankyFrameCount counts frames over budget', () {
      const snap = FpsSnapshot(
        fps: 45,
        avgFrameMs: 18.0,
        worstFrameMs: 40.0,
        samples: [10.0, 20.0, 40.0, 12.0, 25.0],
      );
      // Frames > 16.67ms: 20.0, 40.0, 25.0 → count = 3
      expect(snap.jankyFrameCount, 3);
    });

    test('default budgetMs is 16.67', () {
      const snap =
          FpsSnapshot(fps: 0, avgFrameMs: 0, worstFrameMs: 0, samples: []);
      expect(snap.budgetMs, closeTo(16.67, 0.01));
    });

    test('new timing fields default to zero for source compatibility', () {
      const snap =
          FpsSnapshot(fps: 60, avgFrameMs: 16, worstFrameMs: 16, samples: []);

      expect(snap.buildAvgMs, 0);
      expect(snap.rasterAvgMs, 0);
      expect(snap.totalAvgMs, 0);
    });
  });

  group('FpsMonitor', () {
    test('current returns zero snapshot before start', () {
      final monitor = FpsMonitor();
      final snap = monitor.current;
      expect(snap.fps, 0);
      expect(snap.samples, isEmpty);
    });

    test('stop clears state', () {
      final monitor = FpsMonitor();
      monitor.stop();
      expect(monitor.current.samples, isEmpty);
      monitor.dispose();
    });

    test('pause and resume preserve the session', () {
      final monitor = FpsMonitor();
      monitor.start();
      final startedAt = monitor.sessionStart;

      monitor.pause();
      monitor.resume();

      expect(startedAt, isNotNull);
      expect(monitor.sessionStart, startedAt);
      monitor.dispose();
    });

    test('dispose closes stream', () {
      final monitor = FpsMonitor();
      monitor.dispose();
      expect(monitor.stream.isBroadcast, isTrue);
    });
  });
}
