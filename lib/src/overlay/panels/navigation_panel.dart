import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../blackbox.dart';
import '../../core/journey/navigation_store.dart';
import '../widgets/blackbox_theme.dart';
import '../widgets/empty_state.dart';

/// Panel displaying the live navigation stack and route history
/// with arguments.
class NavigationPanel extends StatefulWidget {
  const NavigationPanel({super.key});

  @override
  State<NavigationPanel> createState() => _NavigationPanelState();
}

class _NavigationPanelState extends State<NavigationPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  StreamSubscription<List<NavigationEntry>>? _sub;
  List<NavigationEntry> _history = const [];
  List<NavigationEntry> _stack = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _history = BlackBox.instance.navigationStore.history;
    _stack = BlackBox.instance.navigationStore.currentStack;
    _sub = BlackBox.instance.navigationStore.stream.listen((_) {
      if (mounted) {
        setState(() {
          _history = BlackBox.instance.navigationStore.history;
          _stack = BlackBox.instance.navigationStore.currentStack;
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = BlackBoxTheme.of(context);

    return Column(
      children: [
        // ── Sub-tab bar ─────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          decoration: BoxDecoration(
            color: theme.surfaceOverlay,
            borderRadius: BorderRadius.circular(8),
          ),
          child: TabBar(
            controller: _tabController,
            indicatorColor: theme.accentColor,
            labelColor: theme.textPrimary,
            unselectedLabelColor: theme.textMuted,
            labelStyle:
                const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.layers, size: 14, color: theme.textSecondary),
                    const SizedBox(width: 4),
                    Text('Stack (${_stack.length})'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history, size: 14, color: theme.textSecondary),
                    const SizedBox(width: 4),
                    Text('History (${_history.length})'),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // ── Tab content ─────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _StackView(stack: _stack),
              _HistoryView(history: _history),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live navigation stack view
// ─────────────────────────────────────────────────────────────────────────────

class _StackView extends StatelessWidget {
  const _StackView({required this.stack});
  final List<NavigationEntry> stack;

  @override
  Widget build(BuildContext context) {
    if (stack.isEmpty) {
      return const EmptyState(
        icon: Icons.route,
        label: 'No routes in stack yet',
        emoji: '🗺️',
      );
    }

    final theme = BlackBoxTheme.of(context);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      itemCount: stack.length,
      itemBuilder: (ctx, i) {
        // Show bottom of stack first, current route last
        final entry = stack[i];
        final isCurrent = i == stack.length - 1;

        return Container(
          margin: const EdgeInsets.only(bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Depth indicator (visual tree) ──
              SizedBox(
                width: 30,
                child: Column(
                  children: [
                    if (i > 0)
                      Container(
                        width: 1.5,
                        height: 8,
                        color: theme.accentColor.withValues(alpha: 0.3),
                      ),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isCurrent
                            ? theme.accentColor
                            : theme.accentColor.withValues(alpha: 0.3),
                        border: Border.all(
                          color: theme.accentColor,
                          width: 1.5,
                        ),
                      ),
                    ),
                    if (i < stack.length - 1)
                      Container(
                        width: 1.5,
                        height: 8,
                        color: theme.accentColor.withValues(alpha: 0.3),
                      ),
                  ],
                ),
              ),
              // ── Route card ──
              Expanded(
                child: _RouteCard(
                  entry: entry,
                  isCurrent: isCurrent,
                  showAction: false,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Navigation history timeline
// ─────────────────────────────────────────────────────────────────────────────

class _HistoryView extends StatelessWidget {
  const _HistoryView({required this.history});
  final List<NavigationEntry> history;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const EmptyState(
        icon: Icons.history,
        label: 'No navigation events yet',
        emoji: '🕰️',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      itemCount: history.length,
      itemBuilder: (ctx, i) {
        // Newest first
        final entry = history[history.length - 1 - i];
        return _RouteCard(
          entry: entry,
          isCurrent: false,
          showAction: true,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Route card
// ─────────────────────────────────────────────────────────────────────────────

class _RouteCard extends StatefulWidget {
  const _RouteCard({
    required this.entry,
    required this.isCurrent,
    required this.showAction,
  });

  final NavigationEntry entry;
  final bool isCurrent;
  final bool showAction;

  @override
  State<_RouteCard> createState() => _RouteCardState();
}

class _RouteCardState extends State<_RouteCard> {
  bool _argsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = BlackBoxTheme.of(context);
    final entry = widget.entry;
    final hasArgs = entry.arguments != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: widget.isCurrent
            ? theme.accentColor.withValues(alpha: 0.08)
            : theme.surfaceOverlay,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.isCurrent
              ? theme.accentColor.withValues(alpha: 0.3)
              : theme.borderColor,
          width: 0.5,
        ),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _argsExpanded = !_argsExpanded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // ── Action badge ──
                if (widget.showAction)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: _actionColor(entry.action).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      entry.action.toUpperCase(),
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: _actionColor(entry.action),
                      ),
                    ),
                  ),
                // ── Current badge ──
                if (widget.isCurrent)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: theme.accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'CURRENT',
                      style: TextStyle(
                        fontSize: 7,
                        fontWeight: FontWeight.w800,
                        color: theme.accentColor,
                      ),
                    ),
                  ),
                // ── Route name ──
                Expanded(
                  child: Text(
                    entry.routeName,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.textSecondary,
                      fontFamily: 'monospace',
                      fontWeight: widget.isCurrent
                          ? FontWeight.w700
                          : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // ── Timestamp ──
                Text(
                  _formatTime(entry.timestamp),
                  style: TextStyle(fontSize: 9, color: theme.textMuted),
                ),
              ],
            ),

            // ── Depth indicator ──
            if (widget.showAction) ...[
              const SizedBox(height: 2),
              Text(
                'depth: ${entry.stackDepth}',
                style: TextStyle(
                  fontSize: 8,
                  color: theme.textMuted,
                  fontFamily: 'monospace',
                ),
              ),
            ],

            // ── Expanded Info ──
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: !_argsExpanded
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.panelBackground,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Full Route Name:',
                              style: TextStyle(
                                fontSize: 9,
                                color: theme.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              entry.routeName,
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.textSecondary,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Text(
                                  'Arguments:',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: theme.textMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (hasArgs) ...[
                                  const Spacer(),
                                  GestureDetector(
                                    onTap: () {
                                      Clipboard.setData(ClipboardData(
                                        text: _formatArguments(entry.arguments),
                                      ));
                                    },
                                    child: Icon(Icons.copy,
                                        size: 12, color: theme.textMuted),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            if (hasArgs)
                              Text(
                                _formatArguments(entry.arguments),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: theme.textSecondary,
                                  fontFamily: 'monospace',
                                  height: 1.4,
                                ),
                              )
                            else
                              Text(
                                'No arguments provided.',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: theme.textMuted,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Color _actionColor(String action) => switch (action) {
        'push' => Colors.green,
        'pop' => Colors.orange,
        'replace' => Colors.blue,
        'remove' => Colors.red,
        _ => Colors.grey,
      };

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  String _formatArguments(Object? args) {
    if (args == null) return 'null';
    if (args is Map || args is List) {
      try {
        return const JsonEncoder.withIndent('  ').convert(args);
      } catch (_) {
        return args.toString();
      }
    }
    return args.toString();
  }
}
