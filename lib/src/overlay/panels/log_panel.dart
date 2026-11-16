import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/log/log_entry.dart';
import '../../core/log/log_level.dart';
import '../../blackbox.dart';
import '../widgets/blackbox_colors.dart';
import '../widgets/blackbox_toast.dart';
import '../widgets/empty_state.dart';
import '../widgets/staggered_list_item.dart';

// ponytail: plain data class, no logic
class _GroupedLog {
  const _GroupedLog(
      {required this.entry, required this.count, required this.ids});
  final LogEntry entry;
  final int count;
  final List<String> ids;
}

// ponytail: single O(N) pass, no allocations beyond result list
List<_GroupedLog> _groupConsecutive(List<LogEntry> logs) {
  if (logs.isEmpty) return const [];
  final groups = <_GroupedLog>[];
  var current = logs.first;
  var count = 1;
  var ids = [current.id];

  for (var i = 1; i < logs.length; i++) {
    final entry = logs[i];
    if (entry.message == current.message && entry.level == current.level) {
      count++;
      ids.add(entry.id);
    } else {
      groups.add(_GroupedLog(
          entry: current, count: count, ids: List.unmodifiable(ids)));
      current = entry;
      count = 1;
      ids = [current.id];
    }
  }
  groups.add(
      _GroupedLog(entry: current, count: count, ids: List.unmodifiable(ids)));
  return groups;
}

class LogPanel extends StatefulWidget {
  const LogPanel({super.key});

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  LogLevel? _filterLevel;
  final ValueNotifier<String> _queryNotifier = ValueNotifier<String>('');
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _showScrollToTop = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _queryNotifier.dispose();
    _showScrollToTop.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final show = _scrollController.offset > 300;
    if (show != _showScrollToTop.value) {
      _showScrollToTop.value = show;
    }
  }

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
                  onChanged: (v) => _queryNotifier.value = v,
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
          child: ValueListenableBuilder<String>(
            valueListenable: _queryNotifier,
            builder: (context, query, _) => StreamBuilder<List<LogEntry>>(
              stream: BlackBox.instance.logStore.stream,
              initialData: BlackBox.instance.logStore.entries,
              builder: (context, snapshot) {
                final all = snapshot.data ?? [];
                final filtered = _filterLevel != null || query.isNotEmpty
                    ? BlackBox.instance.logStore
                        .filter(level: _filterLevel, query: query)
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

                final grouped = _groupConsecutive(filteredList);

                return Stack(
                  children: [
                    RefreshIndicator(
                      color: const Color(0xFF6C63FF),
                      backgroundColor: const Color(0xFF1A1A2E),
                      onRefresh: () async {
                        HapticFeedback.lightImpact();
                        await Future<void>.delayed(
                            const Duration(milliseconds: 300));
                      },
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: grouped.length,
                        itemBuilder: (ctx, i) {
                          final group = grouped[grouped.length - 1 - i];
                          final entry = group.entry;
                          return Dismissible(
                            key: ValueKey(
                                '${entry.timestamp.microsecondsSinceEpoch}_$i'),
                            direction: DismissDirection.startToEnd,
                            onDismissed: (_) {
                              HapticFeedback.mediumImpact();
                              final idsToRemove = group.ids.toSet();
                              BlackBox.instance.logStore.removeWhere(
                                  (e) => idsToRemove.contains(e.id));
                            },
                            background: Container(
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 20),
                              color: const Color(0xFFEF4444)
                                  .withValues(alpha: 0.2),
                              child: const Icon(Icons.delete_outline,
                                  color: Color(0xFFEF4444), size: 20),
                            ),
                            child: StaggeredListItem(
                              index: i,
                              child: _LogTile(group: group),
                            ),
                          );
                        },
                      ),
                    ),
                    // ── Scroll-to-top FAB ──
                    ValueListenableBuilder<bool>(
                      valueListenable: _showScrollToTop,
                      builder: (context, show, child) {
                        if (!show) return const SizedBox.shrink();
                        return child!;
                      },
                      child: Positioned(
                        right: 12,
                        bottom: 12,
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _scrollController.animateTo(0,
                                duration: const Duration(milliseconds: 400),
                                curve: Curves.easeOutCubic);
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFF6C63FF)
                                  .withValues(alpha: 0.85),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6C63FF)
                                      .withValues(alpha: 0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.arrow_upward,
                                color: Colors.white, size: 18),
                          ),
                        ),
                      ),
                    ),
                  ],
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

class _LogTile extends StatelessWidget {
  const _LogTile({required this.group});
  final _GroupedLog group;

  @override
  Widget build(BuildContext context) {
    final entry = group.entry;
    final color = BlackBoxColors.forLevel(entry.level);
    return InkWell(
      onTap: () => _showLogDetails(context, color),
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: entry.toString()));
        HapticFeedback.lightImpact();
        BlackBoxToast.show(context, 'Copied to clipboard');
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          border: Border(
            left: BorderSide(color: color, width: 3),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: color.withValues(alpha: 0.4), width: 0.5),
                  boxShadow: [
                    BoxShadow(
                        color: color.withValues(alpha: 0.2), blurRadius: 4),
                  ],
                ),
                child: Center(
                  child: Text(
                    entry.level.label,
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: color,
                        letterSpacing: 0.5,
                        fontFamily: 'monospace'),
                  ),
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
                    GestureDetector(
                      onDoubleTap: () {
                        Clipboard.setData(ClipboardData(text: entry.message));
                        HapticFeedback.selectionClick();
                        BlackBoxToast.show(context, 'Copied log message');
                      },
                      child: Text(
                        _truncate(entry.message),
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white70, height: 1.4),
                      ),
                    ),
                    if (entry.data != null)
                      GestureDetector(
                        onDoubleTap: () {
                          Clipboard.setData(
                              ClipboardData(text: entry.data.toString()));
                          HapticFeedback.selectionClick();
                          BlackBoxToast.show(context, 'Copied log data');
                        },
                        child: Text(
                          _truncate(entry.data.toString()),
                          style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white38,
                              fontFamily: 'monospace'),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatTime(entry.timestamp),
                    style: const TextStyle(
                        fontSize: 9,
                        color: Colors.white24,
                        fontFamily: 'monospace'),
                  ),
                  if (group.count > 1)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '×${group.count}',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _truncate(String str, [int maxLen = 500]) {
    if (str.length <= maxLen) return str;
    return '${str.substring(0, maxLen)}…';
  }

  String _formatTime(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  static String _truncateDetail(String str, [int maxLen = 5000]) {
    if (str.length <= maxLen) return str;
    return '${str.substring(0, maxLen)}\n\n… [Truncated – ${str.length - maxLen} chars hidden]';
  }

  void _showLogDetails(BuildContext context, Color color) {
    final entry = group.entry;
    // Pre-compute all strings BEFORE opening the sheet to avoid
    // expensive toString() calls during the build/animation frame.
    final String messageText = _truncateDetail(entry.message);
    final String? dataText = entry.data != null
        ? _truncateDetail(
            entry.data is Map && (entry.data as Map).containsKey('details')
                ? (entry.data as Map)['details'].toString()
                : entry.data.toString(),
          )
        : null;
    final String? errorText =
        entry.error != null ? _truncateDetail(entry.error.toString()) : null;
    final String? stackText = entry.stackTrace != null
        ? _truncateDetail(entry.stackTrace.toString())
        : null;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final height = MediaQuery.of(ctx).size.height * 0.65;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: height),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        entry.level.label.toUpperCase(),
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, color: Colors.white70),
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: entry.toString()));
                        HapticFeedback.lightImpact();
                        BlackBoxToast.show(ctx, 'Copied details');
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(color: Colors.white10),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),
                        const Text('Message',
                            style:
                                TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(
                          messageText,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                        ),
                        if (dataText != null) ...[
                          const SizedBox(height: 16),
                          const Text('Data / Context',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                          const SizedBox(height: 4),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              dataText,
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontFamily: 'monospace',
                                  fontSize: 12),
                            ),
                          ),
                        ],
                        if (errorText != null) ...[
                          const SizedBox(height: 16),
                          const Text('Error',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(
                            errorText,
                            style: const TextStyle(
                                color: Colors.redAccent, fontSize: 13),
                          ),
                        ],
                        if (stackText != null) ...[
                          const SizedBox(height: 16),
                          const Text('Stack Trace',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                          const SizedBox(height: 4),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              stackText,
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontFamily: 'monospace',
                                  fontSize: 11),
                            ),
                          ),
                        ],
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
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
              boxShadow: isActive
                  ? [
                      BoxShadow(
                          color: color.withValues(alpha: 0.3), blurRadius: 6),
                    ]
                  : null,
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
