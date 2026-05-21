import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../blackbox.dart';
import '../../core/log/log_level.dart';
import '../../core/report/blackbox_report.dart';
import '../../core/report/package_info_impl.dart'
    if (dart.library.html) '../../core/report/package_info_stub.dart'
    if (dart.library.js_interop) '../../core/report/package_info_stub.dart';

class QaPanel extends StatefulWidget {
  const QaPanel({super.key, required this.captureScreen});
  final Future<List<int>?> Function() captureScreen;

  @override
  State<QaPanel> createState() => _QaPanelState();
}

class _QaPanelState extends State<QaPanel> {
  final _notesController = TextEditingController();
  final _titleController = TextEditingController();
  BugSeverity _selectedSeverity = BugSeverity.medium;

  bool _isGenerating = false;
  String? _lastReportText;
  String? _lastMarkdownText;
  List<int>? _lastScreenshot;
  Map<String, String>? _packageInfo;

  @override
  void initState() {
    super.initState();
    _initPackageInfo();
  }

  Future<void> _initPackageInfo() async {
    final info = await getPackageInfo();
    if (mounted) setState(() => _packageInfo = info);
  }

  @override
  void dispose() {
    _notesController.dispose();
    _titleController.dispose();
    _lastScreenshot = null;
    super.dispose();
  }

  Future<void> _generateReport() async {
    final title = _titleController.text;
    final notes = _notesController.text;
    final severity = _selectedSeverity;

    setState(() => _isGenerating = true);
    try {
      final screenshot = await widget.captureScreen();
      if (!mounted) return;

      final report = await BlackBox.buildReport(
        bugTitle: title.isNotEmpty ? title : null,
        severity: severity,
        notes: notes,
        screenshotPngBytes: screenshot,
      );

      if (!mounted) return;

      setState(() {
        _lastReportText = report.toString();
        _lastMarkdownText = report.toMarkdown();
        _lastScreenshot = screenshot;
        _isGenerating = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  void _copyReport() {
    if (_lastReportText == null) return;
    Clipboard.setData(ClipboardData(text: _lastReportText!));
    _showCopied();
  }

  void _copyMarkdown() {
    if (_lastMarkdownText == null) return;
    Clipboard.setData(ClipboardData(text: _lastMarkdownText!));
    _showCopied();
  }

  void _showCopied() {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
          content: Text('Copied to clipboard'), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Crashes ───────────────────────────────────────────────────
          StreamBuilder(
            stream: BlackBox.instance.crashStore.stream,
            initialData: BlackBox.instance.crashStore.entries,
            builder: (context, snapshot) {
              final crashes = snapshot.data ?? [];
              if (crashes.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Label('CRASHES DETECTED'),
                  const SizedBox(height: 6),
                  ...crashes.map((c) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.red.withValues(alpha: 0.3),
                              width: 0.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.message,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                            if (c.library != null) ...[
                              const SizedBox(height: 4),
                              Text('Library: ${c.library}',
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.white70)),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              c.stackTrace?.toString() ?? 'No stack trace',
                              style: const TextStyle(
                                  fontSize: 9,
                                  color: Colors.white54,
                                  fontFamily: 'monospace'),
                              maxLines: 8,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
          // ── App Info ──────────────────────────────────────────────────
          if (_packageInfo != null) ...[
            const _Label('App Version Info'),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('App Name: ${_packageInfo!['appName'] ?? ''}',
                      style:
                          const TextStyle(fontSize: 11, color: Colors.white70)),
                  const SizedBox(height: 4),
                  Text(
                      'Version: ${_packageInfo!['version'] ?? ''} (${_packageInfo!['buildNumber'] ?? ''})',
                      style:
                          const TextStyle(fontSize: 11, color: Colors.white70)),
                  const SizedBox(height: 4),
                  Text('Package Name: ${_packageInfo!['packageName'] ?? ''}',
                      style:
                          const TextStyle(fontSize: 11, color: Colors.white70)),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          // ── Summary stats ────────────────────────────────────────────
          _SummaryRow(),
          const SizedBox(height: 16),
          // ── Bug details ──────────────────────────────────────────────
          const _Label('Bug Title (optional)'),
          const SizedBox(height: 6),
          TextField(
            controller: _titleController,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
            decoration: InputDecoration(
              hintText: 'Short summary of the issue...',
              hintStyle: const TextStyle(fontSize: 11, color: Colors.white24),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.04),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: Colors.white10, width: 0.5)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: Colors.white10, width: 0.5)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            ),
          ),
          const SizedBox(height: 12),
          const _Label('Severity'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: BugSeverity.values.map((s) {
              final isSelected = _selectedSeverity == s;
              return GestureDetector(
                onTap: () => setState(() => _selectedSeverity = s),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF6C63FF).withValues(alpha: 0.8)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: isSelected
                            ? const Color(0xFF6C63FF)
                            : Colors.white10,
                        width: 0.5),
                  ),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.white : Colors.white60),
                    child: Text(s.name.toUpperCase()),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          // ── Tester notes ─────────────────────────────────────────────
          const _Label('Tester notes (optional)'),
          const SizedBox(height: 6),
          TextField(
            controller: _notesController,
            maxLines: 3,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
            decoration: InputDecoration(
              hintText: 'Describe what you were doing when the bug occurred…',
              hintStyle: const TextStyle(fontSize: 11, color: Colors.white24),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.04),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white10, width: 0.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white10, width: 0.5),
              ),
              contentPadding: const EdgeInsets.all(10),
            ),
          ),
          const SizedBox(height: 16),
          // ── Generate button ──────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isGenerating ? null : _generateReport,
              icon: _isGenerating
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.bug_report_outlined, size: 16),
              label: Text(_isGenerating ? 'Generating…' : 'Generate QA Report'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          if (_lastMarkdownText != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _copyMarkdown,
                icon: const Icon(Icons.article_outlined, size: 16),
                label: const Text('Export Markdown'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
          // ── Report preview ───────────────────────────────────────────
          if (_lastReportText != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const _Label('Report preview'),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.copy, size: 12),
                  label: const Text('Copy', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.white38,
                      padding: EdgeInsets.zero),
                  onPressed: _copyReport,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10, width: 0.5),
              ),
              child: Text(
                _lastReportText!,
                style: const TextStyle(
                    fontSize: 9,
                    color: Colors.white54,
                    fontFamily: 'monospace',
                    height: 1.5),
              ),
            ),
            if (_lastScreenshot != null) ...[
              const SizedBox(height: 12),
              const _Label('Screenshot'),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  Uint8List.fromList(_lastScreenshot!),
                  fit: BoxFit.contain,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final logCount = BlackBox.instance.logStore.entries.length;
    final networkCount = BlackBox.instance.networkStore.entries.length;
    final errorCount = BlackBox.instance.logStore.entries
        .where((e) => e.level == LogLevel.error)
        .length;

    return Row(
      children: [
        _StatBadge(label: 'Logs', value: '$logCount', color: Colors.white38),
        const SizedBox(width: 8),
        _StatBadge(
            label: 'Requests', value: '$networkCount', color: Colors.blue),
        const SizedBox(width: 8),
        _StatBadge(
            label: 'Errors',
            value: '$errorCount',
            color: errorCount > 0 ? const Color(0xFFE24B4A) : Colors.white24),
      ],
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: color)),
          Text(label,
              style: const TextStyle(fontSize: 9, color: Colors.white38)),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 10,
          color: Colors.white38,
          fontWeight: FontWeight.w600,
          letterSpacing: .5));
}
