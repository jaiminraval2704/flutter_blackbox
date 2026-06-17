import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/blackbox_theme.dart';

class DevicePanel extends StatelessWidget {
  const DevicePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final theme = BlackBoxTheme.of(context);
    final size = mq.size;
    final dpr = mq.devicePixelRatio;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      children: [
        _TelemetrySection(
          theme: theme,
          title: 'PLATFORM',
          icon: Icons.memory,
          metrics: [
            (label: 'OS', value: _osVersion()),
            (
              label: 'Platform',
              value: defaultTargetPlatform.name.toUpperCase()
            ),
            (
              label: 'Mode',
              value: kDebugMode
                  ? 'DEBUG'
                  : kProfileMode
                      ? 'PROFILE'
                      : 'RELEASE'
            ),
            (label: 'Web', value: kIsWeb ? 'YES' : 'NO'),
          ],
        ),
        const SizedBox(height: 16),
        _TelemetrySection(
          theme: theme,
          title: 'SCREEN',
          icon: Icons.monitor,
          metrics: [
            (
              label: 'Size',
              value:
                  '${size.width.toStringAsFixed(0)} × ${size.height.toStringAsFixed(0)} dp'
            ),
            (
              label: 'Physical',
              value:
                  '${(size.width * dpr).toStringAsFixed(0)} × ${(size.height * dpr).toStringAsFixed(0)} px'
            ),
            (label: 'Pixel ratio', value: '${dpr}x'),
            (
              label: 'Text scale',
              value: '${mq.textScaler.scale(1).toStringAsFixed(2)}x'
            ),
            (
              label: 'Brightness',
              value: mq.platformBrightness.name.toUpperCase()
            ),
            (
              label: 'Padding',
              value:
                  'T:${mq.padding.top.toStringAsFixed(0)} B:${mq.padding.bottom.toStringAsFixed(0)}'
            ),
          ],
        ),
        const SizedBox(height: 16),
        _TelemetrySection(
          theme: theme,
          title: 'APP',
          icon: Icons.apps,
          metrics: [
            (label: 'Debug mode', value: kDebugMode.toString().toUpperCase()),
            (
              label: 'Profile mode',
              value: kProfileMode.toString().toUpperCase()
            ),
          ],
        ),
      ],
    );
  }

  String _osVersion() {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) return 'Android';
      if (defaultTargetPlatform == TargetPlatform.iOS) return 'iOS';
      if (defaultTargetPlatform == TargetPlatform.macOS) return 'macOS';
      if (defaultTargetPlatform == TargetPlatform.windows) return 'Windows';
      if (defaultTargetPlatform == TargetPlatform.linux) return 'Linux';
      if (defaultTargetPlatform == TargetPlatform.fuchsia) return 'Fuchsia';
      return 'Unknown';
    } catch (_) {
      return 'Unknown';
    }
  }
}

class _TelemetrySection extends StatelessWidget {
  const _TelemetrySection({
    required this.theme,
    required this.title,
    required this.icon,
    required this.metrics,
  });

  final BlackBoxThemeData theme;
  final String title;
  final IconData icon;
  final List<({String label, String value})> metrics;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardBackground.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section header ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: theme.accentColor.withValues(alpha: 0.05),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Icon(icon, color: theme.accentColor, size: 14),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.accentColor,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          // ── Info rows ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              children: metrics
                  .map((m) => _InfoRow(
                        label: m.label,
                        value: m.value,
                        theme: theme,
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.theme,
  });

  final String label;
  final String value;
  final BlackBoxThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: theme.textMuted,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: theme.textSecondary,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
