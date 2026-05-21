import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/socket/socket_event.dart';
import '../../blackbox.dart';
import '../widgets/blackbox_colors.dart';
import '../widgets/empty_state.dart';

class SocketPanel extends StatefulWidget {
  const SocketPanel({super.key});

  @override
  State<SocketPanel> createState() => _SocketPanelState();
}

class _SocketPanelState extends State<SocketPanel> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: PanelSearchBar(
                  hint: 'Filter by event name...',
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => BlackBox.instance.socketStore.clear(),
                child: const Icon(Icons.delete_outline,
                    color: Colors.white38, size: 18),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<SocketEvent>>(
            stream: BlackBox.instance.socketStore.stream,
            initialData: BlackBox.instance.socketStore.events,
            builder: (context, snapshot) {
              var events = snapshot.data ?? [];
              if (_query.isNotEmpty) {
                final q = _query.toLowerCase();
                events = events
                    .where((e) => e.eventName.toLowerCase().contains(q))
                    .toList();
              }
              if (events.isEmpty) {
                return const EmptyState(
                    icon: Icons.power, label: 'No socket events yet');
              }

              return ListView.builder(
                reverse: false,
                itemCount: events.length,
                itemBuilder: (ctx, i) =>
                    _SocketTile(event: events[events.length - 1 - i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SocketTile extends StatefulWidget {
  const _SocketTile({required this.event});
  final SocketEvent event;

  @override
  State<_SocketTile> createState() => _SocketTileState();
}

class _SocketTileState extends State<_SocketTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final isOutgoing = event.direction == SocketDirection.outgoing;

    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              children: [
                _DirectionBadge(direction: event.direction),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    event.eventName,
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  isOutgoing ? 'EMIT' : 'ON',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isOutgoing
                        ? BlackBoxColors.warning
                        : BlackBoxColors.success,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white24,
                  size: 16,
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? _SocketDetail(event: event)
                : const SizedBox(width: double.infinity),
          ),
          const Divider(color: Colors.white10, height: 1),
        ],
      ),
    );
  }
}

class _SocketDetail extends StatelessWidget {
  const _SocketDetail({required this.event});
  final SocketEvent event;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withValues(alpha: 0.03),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (event.data != null)
            _Section(
                title: 'Data', content: _truncate(_formatJson(event.data))),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.copy, size: 12),
                  label:
                      const Text('Copy Event', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.white38,
                      padding: EdgeInsets.zero),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: event.eventName)),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.copy_all, size: 12),
                  label:
                      const Text('Copy Data', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.white38,
                      padding: EdgeInsets.zero),
                  onPressed: () {
                    final fullData = '''Event: ${event.eventName}
Direction: ${event.direction.name.toUpperCase()}
Timestamp: ${event.timestamp.toIso8601String()}

Data:
${event.data != null ? _formatJson(event.data) : 'None'}''';
                    Clipboard.setData(ClipboardData(text: fullData));
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatJson(dynamic data) {
    if (data == null) return '';
    try {
      if (data is String) {
        final decoded = jsonDecode(data);
        return const JsonEncoder.withIndent('  ').convert(decoded);
      }
      return const JsonEncoder.withIndent('  ').convert(data);
    } catch (_) {
      return data.toString();
    }
  }

  String _truncate(String str, [int maxLen = 3000]) {
    if (str.length <= maxLen) return str;
    return '${str.substring(0, maxLen)}...\n\n[TRUNCATED to preserve performance]';
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.content});
  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 9,
                  color: Colors.white38,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .5)),
          const SizedBox(height: 2),
          Text(content,
              style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white60,
                  fontFamily: 'monospace',
                  height: 1.4)),
        ],
      ),
    );
  }
}

class _DirectionBadge extends StatelessWidget {
  const _DirectionBadge({required this.direction});
  final SocketDirection direction;

  Color get _color =>
      direction == SocketDirection.incoming ? Colors.green : Colors.orange;

  IconData get _icon => direction == SocketDirection.incoming
      ? Icons.arrow_downward
      : Icons.arrow_upward;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(_icon, size: 12, color: _color),
    );
  }
}
