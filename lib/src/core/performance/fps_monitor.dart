import 'dart:async';
import 'dart:collection';
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/scheduler.dart';

/// Monitors frame timing using [SchedulerBinding.addTimingsCallback].
///
/// Collects the last [sampleSize] frame durations and exposes rolling
/// FPS, average frame time, and worst frame time as a [Stream].
class FpsMonitor {
  FpsMonitor({
    this.sampleSize = 60,
    this.frameBudgetMs = 16.67,
    this.sessionHistorySize = 3600,
  });

  final int sampleSize;

  /// Frame budget in milliseconds. Frames exceeding this are counted as jank.
  final double frameBudgetMs;

  /// Maximum number of frame samples retained for session-level metrics.
  final int sessionHistorySize;

  final _frameDurations = ListQueue<double>(); // milliseconds
  final _buildDurations = ListQueue<double>();
  final _rasterDurations = ListQueue<double>();
  final _totalDurations = ListQueue<double>();
  int? _lastVsyncMicros;
  final _controller = StreamController<FpsSnapshot>.broadcast();
  bool _isRunning = false;
  bool _callbackRegistered = false;
  int _lastBroadcastMs = 0;
  late final void Function(List<FrameTiming>) _timingsCallback = _onTimings;

  // ponytail: session-level counters — O(1) per frame, no per-frame sorting
  final _sessionHistory = ListQueue<double>();
  int _totalFrames = 0;
  int _totalJankFrames = 0;
  DateTime? _sessionStart;
  double _cachedP95 = 0;
  int _lastP95CalcMs = 0;

  // ── Public API ──────────────────────────────────────────────────────

  /// Broadcast stream of performance snapshots, emitted every 250ms.
  Stream<FpsSnapshot> get stream => _controller.stream;

  /// The most recent performance snapshot.
  FpsSnapshot get current => _buildSnapshot();

  /// Total frames recorded since last [start].
  int get totalFrames => _totalFrames;

  /// Jank frames (exceeding [frameBudgetMs]) since last [start].
  int get totalJankFrames => _totalJankFrames;

  /// When the current monitoring session began.
  DateTime? get sessionStart => _sessionStart;

  void start() {
    reset(notify: false);
    resume();
  }

  /// Resumes collection without clearing the current session.
  void resume() {
    if (_isRunning) return;
    if (_controller.isClosed) return;
    _isRunning = true;
    _sessionStart ??= DateTime.now();
    if (!_callbackRegistered) {
      _callbackRegistered = true;
      SchedulerBinding.instance.addTimingsCallback(_timingsCallback);
    }
  }

  /// Pauses collection while retaining all samples and counters.
  void pause() {
    _isRunning = false;
    _lastVsyncMicros = null;
    if (_callbackRegistered) {
      SchedulerBinding.instance.removeTimingsCallback(_timingsCallback);
      _callbackRegistered = false;
    }
  }

  /// Stops collection and clears the current session.
  void stop() {
    pause();
    reset(notify: false);
  }

  /// Clears metrics without changing whether collection is active.
  void reset({bool notify = true}) {
    _frameDurations.clear();
    _buildDurations.clear();
    _rasterDurations.clear();
    _totalDurations.clear();
    _sessionHistory.clear();
    _totalFrames = 0;
    _totalJankFrames = 0;
    _sessionStart = null;
    _cachedP95 = 0;
    _lastP95CalcMs = 0;
    _lastVsyncMicros = null;
    _lastBroadcastMs = 0;
    if (notify && !_controller.isClosed) {
      _controller.add(_buildSnapshot());
    }
  }

  void dispose() {
    pause();
    reset(notify: false);
    _controller.close();
  }

  // ── Private ─────────────────────────────────────────────────────────

  void _onTimings(List<FrameTiming> timings) {
    if (!_isRunning || _controller.isClosed) return;

    for (final timing in timings) {
      final vsyncMicros = timing.timestampInMicroseconds(FramePhase.vsyncStart);
      final previousVsync = _lastVsyncMicros;
      _lastVsyncMicros = vsyncMicros;
      if (previousVsync == null) continue;

      final cadenceMs = (vsyncMicros - previousVsync) / 1000.0;
      if (cadenceMs <= 0) continue;

      _addRolling(_frameDurations, cadenceMs);
      _addRolling(
          _buildDurations, timing.buildDuration.inMicroseconds / 1000.0);
      _addRolling(
          _rasterDurations, timing.rasterDuration.inMicroseconds / 1000.0);
      _addRolling(_totalDurations, timing.totalSpan.inMicroseconds / 1000.0);

      _totalFrames++;
      if (cadenceMs > frameBudgetMs) _totalJankFrames++;
      if (_sessionHistory.length >= sessionHistorySize) {
        _sessionHistory.removeFirst();
      }
      _sessionHistory.addLast(cadenceMs);
    }

    if (_frameDurations.isEmpty) return;
    final nowMs = _lastVsyncMicros! ~/ 1000;
    if (nowMs - _lastBroadcastMs > 250) {
      _controller.add(_buildSnapshot());
      _lastBroadcastMs = nowMs;
    }
  }

  void _addRolling(ListQueue<double> queue, double value) {
    if (queue.length >= sampleSize) queue.removeFirst();
    queue.addLast(value);
  }

  // ponytail: cached p95, recalculated at most once per second
  double _computeSessionP95() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastP95CalcMs < 1000) return _cachedP95;
    _lastP95CalcMs = nowMs;
    if (_sessionHistory.isEmpty) return 0;
    final sorted = _sessionHistory.toList()..sort();
    _cachedP95 = sorted[(sorted.length * 0.95).floor()];
    return _cachedP95;
  }

  FpsSnapshot _buildSnapshot() {
    if (_frameDurations.isEmpty) {
      return FpsSnapshot(
        fps: 0,
        avgFrameMs: 0,
        worstFrameMs: 0,
        samples: const [],
        budgetMs: frameBudgetMs,
      );
    }
    final samples = _frameDurations.toList();
    final avgMs = samples.reduce((a, b) => a + b) / samples.length;
    final worstMs = samples.reduce((a, b) => a > b ? a : b);
    final fps = avgMs > 0 ? (1000 / avgMs).clamp(0, 120) : 0;
    final sessionDur = _sessionStart != null
        ? DateTime.now().difference(_sessionStart!)
        : Duration.zero;
    return FpsSnapshot(
      fps: fps.toDouble(),
      avgFrameMs: avgMs,
      worstFrameMs: worstMs,
      samples: List.unmodifiable(samples),
      budgetMs: frameBudgetMs,
      totalFrames: _totalFrames,
      totalJankFrames: _totalJankFrames,
      sessionP95Ms: _computeSessionP95(),
      sessionDuration: sessionDur,
      buildAvgMs: _average(_buildDurations),
      rasterAvgMs: _average(_rasterDurations),
      totalAvgMs: _average(_totalDurations),
    );
  }

  double _average(Iterable<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }
}

/// Immutable snapshot of current FPS metrics.
class FpsSnapshot {
  const FpsSnapshot({
    required this.fps,
    required this.avgFrameMs,
    required this.worstFrameMs,
    required this.samples,
    this.budgetMs = 16.67,
    this.totalFrames = 0,
    this.totalJankFrames = 0,
    this.sessionP95Ms = 0,
    this.sessionDuration = Duration.zero,
    this.buildAvgMs = 0,
    this.rasterAvgMs = 0,
    this.totalAvgMs = 0,
  });

  /// Computed frames per second.
  final double fps;

  /// Average frame duration in milliseconds.
  final double avgFrameMs;

  /// Duration of the slowest frame in the current window in milliseconds.
  final double worstFrameMs;

  /// Raw frame durations (ms) for the rolling window, oldest-first.
  final List<double> samples;

  /// Frame budget in milliseconds. Frames exceeding this are jank.
  final double budgetMs;

  /// Total frames recorded in the current session.
  final int totalFrames;

  /// Frames that exceeded [budgetMs] in the current session.
  final int totalJankFrames;

  /// 95th percentile frame duration for the session history.
  final double sessionP95Ms;

  /// Duration of the current monitoring session.
  final Duration sessionDuration;

  /// Average UI-thread build duration in the rolling window.
  final double buildAvgMs;

  /// Average raster-thread duration in the rolling window.
  final double rasterAvgMs;

  /// Average end-to-end frame latency in the rolling window.
  final double totalAvgMs;

  bool get isJanky => avgFrameMs > budgetMs;
  int get jankyFrameCount => samples.where((s) => s > budgetMs).length;
}
