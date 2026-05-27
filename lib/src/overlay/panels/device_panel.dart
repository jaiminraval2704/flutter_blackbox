import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/blackbox_theme.dart';

class DevicePanel extends StatelessWidget {
  const DevicePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final rows = _buildRows(context, mq);
    final theme = BlackBoxTheme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      children: [
        _GlassSection(
          theme: theme,
          title: 'Platform',
          icon: Icons.devices,
          rows: rows['platform']!,
        ),
        const SizedBox(height: 10),
        _GlassSection(
          theme: theme,
          title: 'Screen',
          icon: Icons.aspect_ratio,
          rows: rows['screen']!,
        ),
        const SizedBox(height: 10),
        _GlassSection(
          theme: theme,
          title: 'App',
          icon: Icons.apps,
          rows: rows['app']!,
        ),
      ],
    );
  }

  Map<String, List<MapEntry<String, String>>> _buildRows(
      BuildContext context, MediaQueryData mq) {
    final size = mq.size;
    final dpr = mq.devicePixelRatio;

    return {
      'platform': [
        MapEntry('Platform', defaultTargetPlatform.name.toUpperCase()),
        const MapEntry(
            'Mode',
            kDebugMode
                ? 'DEBUG'
                : kProfileMode
                    ? 'PROFILE'
                    : 'RELEASE'),
        if (!kIsWeb) MapEntry('OS', _osVersion()),
        const MapEntry('Web', kIsWeb ? 'Yes' : 'No'),
      ],
      'screen': [
        MapEntry('Size',
            '${size.width.toStringAsFixed(0)} × ${size.height.toStringAsFixed(0)} dp'),
        MapEntry('Physical',
            '${(size.width * dpr).toStringAsFixed(0)} × ${(size.height * dpr).toStringAsFixed(0)} px'),
        MapEntry('Pixel ratio', dpr.toStringAsFixed(2)),
        MapEntry('Text scale', mq.textScaler.scale(1).toStringAsFixed(2)),
        MapEntry('Brightness', mq.platformBrightness.name),
        MapEntry('Padding',
            'T:${mq.padding.top.toStringAsFixed(0)} B:${mq.padding.bottom.toStringAsFixed(0)}'),
      ],
      'app': [
        // MapEntry('Dart version', Platform.version.split(' ').first), // Removed dart:io dependency
        MapEntry('Debug mode', kDebugMode.toString()),
        MapEntry('Profile mode', kProfileMode.toString()),
      ],
    };
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

class _GlassSection extends StatelessWidget {
  const _GlassSection({
    required this.theme,
    required this.title,
    required this.icon,
    required this.rows,
  });

  final BlackBoxThemeData theme;
  final String title;
  final IconData icon;
  final List<MapEntry<String, String>> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardBackground.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section header ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: theme.accentColor, size: 14),
                const SizedBox(width: 8),
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.accentColor,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
          // ── Info rows ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(
              children: rows
                  .map((e) => _InfoRow(
                        label: e.key,
                        value: e.value,
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
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(fontSize: 11, color: theme.textMuted)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 11,
                    color: theme.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}
