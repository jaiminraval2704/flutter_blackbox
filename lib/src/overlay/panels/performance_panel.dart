import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/performance/fps_monitor.dart';
import '../../core/performance/memory_info.dart' as mem;
import '../../blackbox.dart';
import '../../companion/firebase_streamer.dart';
import '../widgets/blackbox_colors.dart';

class PerformancePanel extends StatelessWidget {
  const PerformancePanel({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<FpsSnapshot>(
      stream: BlackBox.instance.fpsMonitor.stream,
      initialData: BlackBox.instance.fpsMonitor.current,
      builder: (context, snapshot) {
        final snap = snapshot.data ?? BlackBox.instance.fpsMonitor.current;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── FPS headline metrics ─────────────────────────────────
              Row(
                children: [
                  _FpsGauge(fps: snap.fps),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      children: [
                        _MetricCard(
                          label: 'Avg frame',
                          value: '${snap.avgFrameMs.toStringAsFixed(1)}ms',
                          color: snap.isJanky
                              ? BlackBoxColors.warning
                              : BlackBoxColors.success,
                        ),
                        const SizedBox(height: 8),
                        _MetricCard(
                          label: 'Worst frame',
                          value: '${snap.worstFrameMs.toStringAsFixed(1)}ms',
                          color: snap.worstFrameMs > snap.budgetMs
                              ? BlackBoxColors.error
                              : BlackBoxColors.success,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // ── Frame budget bar ─────────────────────────────────────
              _FrameBudgetBar(snap: snap),
              const SizedBox(height: 16),
              if (snap.totalAvgMs > 0) ...[
                _FrameTimingBreakdown(snap: snap),
                const SizedBox(height: 16),
              ],
              // ── Rolling FPS graph ────────────────────────────────────
              const _SectionTitle('Rolling frame durations (60 frames)'),
              const SizedBox(height: 8),
              SizedBox(
                height: 120,
                child:
                    _FpsGraph(samples: snap.samples, budgetMs: snap.budgetMs),
              ),
              const SizedBox(height: 12),
              // ── Jank summary ─────────────────────────────────────────
              _JankSummary(snap: snap),
              const SizedBox(height: 16),
              // ── Session summary ────────────────────────────────────
              if (snap.totalFrames > 0) ...[
                _SessionSummaryCard(snap: snap),
                const SizedBox(height: 16),
              ],
              ValueListenableBuilder<bool>(
                valueListenable: BlackBox.instance.captureStateListenable,
                builder: (context, capturing, _) =>
                    _CaptureSummaryCard(capturing: capturing),
              ),
              const SizedBox(height: 16),
              // ── Memory usage ──────────────────────────────────────────
              const _MemoryUsageCard(),
            ],
          ),
        );
      },
    );
  }
}

class _FrameTimingBreakdown extends StatelessWidget {
  const _FrameTimingBreakdown({required this.snap});

  final FpsSnapshot snap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _TimingValue(label: 'UI', value: snap.buildAvgMs),
          _TimingValue(label: 'Raster', value: snap.rasterAvgMs),
          _TimingValue(label: 'Total', value: snap.totalAvgMs),
        ],
      ),
    );
  }
}

class _TimingValue extends StatelessWidget {
  const _TimingValue({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 9, color: Colors.white38),
          ),
          const SizedBox(height: 2),
          Text(
            '${value.toStringAsFixed(1)}ms',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _MetricCard extends StatelessWidget {
  const _MetricCard(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 9, color: Colors.white38)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

/// Animated radial FPS gauge using CustomPaint.
class _FpsGauge extends StatelessWidget {
  const _FpsGauge({required this.fps});
  final double fps;

  @override
  Widget build(BuildContext context) {
    final color = BlackBoxColors.fpsColor(fps);
    return SizedBox(
      width: 90,
      height: 90,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: fps.clamp(0, 120)),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (context, animatedFps, _) {
          return CustomPaint(
            painter: _FpsGaugePainter(
              fps: animatedFps,
              color: color,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    animatedFps.round().toString(),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  const Text(
                    'FPS',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: Colors.white38,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FpsGaugePainter extends CustomPainter {
  const _FpsGaugePainter({required this.fps, required this.color});
  final double fps;
  final Color color;

  static const double _maxFps = 120;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - 6;

    // Background arc (track)
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    const startAngle = 2.3562; // 135 degrees in radians
    const sweepTotal = 4.7124; // 270 degrees in radians

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepTotal,
      false,
      trackPaint,
    );

    // Foreground arc (value)
    final sweepFraction = (fps / _maxFps).clamp(0.0, 1.0);
    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepTotal * sweepFraction,
      false,
      valuePaint,
    );

    // Glow effect (very subtle, only on the value arc)
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepTotal * sweepFraction,
      false,
      glowPaint,
    );
  }

  @override
  bool shouldRepaint(_FpsGaugePainter old) =>
      old.fps != fps || old.color != color;
}

class _FrameBudgetBar extends StatelessWidget {
  const _FrameBudgetBar({required this.snap});
  final FpsSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final budget = snap.budgetMs > 0 ? snap.budgetMs : 16.67;
    final pct = (snap.avgFrameMs / budget).clamp(0.0, 2.0);
    final targetFps = (1000 / budget).round();
    final color = BlackBoxColors.fpsColor(snap.fps);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
            'Frame budget usage (${budget.toStringAsFixed(2)}ms at ${targetFps}fps)'),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (pct / 2).clamp(0, 1),
            minHeight: 8,
            backgroundColor: Colors.white10,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${(pct * 100).toStringAsFixed(0)}% of frame budget used',
          style: const TextStyle(fontSize: 10, color: Colors.white38),
        ),
      ],
    );
  }
}

class _FpsGraph extends StatelessWidget {
  const _FpsGraph({required this.samples, required this.budgetMs});
  final List<double> samples;
  final double budgetMs;

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) {
      return const Center(
        child: Text('Collecting frames…',
            style: TextStyle(fontSize: 11, color: Colors.white38)),
      );
    }
    return CustomPaint(
      painter: _FpsGraphPainter(samples: samples, budgetMs: budgetMs),
      size: Size.infinite,
    );
  }
}

class _FpsGraphPainter extends CustomPainter {
  const _FpsGraphPainter({required this.samples, required this.budgetMs});
  final List<double> samples;
  final double budgetMs;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    final sampleMax = samples.reduce((a, b) => a > b ? a : b);
    final budget = budgetMs > 0 ? budgetMs : 16.67;
    final maxMs = (sampleMax <= 0.0 ? budget : sampleMax).clamp(1.0, 100.0);

    // Budget line
    final budgetY = size.height * (1 - (budget / maxMs).clamp(0.0, 1.0));
    canvas.drawLine(
      Offset(0, budgetY),
      Offset(size.width, budgetY),
      Paint()
        ..color = Colors.orange.withValues(alpha: 0.4)
        ..strokeWidth = 0.5
        ..style = PaintingStyle.stroke,
    );

    // Bar graph
    final barW = (size.width / samples.length) - 1;
    for (var i = 0; i < samples.length; i++) {
      final ms = samples[i].clamp(0.0, maxMs);
      final barH = size.height * (ms / maxMs);
      final x = i * (barW + 1);
      final color =
          ms > budget ? const Color(0xFFE24B4A) : const Color(0xFF1D9E75);
      final rect = Rect.fromLTWH(x, size.height - barH, barW, barH);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              color.withValues(alpha: 0.2),
              color.withValues(alpha: 0.9),
            ],
          ).createShader(rect),
      );
      // Glow
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()
          ..color = color.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
  }

  @override
  bool shouldRepaint(_FpsGraphPainter old) =>
      !listEquals(old.samples, samples) || old.budgetMs != budgetMs;
}

class _JankSummary extends StatelessWidget {
  const _JankSummary({required this.snap});
  final FpsSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final janks = snap.jankyFrameCount;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            janks == 0
                ? Icons.check_circle_outline
                : Icons.warning_amber_outlined,
            size: 16,
            color: janks == 0 ? BlackBoxColors.success : BlackBoxColors.warning,
          ),
          const SizedBox(width: 8),
          Text(
            janks == 0
                ? 'No jank detected in last ${snap.samples.length} frames'
                : '$janks janky frame(s) in last ${snap.samples.length} frames',
            style: const TextStyle(fontSize: 11, color: Colors.white60),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontSize: 10,
            color: Colors.white38,
            fontWeight: FontWeight.w600,
            letterSpacing: .5));
  }
}

// ponytail: reuses _MetricCard and _SectionTitle, no new state
class _SessionSummaryCard extends StatelessWidget {
  const _SessionSummaryCard({required this.snap});
  final FpsSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final jankPct = snap.totalFrames > 0
        ? (snap.totalJankFrames / snap.totalFrames * 100)
        : 0.0;
    final mins = snap.sessionDuration.inMinutes;
    final secs = snap.sessionDuration.inSeconds % 60;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Session summary'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Total frames',
                value: '${snap.totalFrames}',
                color: Colors.white54,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                label: 'Jank %',
                value: '${jankPct.toStringAsFixed(1)}%',
                color: jankPct > 5
                    ? BlackBoxColors.error
                    : jankPct > 1
                        ? BlackBoxColors.warning
                        : BlackBoxColors.success,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'p95 frame',
                value: '${snap.sessionP95Ms.toStringAsFixed(1)}ms',
                color: snap.sessionP95Ms > snap.budgetMs
                    ? BlackBoxColors.error
                    : BlackBoxColors.success,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                label: 'Session',
                value: '${mins}m ${secs}s',
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Capture footprint
// ─────────────────────────────────────────────────────────────────────────────

class _CaptureSummaryCard extends StatelessWidget {
  const _CaptureSummaryCard({required this.capturing});

  final bool capturing;

  @override
  Widget build(BuildContext context) {
    final blackBox = BlackBox.instance;
    final entryCount = blackBox.networkStore.entries.length +
        blackBox.logStore.entries.length +
        blackBox.socketStore.events.length +
        blackBox.crashStore.entries.length +
        blackBox.navigationStore.history.length +
        blackBox.journeyStore.events.length +
        blackBox.rebuildStore.counts.length;
    final retainedBytes = blackBox.networkStore.approximateRetainedBytes +
        blackBox.logStore.approximateRetainedBytes +
        blackBox.socketStore.approximateRetainedBytes +
        blackBox.crashStore.approximateRetainedBytes +
        blackBox.navigationStore.approximateRetainedBytes +
        blackBox.journeyStore.approximateRetainedBytes +
        blackBox.rebuildStore.approximateRetainedBytes;
    final dropped = blackBox.networkStore.droppedEntryCount +
        blackBox.logStore.droppedEntryCount +
        blackBox.socketStore.droppedEntryCount +
        blackBox.crashStore.droppedEntryCount +
        blackBox.navigationStore.droppedEntryCount +
        blackBox.journeyStore.droppedEntryCount +
        blackBox.rebuildStore.droppedEntryCount +
        FirebaseStreamer.instance.droppedEventCount;
    final truncated = blackBox.networkStore.truncatedPayloadCount +
        blackBox.logStore.truncatedPayloadCount +
        blackBox.socketStore.truncatedPayloadCount +
        blackBox.crashStore.truncatedPayloadCount +
        blackBox.navigationStore.truncatedPayloadCount +
        blackBox.journeyStore.truncatedPayloadCount +
        FirebaseStreamer.instance.truncatedEventCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Capture footprint'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Status',
                value: capturing ? 'Recording' : 'Paused',
                color:
                    capturing ? BlackBoxColors.success : BlackBoxColors.warning,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                label: 'Entries',
                value: '$entryCount',
                color: Colors.white70,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Approx. retained',
                value: _formatCaptureBytes(retainedBytes),
                color: Colors.white70,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                label: 'Dropped / trimmed',
                value: '$dropped / $truncated',
                color: dropped + truncated > 0
                    ? BlackBoxColors.warning
                    : Colors.white54,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _formatCaptureBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

// ─────────────────────────────────────────────────────────────────────────────
// Memory usage card
// ─────────────────────────────────────────────────────────────────────────────

class _MemoryUsageCard extends StatefulWidget {
  const _MemoryUsageCard();

  @override
  State<_MemoryUsageCard> createState() => _MemoryUsageCardState();
}

class _MemoryUsageCardState extends State<_MemoryUsageCard> {
  int _currentRss = 0;
  int _peakRss = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    try {
      // ProcessInfo is dart:io — only available on native platforms.
      // ignore: avoid_dynamic_calls
      final currentRss = _getRss();
      final maxRss = _getMaxRss();
      if ((currentRss > 0 || maxRss > 0) && mounted) {
        setState(() {
          _currentRss = currentRss;
          _peakRss = maxRss;
        });
      }
    } catch (_) {
      // ProcessInfo may not be available on web.
    }
  }

  static int _getRss() {
    try {
      if (kIsWeb) return 0;
      return mem.getCurrentRss();
    } catch (_) {
      return 0;
    }
  }

  static int _getMaxRss() {
    try {
      if (kIsWeb) return 0;
      return mem.getMaxRss();
    } catch (_) {
      return 0;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final baseline = BlackBox.instance.captureBaselineRss;
    final delta = baseline > 0 ? _currentRss - baseline : 0;
    const barColor = Colors.white54;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SectionTitle('Memory usage'),
            const Spacer(),
            GestureDetector(
              onTap: _refresh,
              child: const Icon(Icons.refresh, size: 14, color: Colors.white38),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: barColor.withValues(alpha: 0.3), width: 0.5),
            boxShadow: [
              BoxShadow(
                color: barColor.withValues(alpha: 0.1),
                blurRadius: 10,
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _MemoryStat(
                    label: 'RSS',
                    value: _formatBytes(_currentRss),
                    icon: Icons.memory,
                    color: barColor,
                  ),
                  _MemoryStat(
                    label: 'Peak RSS',
                    value: _formatBytes(_peakRss),
                    icon: Icons.storage,
                    color: Colors.white54,
                  ),
                  _MemoryStat(
                    label: 'Session change',
                    value: baseline == 0
                        ? 'Unavailable'
                        : '${delta >= 0 ? '+' : '−'}${_formatBytes(delta.abs())}',
                    icon: Icons.swap_horiz,
                    color: Colors.white38,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Process memory; session change is not BlackBox-only usage.',
                style: TextStyle(fontSize: 9, color: Colors.white38),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MemoryStat extends StatelessWidget {
  const _MemoryStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 8, color: Colors.white38)),
      ],
    );
  }
}
