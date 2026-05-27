import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../blackbox.dart';
import '../widgets/blackbox_colors.dart';
import '../widgets/empty_state.dart';

class RebuildPanel extends StatefulWidget {
  const RebuildPanel({super.key});

  @override
  State<RebuildPanel> createState() => _RebuildPanelState();
}

class _RebuildPanelState extends State<RebuildPanel> {
  Map<String, int> _counts = const {};
  StreamSubscription<Map<String, int>>? _sub;

  @override
  void initState() {
    super.initState();
    _counts = BlackBox.instance.rebuildStore.counts;
    _sub = BlackBox.instance.rebuildStore.stream.listen((counts) {
      if (mounted) setState(() => _counts = counts);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final totalRebuilds = entries.fold<int>(0, (sum, e) => sum + e.value);
    final isAutoOn = BlackBox.instance.isAutoRebuildTrackingEnabled;

    return Column(
      children: [
        // ── Header stats ──────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              _StatChip(
                label: 'Widgets',
                value: '${entries.length}',
                color: Colors.white54,
              ),
              const SizedBox(width: 8),
              _StatChip(
                label: 'Total rebuilds',
                value: '$totalRebuilds',
                color: totalRebuilds > 100
                    ? BlackBoxColors.warning
                    : BlackBoxColors.success,
              ),
              const Spacer(),
              // ── Auto-track toggle ───────────────────────────────
              GestureDetector(
                onTap: () {
                  setState(() {
                    if (isAutoOn) {
                      BlackBox.stopRebuildTracking();
                    } else {
                      BlackBox.startRebuildTracking();
                    }
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isAutoOn
                        ? BlackBoxColors.success.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isAutoOn ? BlackBoxColors.success : Colors.white10,
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isAutoOn ? Icons.visibility : Icons.visibility_off,
                        size: 12,
                        color:
                            isAutoOn ? BlackBoxColors.success : Colors.white38,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isAutoOn ? 'AUTO ON' : 'AUTO OFF',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: isAutoOn
                              ? BlackBoxColors.success
                              : Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => BlackBox.instance.rebuildStore.reset(),
                child: const Icon(Icons.delete_outline,
                    color: Colors.white38, size: 18),
              ),
            ],
          ),
        ),

        // ── Info banner ───────────────────────────────────────────
        if (entries.isEmpty && !isAutoOn)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF6C63FF).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFF6C63FF).withValues(alpha: 0.2),
                    width: 0.5),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How to track rebuilds:',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.white70,
                          fontWeight: FontWeight.w700)),
                  SizedBox(height: 4),
                  Text(
                    '1. Tap "AUTO OFF" → auto-tracks ALL widgets\n'
                    '2. Or wrap specific widgets:\n'
                    '   RebuildTracker(label: "MyWidget", child: ...)',
                    style: TextStyle(
                        fontSize: 9,
                        color: Colors.white38,
                        fontFamily: 'monospace',
                        height: 1.5),
                  ),
                ],
              ),
            ),
          ),

        // ── Widget list ───────────────────────────────────────────
        Expanded(
          child: entries.isEmpty
              ? const EmptyState(
                  icon: Icons.refresh,
                  label: 'No rebuild data yet',
                  emoji: '♻️')
              : RefreshIndicator(
                  color: const Color(0xFF6C63FF),
                  backgroundColor: const Color(0xFF1A1A2E),
                  onRefresh: () async {
                    HapticFeedback.lightImpact();
                    BlackBox.instance.rebuildStore.reset();
                    await Future<void>.delayed(
                        const Duration(milliseconds: 300));
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    itemCount: entries.length,
                    itemExtent: 54, // Fixed height for O(1) layout calculation
                    itemBuilder: (ctx, i) {
                      final entry = entries[i];
                      final maxCount = entries.first.value;
                      return _RebuildTile(
                        widgetName: entry.key,
                        count: entry.value,
                        maxCount: maxCount,
                        rank: i + 1,
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _RebuildTile extends StatelessWidget {
  const _RebuildTile({
    required this.widgetName,
    required this.count,
    required this.maxCount,
    required this.rank,
  });

  final String widgetName;
  final int count;
  final int maxCount;
  final int rank;

  Color get _heatColor {
    if (count > 50) return BlackBoxColors.error;
    if (count > 20) return BlackBoxColors.warning;
    return BlackBoxColors.success;
  }

  @override
  Widget build(BuildContext context) {
    final fraction = maxCount > 0 ? (count / maxCount).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _heatColor.withValues(alpha: 0.2),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Rank badge
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: rank <= 3
                      ? _heatColor.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: Text(
                    '#$rank',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: rank <= 3 ? _heatColor : Colors.white38,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widgetName,
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                      fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _heatColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _heatColor,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 3,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(_heatColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(fontSize: 9, color: Colors.white38)),
        ],
      ),
    );
  }
}
