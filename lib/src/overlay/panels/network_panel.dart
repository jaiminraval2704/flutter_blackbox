import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/network_store.dart';
import '../../core/network/network_request.dart';
import '../../core/network/network_response.dart';
import '../../core/network/network_throttle.dart';
import '../../core/network/network_replayer.dart';
import '../../blackbox.dart';
import '../widgets/blackbox_colors.dart';
import '../widgets/empty_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Filter enums
// ─────────────────────────────────────────────────────────────────────────────

enum _StatusFilter { all, success, clientErr, serverErr, pending, failed }

class NetworkPanel extends StatefulWidget {
  const NetworkPanel({super.key});

  @override
  State<NetworkPanel> createState() => _NetworkPanelState();
}

class _NetworkPanelState extends State<NetworkPanel> {
  String _query = '';
  _StatusFilter _statusFilter = _StatusFilter.all;
  String _methodFilter = 'ALL';

  // Single subscription instead of two StreamBuilders on the same stream.
  List<NetworkEntry> _entries = const [];
  StreamSubscription<List<NetworkEntry>>? _sub;

  @override
  void initState() {
    super.initState();
    _entries = BlackBox.instance.networkStore.entries;
    _sub = BlackBox.instance.networkStore.stream.listen((entries) {
      if (mounted) setState(() => _entries = entries);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  List<NetworkEntry> _applyFilters(List<NetworkEntry> entries) {
    var filtered = entries;

    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      filtered = filtered
          .where((e) => e.request.url.toLowerCase().contains(q))
          .toList();
    }

    if (_methodFilter != 'ALL') {
      filtered = filtered
          .where((e) => e.request.method.toUpperCase() == _methodFilter)
          .toList();
    }

    filtered = switch (_statusFilter) {
      _StatusFilter.all => filtered,
      _StatusFilter.success =>
        filtered.where((e) => e.response?.isSuccess == true).toList(),
      _StatusFilter.clientErr =>
        filtered.where((e) => e.response?.isClientError == true).toList(),
      _StatusFilter.serverErr =>
        filtered.where((e) => e.response?.isServerError == true).toList(),
      _StatusFilter.pending => filtered.where((e) => e.isPending).toList(),
      _StatusFilter.failed => filtered
          .where((e) =>
              e.response?.failureType != null &&
              e.response!.failureType != NetworkFailureType.none)
          .toList(),
    };

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    // Compute counts in a single O(N) pass.
    int c2xx = 0, c4xx = 0, c5xx = 0, cPend = 0, cFail = 0;
    for (final e in _entries) {
      if (e.isPending) {
        cPend++;
      } else {
        final res = e.response;
        if (res != null) {
          if (res.isSuccess) {
            c2xx++;
          } else if (res.isClientError) {
            c4xx++;
          } else if (res.isServerError) {
            c5xx++;
          }

          if (res.failureType != NetworkFailureType.none) {
            cFail++;
          }
        }
      }
    }

    // All data comes from _entries — no StreamBuilders needed here.
    final filtered = _applyFilters(_entries);

    String baseUrl = '';
    try {
      if (_entries.isNotEmpty) {
        baseUrl = Uri.parse(_entries.last.request.url).origin;
      }
    } catch (_) {}

    return Column(
      children: [
        // ── Search bar + actions ──────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: PanelSearchBar(
                  hint: 'Filter by URL…',
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  showModalBottomSheet<void>(
                    context: context,
                    backgroundColor: const Color(0xff2A2A2A),
                    builder: (ctx) => const _ThrottleSettingsSheet(),
                  );
                },
                child: const Icon(Icons.speed, color: Colors.white38, size: 18),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => BlackBox.instance.networkStore.clear(),
                child: const Icon(Icons.delete_outline,
                    color: Colors.white38, size: 18),
              ),
            ],
          ),
        ),

        // ── Filter chips row ─────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: SizedBox(
            height: 28,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _FilterChip(
                  label: 'All',
                  count: _entries.length,
                  selected: _statusFilter == _StatusFilter.all,
                  onTap: () =>
                      setState(() => _statusFilter = _StatusFilter.all),
                ),
                _FilterChip(
                  label: '2xx',
                  count: c2xx,
                  color: BlackBoxColors.success,
                  selected: _statusFilter == _StatusFilter.success,
                  onTap: () =>
                      setState(() => _statusFilter = _StatusFilter.success),
                ),
                _FilterChip(
                  label: '4xx',
                  count: c4xx,
                  color: BlackBoxColors.warning,
                  selected: _statusFilter == _StatusFilter.clientErr,
                  onTap: () =>
                      setState(() => _statusFilter = _StatusFilter.clientErr),
                ),
                _FilterChip(
                  label: '5xx',
                  count: c5xx,
                  color: BlackBoxColors.error,
                  selected: _statusFilter == _StatusFilter.serverErr,
                  onTap: () =>
                      setState(() => _statusFilter = _StatusFilter.serverErr),
                ),
                _FilterChip(
                  label: '⏳',
                  count: cPend,
                  selected: _statusFilter == _StatusFilter.pending,
                  onTap: () =>
                      setState(() => _statusFilter = _StatusFilter.pending),
                ),
                _FilterChip(
                  label: '❌',
                  count: cFail,
                  color: BlackBoxColors.error,
                  selected: _statusFilter == _StatusFilter.failed,
                  onTap: () =>
                      setState(() => _statusFilter = _StatusFilter.failed),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 1,
                  height: 16,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  color: Colors.white12,
                ),
                const SizedBox(width: 8),
                for (final m in [
                  'ALL',
                  'GET',
                  'POST',
                  'PUT',
                  'DELETE',
                  'PATCH'
                ])
                  _FilterChip(
                    label: m,
                    color: _methodColor(m),
                    selected: _methodFilter == m,
                    onTap: () => setState(() => _methodFilter = m),
                  ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 6),

        // ── Request list ─────────────────────────────────────────────
        Expanded(
          child: _entries.isEmpty
              ? const EmptyState(
                  icon: Icons.wifi_off, label: 'No requests yet', emoji: '🕸️')
              : filtered.isEmpty
                  ? const EmptyState(
                      icon: Icons.filter_alt_off,
                      label: 'No requests match filters',
                      emoji: '🔍')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (baseUrl.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(
                                left: 12, right: 12, bottom: 4),
                            child: Text(
                              'Base: $baseUrl   •   ${filtered.length} request${filtered.length == 1 ? '' : 's'}',
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white38,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (ctx, i) => _NetworkTile(
                                entry: filtered[filtered.length - 1 - i]),
                          ),
                        ),
                      ],
                    ),
        ),
      ],
    );
  }

  Color _methodColor(String m) => switch (m) {
        'GET' => Colors.green,
        'POST' => Colors.blue,
        'PUT' || 'PATCH' => Colors.orange,
        'DELETE' => Colors.red,
        _ => Colors.white38,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter chip widget
// ─────────────────────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    this.count,
    this.color,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int? count;
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white38;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? c.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? c.withValues(alpha: 0.6) : Colors.white10,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: selected ? c : Colors.white38),
            ),
            if (count != null && count! > 0) ...[
              const SizedBox(width: 3),
              Text(
                '$count',
                style: TextStyle(
                    fontSize: 8, color: selected ? c : Colors.white24),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Throttle settings
// ─────────────────────────────────────────────────────────────────────────────

class _ThrottleSettingsSheet extends StatefulWidget {
  const _ThrottleSettingsSheet();
  @override
  State<_ThrottleSettingsSheet> createState() => _ThrottleSettingsSheetState();
}

class _ThrottleSettingsSheetState extends State<_ThrottleSettingsSheet> {
  @override
  Widget build(BuildContext context) {
    final throttle = NetworkThrottle.instance;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Network Throttle (Mocks Only)',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Enable Throttle',
                  style: TextStyle(color: Colors.white, fontSize: 13)),
              value: throttle.enabled,
              onChanged: (v) => setState(() => throttle.enabled = v),
              activeTrackColor: BlackBoxColors.success.withValues(alpha: 0.5),
              activeThumbColor: BlackBoxColors.success,
              contentPadding: EdgeInsets.zero,
            ),
            if (throttle.enabled) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Delay (ms)',
                      style: TextStyle(color: Colors.white70, fontSize: 11)),
                  Expanded(
                    child: Slider(
                      value: throttle.delayMs.toDouble(),
                      min: 0,
                      max: 5000,
                      divisions: 50,
                      activeColor: BlackBoxColors.success,
                      inactiveColor: Colors.white12,
                      label: '${throttle.delayMs} ms',
                      onChanged: (v) =>
                          setState(() => throttle.delayMs = v.toInt()),
                    ),
                  ),
                  Text('${throttle.delayMs} ms',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ]
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Network tile (each request row)
// ─────────────────────────────────────────────────────────────────────────────

class _NetworkTile extends StatefulWidget {
  const _NetworkTile({required this.entry});
  final NetworkEntry entry;

  @override
  State<_NetworkTile> createState() => _NetworkTileState();
}

class _NetworkTileState extends State<_NetworkTile> {
  bool _expanded = false;

  // Cached endpoint string — Uri.parse() is not called on every build.
  late String _endpoint;

  @override
  void initState() {
    super.initState();
    _endpoint = _parseEndpoint(widget.entry.request.url);
  }

  @override
  void didUpdateWidget(_NetworkTile old) {
    super.didUpdateWidget(old);
    if (old.entry.request.url != widget.entry.request.url) {
      _endpoint = _parseEndpoint(widget.entry.request.url);
    }
  }

  static String _parseEndpoint(String url) {
    try {
      final uri = Uri.parse(url);
      final ep = uri.path + (uri.hasQuery ? '?${uri.query}' : '');
      return ep.isEmpty ? '/' : ep;
    } catch (_) {
      return url;
    }
  }

  Color get _statusColor {
    final code = widget.entry.response?.statusCode ?? 0;
    if (code == 0) return Colors.white38;
    if (code < 300) return BlackBoxColors.success;
    if (code < 500) return BlackBoxColors.warning;
    return BlackBoxColors.error;
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.entry.request;
    final res = widget.entry.response;

    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              children: [
                _MethodBadge(method: req.method),
                if (req.isReplay) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      'REPLAY',
                      style: TextStyle(
                        fontSize: 7,
                        fontWeight: FontWeight.w800,
                        color: Colors.deepPurple,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _endpoint,
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (res != null) ...[
                  const SizedBox(width: 4),
                  if (res.failureType != NetworkFailureType.none) ...[
                    Text(
                      res.failureType.name.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 9,
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w600),
                    ),
                  ] else ...[
                    Text(
                      '${res.statusCode}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _statusColor),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${res.durationMs}ms',
                      style:
                          const TextStyle(fontSize: 9, color: Colors.white38),
                    ),
                    // ── Response size ──
                    if (res.formattedSize.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(
                        res.formattedSize,
                        style:
                            const TextStyle(fontSize: 9, color: Colors.white24),
                      ),
                    ],
                  ],
                ] else
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        color: Colors.white38, strokeWidth: 1.5),
                  ),
                const SizedBox(width: 4),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white24,
                  size: 16,
                ),
              ],
            ),
          ),
          // ── Timing bar & Detail ──
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? _NetworkDetail(entry: widget.entry)
                : (res != null
                    ? Padding(
                        padding: const EdgeInsets.only(
                            left: 12, right: 12, bottom: 4),
                        child: _TimingBar(durationMs: res.durationMs),
                      )
                    : const SizedBox(width: double.infinity)),
          ),
          const Divider(color: Colors.white10, height: 1),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Timing bar visualization
// ─────────────────────────────────────────────────────────────────────────────

class _TimingBar extends StatelessWidget {
  const _TimingBar({required this.durationMs});
  final int durationMs;

  @override
  Widget build(BuildContext context) {
    // Normalize: 0ms = 0%, 3000ms+ = 100%
    final ratio = (durationMs / 3000).clamp(0.0, 1.0);
    final color = durationMs < 300
        ? BlackBoxColors.success
        : durationMs < 1000
            ? BlackBoxColors.warning
            : BlackBoxColors.error;

    return SizedBox(
      height: 3,
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          return Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: constraints.maxWidth * ratio,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expanded detail view with cURL, pretty JSON, timing
// ─────────────────────────────────────────────────────────────────────────────

class _NetworkDetail extends StatelessWidget {
  const _NetworkDetail({required this.entry});
  final NetworkEntry entry;

  @override
  Widget build(BuildContext context) {
    final req = entry.request;
    final res = entry.response;

    return Container(
      color: Colors.white.withValues(alpha: 0.03),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Timing summary ──
          if (res != null) ...[
            _TimingDetailRow(res: res),
            const SizedBox(height: 8),
          ],

          // ── Request ──
          if (req.headers.isNotEmpty)
            _CollapsibleJsonSection(
                title: 'Request Headers', data: req.headers),
          if (req.body != null)
            _CollapsibleJsonSection(title: 'Request Body', data: req.body),

          // ── Response ──
          if (res != null) ...[
            _Section(
                title: 'Response status code:',
                content: res.statusCode.toString()),
            _Section(
                title: 'Response message:',
                content: res.failureType != NetworkFailureType.none
                    ? res.failureType.name
                    : 'Success'),
            if (res.body != null)
              _CollapsibleJsonSection(title: 'Response Body', data: res.body),
          ],

          // ── Action buttons ──
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                _ActionButton(
                  icon: Icons.replay,
                  label: 'Replay',
                  onPressed: () async {
                    _showSnackBar(context,
                        'Replaying ${req.method} ${req.url.split('/').last}…');
                    try {
                      final response = await NetworkReplayer.replay(req);
                      if (context.mounted) {
                        _showSnackBar(context,
                            'Replay complete: ${response.statusCode} (${response.durationMs}ms)');
                      }
                    } catch (e) {
                      if (context.mounted) {
                        _showSnackBar(context, 'Replay failed: $e');
                      }
                    }
                  },
                ),
                _ActionButton(
                  icon: Icons.terminal,
                  label: 'cURL',
                  onPressed: () {
                    final curl = _generateCurl(req);
                    Clipboard.setData(ClipboardData(text: curl));
                    _showSnackBar(context, 'cURL copied to clipboard');
                  },
                ),
                _ActionButton(
                  icon: Icons.copy,
                  label: 'Copy URL',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: req.url));
                    _showSnackBar(context, 'URL copied');
                  },
                ),
                _ActionButton(
                  icon: Icons.copy_all,
                  label: 'Copy All',
                  onPressed: () {
                    final fullData = _generateFullCopy(req, res);
                    Clipboard.setData(ClipboardData(text: fullData));
                    _showSnackBar(context, 'Full request/response copied');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── cURL generator ──────────────────────────────────────────────────────

  String _generateCurl(NetworkRequest req) {
    final parts = <String>["curl -X ${req.method} '${req.url}'"];

    req.headers.forEach((key, value) {
      // Skip redacted headers in cURL
      if (value.toString().contains('redacted')) return;
      parts.add("-H '$key: $value'");
    });

    if (req.body != null) {
      String bodyStr;
      try {
        bodyStr = const JsonEncoder().convert(req.body);
      } catch (_) {
        bodyStr = req.body.toString();
      }
      parts.add("-d '$bodyStr'");
    }

    return parts.join(' \\\n  ');
  }

  String _generateFullCopy(NetworkRequest req, NetworkResponse? res) {
    return '''Request URL: ${req.url}
Method: ${req.method}
Timestamp: ${req.timestamp.toIso8601String()}

Request Headers:
${_formatJson(req.headers)}

Request Body:
${req.body != null ? _formatJson(req.body) : 'None'}

Response status code: ${res?.statusCode ?? 'Pending'}
Duration: ${res?.durationMs ?? '–'}ms
Size: ${res?.formattedSize ?? '–'}
Response message: ${res != null && res.failureType != NetworkFailureType.none ? res.failureType.name : 'Success'}

Response Body:
${res?.body != null ? _formatJson(res!.body) : 'None'}

cURL:
${_generateCurl(req)}''';
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

  void _showSnackBar(BuildContext context, String msg) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 12)),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2A2A3E),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Timing detail row
// ─────────────────────────────────────────────────────────────────────────────

class _TimingDetailRow extends StatelessWidget {
  const _TimingDetailRow({required this.res});
  final NetworkResponse res;

  @override
  Widget build(BuildContext context) {
    final color = res.durationMs < 300
        ? BlackBoxColors.success
        : res.durationMs < 1000
            ? BlackBoxColors.warning
            : BlackBoxColors.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, size: 12, color: color),
          const SizedBox(width: 6),
          Text(
            '${res.durationMs}ms',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: color),
          ),
          if (res.formattedSize.isNotEmpty) ...[
            const SizedBox(width: 12),
            const Icon(Icons.data_usage, size: 12, color: Colors.white38),
            const SizedBox(width: 4),
            Text(
              res.formattedSize,
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ],
          const Spacer(),
          // Speed indicator
          Text(
            res.durationMs < 300
                ? '⚡ Fast'
                : res.durationMs < 1000
                    ? '🐢 Slow'
                    : '🐌 Very slow',
            style: TextStyle(fontSize: 10, color: color),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Collapsible JSON section — Pretty JSON Viewer
// ─────────────────────────────────────────────────────────────────────────────

class _CollapsibleJsonSection extends StatefulWidget {
  const _CollapsibleJsonSection({
    required this.title,
    required this.data,
  });
  final String title;
  final dynamic data;

  @override
  State<_CollapsibleJsonSection> createState() =>
      _CollapsibleJsonSectionState();
}

class _CollapsibleJsonSectionState extends State<_CollapsibleJsonSection> {
  bool _expanded = false;

  // Cache the decoded result — jsonDecode is not called on every build().
  late dynamic _parsed;

  @override
  void initState() {
    super.initState();
    _parsed = _decodeData(widget.data);
  }

  @override
  void didUpdateWidget(_CollapsibleJsonSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _parsed = _decodeData(widget.data);
    }
  }

  static dynamic _decodeData(dynamic d) {
    if (d is Map || d is List) return d;
    if (d is String) {
      try {
        return jsonDecode(d);
      } catch (_) {
        return d;
      }
    }
    return d;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 14,
                  color: Colors.white38,
                ),
                const SizedBox(width: 4),
                Text(widget.title,
                    style: const TextStyle(
                        fontSize: 9,
                        color: Colors.white38,
                        fontWeight: FontWeight.w600,
                        letterSpacing: .5)),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    final text = _formatForCopy(_parsed);
                    Clipboard.setData(ClipboardData(text: text));
                  },
                  child:
                      const Icon(Icons.copy, size: 12, color: Colors.white24),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: _buildJsonTree(_parsed, 0),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _previewText(_parsed),
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.4),
                          fontFamily: 'monospace'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _previewText(dynamic data) {
    if (data is Map) {
      return '{${data.length} key${data.length == 1 ? '' : 's'}}';
    }
    if (data is List) {
      return '[${data.length} item${data.length == 1 ? '' : 's'}]';
    }
    final s = data.toString();
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }

  String _formatForCopy(dynamic data) {
    try {
      return const JsonEncoder.withIndent('  ').convert(data);
    } catch (_) {
      return data.toString();
    }
  }

  Widget _buildJsonTree(dynamic data, int depth) {
    if (depth > 8) {
      return const Text('…',
          style: TextStyle(color: Colors.white38, fontSize: 10));
    }
    if (data is Map) return _JsonMapTree(map: data, depth: depth);
    if (data is List) return _JsonListTree(list: data, depth: depth);
    return _JsonValue(value: data);
  }
}

// ── JSON Map tree ──

class _JsonMapTree extends StatelessWidget {
  const _JsonMapTree({required this.map, required this.depth});
  final Map<dynamic, dynamic> map;
  final int depth;

  @override
  Widget build(BuildContext context) {
    if (map.isEmpty) {
      return const Text('{}',
          style: TextStyle(
              fontSize: 10, color: Colors.white38, fontFamily: 'monospace'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: map.entries.map((e) {
        final isComplex = e.value is Map || e.value is List;
        return _JsonKeyValueRow(
          keyName: e.key.toString(),
          value: e.value,
          depth: depth,
          isComplex: isComplex,
        );
      }).toList(),
    );
  }
}

class _JsonKeyValueRow extends StatefulWidget {
  const _JsonKeyValueRow({
    required this.keyName,
    required this.value,
    required this.depth,
    required this.isComplex,
  });
  final String keyName;
  final dynamic value;
  final int depth;
  final bool isComplex;

  @override
  State<_JsonKeyValueRow> createState() => _JsonKeyValueRowState();
}

class _JsonKeyValueRowState extends State<_JsonKeyValueRow> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    // Auto-expand first two levels
    _expanded = widget.depth < 1;
  }

  String get _preview {
    if (widget.value is Map) return '{${(widget.value as Map).length}}';
    if (widget.value is List) return '[${(widget.value as List).length}]';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: widget.depth * 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: widget.isComplex
                ? () => setState(() => _expanded = !_expanded)
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.isComplex)
                    Icon(
                      _expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 12,
                      color: Colors.white24,
                    ),
                  if (!widget.isComplex) const SizedBox(width: 12),
                  Text(
                    '"${widget.keyName}"',
                    style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF82AAFF),
                        fontFamily: 'monospace'),
                  ),
                  const Text(': ',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.white38,
                          fontFamily: 'monospace')),
                  if (!widget.isComplex)
                    Expanded(child: _JsonValue(value: widget.value))
                  else
                    Text(
                      _preview,
                      style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white24,
                          fontFamily: 'monospace'),
                    ),
                ],
              ),
            ),
          ),
          if (_expanded && widget.isComplex)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: widget.value is Map
                  ? _JsonMapTree(
                      map: widget.value as Map, depth: widget.depth + 1)
                  : _JsonListTree(
                      list: widget.value as List, depth: widget.depth + 1),
            ),
        ],
      ),
    );
  }
}

// ── JSON List tree ──

class _JsonListTree extends StatelessWidget {
  const _JsonListTree({required this.list, required this.depth});
  final List<dynamic> list;
  final int depth;

  @override
  Widget build(BuildContext context) {
    if (list.isEmpty) {
      return const Text('[]',
          style: TextStyle(
              fontSize: 10, color: Colors.white38, fontFamily: 'monospace'));
    }
    // Show max 20 items, then truncate
    final items = list.length > 20 ? list.sublist(0, 20) : list;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...items.asMap().entries.map((e) {
          final isComplex = e.value is Map || e.value is List;
          return _JsonKeyValueRow(
            keyName: '${e.key}',
            value: e.value,
            depth: depth,
            isComplex: isComplex,
          );
        }),
        if (list.length > 20)
          Padding(
            padding: EdgeInsets.only(left: depth * 12.0),
            child: Text(
              '… ${list.length - 20} more items',
              style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white24,
                  fontFamily: 'monospace',
                  fontStyle: FontStyle.italic),
            ),
          ),
      ],
    );
  }
}

// ── JSON value (leaf node) ──

class _JsonValue extends StatelessWidget {
  const _JsonValue({required this.value});
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    final (text, color) = _format(value);
    return Text(
      text,
      style: TextStyle(fontSize: 10, color: color, fontFamily: 'monospace'),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }

  (String, Color) _format(dynamic v) {
    if (v == null) return ('null', const Color(0xFF808080));
    if (v is bool) return ('$v', const Color(0xFFFF9CAC));
    if (v is num) return ('$v', const Color(0xFFF78C6C));
    if (v is String) {
      final s = v.length > 200 ? '${v.substring(0, 200)}…' : v;
      return ('"$s"', const Color(0xFFC3E88D));
    }
    return (v.toString(), Colors.white60);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

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

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      icon: Icon(icon, size: 12),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      style: TextButton.styleFrom(
          foregroundColor: Colors.white38,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      onPressed: onPressed,
    );
  }
}

class _MethodBadge extends StatelessWidget {
  const _MethodBadge({required this.method});
  final String method;

  Color get _color => switch (method.toUpperCase()) {
        'GET' => Colors.green,
        'POST' => Colors.blue,
        'PUT' || 'PATCH' => Colors.orange,
        'DELETE' => Colors.red,
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        method.toUpperCase(),
        style:
            TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: _color),
      ),
    );
  }
}
