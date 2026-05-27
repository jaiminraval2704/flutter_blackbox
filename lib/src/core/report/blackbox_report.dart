import 'blackbox_device_info.dart';

/// A complete QA report bundle — screenshot + logs + network + device info.
class BlackBoxReport {
  const BlackBoxReport({
    this.bugTitle,
    required this.severity,
    required this.timestamp,
    required this.appInfo,
    required this.deviceInfo,
    required this.socketEvents,
    required this.userJourney,
    required this.failedRequests,
    required this.logs,
    required this.networkRequests,
    required this.crashes,
    this.screenshotPngBytes,
    this.notes,
  });

  /// Optional title for the bug report.
  final String? bugTitle;

  /// Urgency of the reported bug.
  final BugSeverity severity;

  /// When the report was generated.
  final DateTime timestamp;

  /// Map containing application version and build information.
  final Map<String, String> appInfo;

  /// Technical details about the device hardware and OS.
  final BlackBoxDeviceInfo deviceInfo;

  /// List of recent Socket.IO events.
  final List<Map<String, dynamic>> socketEvents;

  /// Sequence of user navigation steps leading up to the report.
  final List<String> userJourney;

  /// List of network requests that returned an error status code.
  final List<Map<String, dynamic>> failedRequests;

  /// List of recent application logs.
  final List<Map<String, dynamic>> logs;

  /// List of all recorded network requests.
  final List<Map<String, dynamic>> networkRequests;

  /// List of captured crashes.
  final List<Map<String, dynamic>> crashes;

  /// Captured PNG screenshot bytes of the app when the report was created.
  final List<int>? screenshotPngBytes;

  /// User-provided notes and reproduction steps from the QA panel.
  final String? notes;

  Map<String, dynamic> toJson() => {
        'bugTitle': bugTitle,
        'severity': severity.name,
        'timestamp': timestamp.toIso8601String(),
        'app': appInfo,
        'device': deviceInfo.toJson(),
        'socketEvents': socketEvents,
        'userJourney': userJourney,
        'failedRequests': failedRequests,
        'logs': logs,
        'networkRequests': networkRequests,
        'crashes': crashes,
        'hasScreenshot': screenshotPngBytes != null,
        'notes': notes,
        // screenshot is omitted from JSON (too large); shared separately
      };

  String toMarkdown() => '''
## ${bugTitle ?? 'Bug Report'} [${severity.name.toUpperCase()}]

**Reported:** ${timestamp.toIso8601String()}
**Device:** ${deviceInfo.deviceModel} — ${deviceInfo.osVersion}
**Network:** ${deviceInfo.networkType}
**App:** v${appInfo['version']} (build ${appInfo['buildNumber']})

### Steps to reproduce
${userJourney.join('\n')}

### Failed requests
${failedRequests.map((r) {
        final req = r['request'] as Map?;
        final res = r['response'] as Map?;
        return '- ${req?['method']} ${req?['url']} → ${res?['statusCode']} (${res?['durationMs']}ms)';
      }).join('\n')}

### Crashes
${crashes.isEmpty ? 'None' : crashes.map((c) => '- ${c['message']}').join('\n')}

${notes != null && notes!.isNotEmpty ? '### Notes\n$notes\n' : ''}
''';

  @override
  String toString() {
    final buf = StringBuffer()
      ..writeln('=== BlackBox QA Report ===')
      ..writeln('Title: ${bugTitle ?? 'N/A'} [${severity.name.toUpperCase()}]')
      ..writeln('Generated: ${timestamp.toIso8601String()}');

    buf
      ..writeln()
      ..writeln('--- App ---');
    appInfo.forEach((k, v) => buf.writeln('$k: $v'));
    buf
      ..writeln()
      ..writeln('--- Device ---');
    deviceInfo.toJson().forEach((k, v) => buf.writeln('$k: $v'));
    buf
      ..writeln()
      ..writeln('--- Socket IO (${socketEvents.length}) ---');
    for (final e in socketEvents) {
      buf.writeln('[${e['direction']}] ${e['timestamp']} ${e['eventName']}');
    }
    buf
      ..writeln()
      ..writeln('--- Logs (${logs.length}) ---');
    for (final l in logs) {
      buf.writeln('[${l['level']}] ${l['timestamp']} ${l['message']}');
    }
    buf
      ..writeln()
      ..writeln('--- Network (${networkRequests.length}) ---');
    for (final n in networkRequests) {
      final req = n['request'] as Map?;
      final res = n['response'] as Map?;
      if (req != null) {
        buf.writeln(
          '${req['method']} ${req['url']} → '
          '${res?['statusCode'] ?? 'pending'} '
          '(${res?['durationMs'] ?? '?'}ms)',
        );
      }
    }
    if (notes != null && notes!.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('--- Notes ---')
        ..writeln(notes);
    }
    return buf.toString();
  }
}

/// Qualitative urgency of a bug report.
enum BugSeverity {
  /// App is unusable or critical feature is broken.
  critical,

  /// Significant functionality is impaired.
  high,

  /// Minor defect with an available workaround.
  medium,

  /// Visual tweak or non-blocking issue.
  low
}
