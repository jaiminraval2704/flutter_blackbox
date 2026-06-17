import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/performance/fps_monitor.dart';
import '../../core/performance/memory_info.dart' as mem;
import '../../blackbox.dart';
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
                          color: snap.worstFrameMs > FpsSnapshot.budgetMs
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
              // ── Rolling FPS graph ────────────────────────────────────
              const _SectionTitle('Rolling frame durations (60 frames)'),
              const SizedBox(height: 8),
              SizedBox(
                height: 120,
                child: _FpsGraph(samples: snap.samples),
              ),
              const SizedBox(height: 12),
              // ── Jank summary ─────────────────────────────────────────
              _JankSummary(snap: snap),
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
    final pct = (snap.avgFrameMs / FpsSnapshot.budgetMs).clamp(0.0, 2.0);
    final color = BlackBoxColors.fpsColor(snap.fps);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Frame budget usage (16.67ms at 60fps)'),
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
  const _FpsGraph({required this.samples});
  final List<double> samples;

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) {
      return const Center(
        child: Text('Collecting frames…',
            style: TextStyle(fontSize: 11, color: Colors.white38)),
      );
    }
    return CustomPaint(
      painter: _FpsGraphPainter(samples: samples),
      size: Size.infinite,
    );
  }
}

class _FpsGraphPainter extends CustomPainter {
  const _FpsGraphPainter({required this.samples});
  final List<double> samples;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    final maxMs = samples.reduce((a, b) => a > b ? a : b).clamp(0.0, 100.0);
    const budget = FpsSnapshot.budgetMs;

    // Budget line
    final budgetY = size.height * (1 - (budget / maxMs).clamp(0, 1));
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
  bool shouldRepaint(_FpsGraphPainter old) => !listEquals(old.samples, samples);
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
  int _heapUsed = 0;
  int _heapCapacity = 0;
  int _externalUsage = 0;

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
      if (currentRss > 0 || maxRss > 0) {
        setState(() {
          _currentRss = currentRss;
          _heapCapacity = maxRss;
          _heapUsed = currentRss;
          _externalUsage = (maxRss - currentRss).abs();
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
    final usedMb = _heapUsed / (1024 * 1024);
    final capacityMb = _heapCapacity / (1024 * 1024);
    final usageRatio =
        _heapCapacity > 0 ? (_heapUsed / _heapCapacity).clamp(0.0, 1.0) : 0.0;

    final barColor = usageRatio < 0.6
        ? BlackBoxColors.success
        : usageRatio < 0.85
            ? BlackBoxColors.warning
            : BlackBoxColors.error;

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
              // Usage bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: usageRatio,
                  minHeight: 6,
                  backgroundColor: Colors.white10,
                  valueColor: AlwaysStoppedAnimation<Color>(barColor),
                ),
              ),
              const SizedBox(height: 10),
              // Stats row
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
                    label: 'Max RSS',
                    value: _formatBytes(_heapCapacity),
                    icon: Icons.storage,
                    color: Colors.white54,
                  ),
                  _MemoryStat(
                    label: 'Delta',
                    value: _formatBytes(_externalUsage),
                    icon: Icons.swap_horiz,
                    color: Colors.white38,
                  ),
                ],
              ),
              if (capacityMb > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '${usedMb.toStringAsFixed(1)} MB / ${capacityMb.toStringAsFixed(1)} MB  •  ${(usageRatio * 100).toStringAsFixed(0)}% used',
                  style: TextStyle(fontSize: 9, color: barColor),
                ),
              ],
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
