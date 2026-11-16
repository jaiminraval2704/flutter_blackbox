import 'dart:convert';

import '../network/network_request.dart';

/// Generates a valid cURL command string from a [NetworkRequest].
///
/// ```dart
/// final curl = CurlExporter.toCurl(request);
/// Clipboard.setData(ClipboardData(text: curl));
/// ```
class CurlExporter {
  CurlExporter._();

  /// Converts a [NetworkRequest] into a ready-to-paste cURL command.
  static String toCurl(NetworkRequest req) {
    final buffer = StringBuffer("curl -X ${req.method}");

    // URL with query parameters
    var url = req.url;
    if (req.queryParameters.isNotEmpty) {
      final query = req.queryParameters.entries
          .map((e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');
      final separator = url.contains('?') ? '&' : '?';
      url = '$url$separator$query';
    }
    buffer.write(" '${_escapeShell(url)}'");

    // Headers
    for (final entry in req.headers.entries) {
      buffer
          .write(" \\\n  -H '${_escapeShell('${entry.key}: ${entry.value}')}'");
    }

    // Body
    if (req.body != null) {
      String bodyStr;
      if (req.body is String) {
        bodyStr = req.body as String;
      } else {
        try {
          bodyStr = jsonEncode(req.body);
        } catch (_) {
          bodyStr = req.body.toString();
        }
      }
      buffer.write(" \\\n  -d '${_escapeShell(bodyStr)}'");
    }

    return buffer.toString();
  }

  /// Escapes single quotes for safe shell usage.
  static String _escapeShell(String value) {
    return value.replaceAll("'", "'\\''");
  }
}
