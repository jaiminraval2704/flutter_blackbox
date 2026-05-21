import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/log/log_entry.dart';
import '../../core/log/log_level.dart';
import '../../blackbox.dart';
import '../widgets/blackbox_colors.dart';
import '../widgets/empty_state.dart';

class LogPanel extends StatefulWidget {
  const LogPanel({super.key});

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  LogLevel? _filterLevel;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Toolbar ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: PanelSearchBar(
                  hint: 'Search logs…',
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(width: 8),
              _LevelFilterChips(
                selected: _filterLevel,
                onSelected: (l) =>
                    setState(() => _filterLevel = _filterLevel == l ? null : l),
              ),
              const SizedBox(width: 8),
              _ClearButton(onTap: () => BlackBox.instance.logStore.clear()),
            ],
          ),
        ),
        // ── List ────────────────────────────────────────────────────────
        Expanded(
          child: StreamBuilder<List<LogEntry>>(
            stream: BlackBox.instance.logStore.stream,
            initialData: BlackBox.instance.logStore.entries,
            builder: (context, snapshot) {
              final all = snapshot.data ?? [];
              final filtered = _filterLevel != null || _query.isNotEmpty
                  ? BlackBox.instance.logStore
                      .filter(level: _filterLevel, query: _query)
                  : all;

              final filteredList = filtered.toList(growable: false);
              if (all.isEmpty) {
                return const EmptyState(
                    icon: Icons.article_outlined,
                    label: 'No logs recorded yet',
                    emoji: '📝');
              }
              if (filteredList.isEmpty) {
                return const EmptyState(
                    icon: Icons.search_off,
                    label: 'No matches found',
                    emoji: '🔍');
              }

              return ListView.builder(
                reverse: true,
                itemExtent: 70, // Performance optimization for large lists
                itemCount: filteredList.length,
                itemBuilder: (ctx, i) =>
                    _LogTile(entry: filteredList[filteredList.length - 1 - i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});
  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = BlackBoxColors.forLevel(entry.level);
    return InkWell(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: entry.toString()));
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
              content: Text('Copied to clipboard'),
              duration: Duration(seconds: 1)),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                entry.level.label,
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (entry.tag != null)
                    Text(
                      '[${entry.tag}]',
                      style: TextStyle(
                          fontSize: 9,
                          color: color.withValues(alpha: 0.7),
                          fontFamily: 'monospace'),
                    ),
                  Text(
                    _truncate(entry.message),
                    style: const TextStyle(
                        fontSize: 11, color: Colors.white70, height: 1.4),
                  ),
                  if (entry.data != null)
                    Text(
                      _truncate(entry.data.toString()),
                      style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white38,
                          fontFamily: 'monospace'),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _formatTime(entry.timestamp),
              style: const TextStyle(fontSize: 9, color: Colors.white24),
            ),
          ],
        ),
      ),
    );
  }

  String _truncate(String str, [int maxLen = 3000]) {
    if (str.length <= maxLen) return str;
    return '${str.substring(0, maxLen)}...\n[TRUNCATED to preserve performance]';
  }

  String _formatTime(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';
}

// ─────────────────────────────────────────────────────────────────────────────

class _LevelFilterChips extends StatelessWidget {
  const _LevelFilterChips({this.selected, required this.onSelected});
  final LogLevel? selected;
  final void Function(LogLevel) onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [LogLevel.error, LogLevel.warning, LogLevel.info].map((l) {
        final isActive = selected == l;
        final color = BlackBoxColors.forLevel(l);
        return GestureDetector(
          onTap: () => onSelected(l),
          child: Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color:
                  isActive ? color.withValues(alpha: 0.2) : Colors.transparent,
              border: Border.all(
                  color: isActive ? color : Colors.white24, width: 0.5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(l.label,
                style: TextStyle(
                    fontSize: 9, color: isActive ? color : Colors.white38)),
          ),
        );
      }).toList(),
    );
  }
}

class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: const Icon(Icons.delete_outline, color: Colors.white38, size: 18),
    );
  }
}
