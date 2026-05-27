import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../blackbox.dart';
import '../widgets/blackbox_colors.dart';
import '../widgets/blackbox_toast.dart';
import '../widgets/empty_state.dart';

/// A unified search panel that searches across Network, Logs, Storage,
/// Socket, and Crash stores simultaneously.
class SearchPanel extends StatefulWidget {
  const SearchPanel({super.key, required this.onResultTap});
  final void Function(String source) onResultTap;

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel> {
  String _query = '';
  final _controller = TextEditingController();
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    // Update _query immediately so the UI responds (border, clear button,
    // empty state). The expensive _search() runs on next build but only
    // after the debounce prevents rapid-fire rebuilds.
    setState(() => _query = value);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() {});
    });
  }

  List<_SearchResult> _search(String query) {
    if (query.isEmpty) return [];
    final q = query.toLowerCase();
    final results = <_SearchResult>[];

    // ── Search Network ──
    for (final entry in BlackBox.instance.networkStore.entries) {
      final req = entry.request;
      final res = entry.response;

      final urlMatch = req.url.toLowerCase().contains(q);
      final methodMatch = req.method.toLowerCase().contains(q);
      final bodyMatch = req.body?.toString().toLowerCase().contains(q) == true;
      final resBodyMatch =
          res?.body?.toString().toLowerCase().contains(q) == true;
      final headerMatch = req.headers.toString().toLowerCase().contains(q);

      if (urlMatch || methodMatch || bodyMatch || resBodyMatch || headerMatch) {
        final matchIn = <String>[];
        if (urlMatch) matchIn.add('URL');
        if (methodMatch) matchIn.add('method');
        if (bodyMatch) matchIn.add('request body');
        if (resBodyMatch) matchIn.add('response body');
        if (headerMatch) matchIn.add('headers');

        results.add(_SearchResult(
          source: 'Network',
          icon: Icons.wifi,
          color: Colors.blue,
          title: '${req.method} ${_shortenUrl(req.url)}',
          subtitle: 'Matched in: ${matchIn.join(", ")}',
          detail:
              '${res?.statusCode ?? "Pending"} • ${res?.durationMs ?? "–"}ms',
          timestamp: req.timestamp,
          copyText: req.url,
        ));
      }
    }

    // ── Search Logs ──
    for (final entry in BlackBox.instance.logStore.entries) {
      final msgMatch = entry.message.toLowerCase().contains(q);
      final tagMatch = entry.tag?.toLowerCase().contains(q) == true;
      final dataMatch =
          entry.data?.toString().toLowerCase().contains(q) == true;

      if (msgMatch || tagMatch || dataMatch) {
        results.add(_SearchResult(
          source: 'Logs',
          icon: Icons.article_outlined,
          color: BlackBoxColors.warning,
          title: entry.message.length > 80
              ? '${entry.message.substring(0, 80)}…'
              : entry.message,
          subtitle: entry.tag != null ? 'Tag: ${entry.tag}' : entry.level.label,
          detail: entry.level.label.toUpperCase(),
          timestamp: entry.timestamp,
          copyText: entry.message,
        ));
      }
    }

    // ── Search Crashes ──
    for (final entry in BlackBox.instance.crashStore.entries) {
      final msgMatch = entry.message.toLowerCase().contains(q);
      final libMatch = entry.library?.toLowerCase().contains(q) == true;
      final stackMatch =
          entry.stackTrace?.toString().toLowerCase().contains(q) == true;

      if (msgMatch || libMatch || stackMatch) {
        results.add(_SearchResult(
          source: 'Crash',
          icon: Icons.bug_report_outlined,
          color: BlackBoxColors.error,
          title: entry.message.length > 80
              ? '${entry.message.substring(0, 80)}…'
              : entry.message,
          subtitle: entry.library ?? 'Unknown',
          detail: 'CRASH',
          timestamp: entry.timestamp,
          copyText: entry.message,
        ));
      }
    }

    // ── Search Socket Events ──
    for (final entry in BlackBox.instance.socketStore.events) {
      final nameMatch = entry.eventName.toLowerCase().contains(q);
      final dataMatch =
          entry.data?.toString().toLowerCase().contains(q) == true;

      if (nameMatch || dataMatch) {
        results.add(_SearchResult(
          source: 'Socket',
          icon: Icons.power,
          color: Colors.purple,
          title: entry.eventName,
          subtitle: entry.direction.name,
          detail: entry.data?.toString().length.toString() ?? '',
          timestamp: entry.timestamp,
          copyText:
              '${entry.eventName}: ${entry.data?.toString() ?? "no data"}',
        ));
      }
    }

    // Sort by timestamp (newest first)
    results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return results;
  }

  String _shortenUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path + (uri.hasQuery ? '?${uri.query}' : '');
      return path.isEmpty ? '/' : path;
    } catch (_) {
      return url;
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _search(_query);

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        children: [
          // ── Search bar ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _query.isNotEmpty
                      ? const Color(0xFF6C63FF).withValues(alpha: 0.5)
                      : Colors.white10,
                ),
              ),
              child: TextField(
                controller: _controller,
                onChanged: _onSearchChanged,
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                    fontFamily: 'monospace'),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search across Network, Logs, Crashes, Sockets…',
                  hintStyle:
                      const TextStyle(fontSize: 11, color: Colors.white24),
                  prefixIcon:
                      const Icon(Icons.search, color: Colors.white24, size: 16),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 40, minHeight: 36),
                  suffixIcon: _query.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _controller.clear();
                            setState(() => _query = '');
                          },
                          child: const Icon(Icons.close,
                              color: Colors.white24, size: 14),
                        )
                      : null,
                  suffixIconConstraints:
                      const BoxConstraints(minWidth: 40, minHeight: 36),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),

          // ── Results ──
          if (_query.isEmpty)
            const Expanded(
              child: EmptyState(
                icon: Icons.search,
                label:
                    'Search across all panels\nNetwork • Logs • Crashes • Socket',
              ),
            )
          else if (results.isEmpty)
            Expanded(
              child: EmptyState(
                icon: Icons.search_off,
                label: 'No results for "$_query"',
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '${results.length} result${results.length == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 10, color: Colors.white38),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView.builder(
                itemCount: results.length,
                itemBuilder: (ctx, i) => _SearchResultTile(
                  result: results[i],
                  onTap: () => widget.onResultTap(results[i].source),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SearchResult {
  const _SearchResult({
    required this.source,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.timestamp,
    required this.copyText,
  });

  final String source;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String detail;
  final DateTime timestamp;
  final String copyText;
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.result, required this.onTap});
  final _SearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: result.copyText));
        HapticFeedback.lightImpact();
        BlackBoxToast.show(context, 'Copied ${result.source} entry');
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Source badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: result.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(result.icon, size: 10, color: result.color),
                      const SizedBox(width: 3),
                      Text(
                        result.source,
                        style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            color: result.color),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.title,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white70),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        result.subtitle,
                        style:
                            const TextStyle(fontSize: 9, color: Colors.white30),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  result.detail,
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: result.color),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
        ],
      ),
    );
  }
}
