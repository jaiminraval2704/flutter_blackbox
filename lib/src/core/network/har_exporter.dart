import 'dart:convert';

import 'network_store.dart';

/// Exports a list of [NetworkEntry] as a HAR 1.2 JSON string.
///
/// HAR (HTTP Archive) is the industry-standard format supported by
/// Postman, Insomnia, Chrome DevTools, and Charles Proxy.
///
/// ```dart
/// final har = HarExporter.toHar(BlackBox.instance.networkStore.entries);
/// Clipboard.setData(ClipboardData(text: har));
/// ```
class HarExporter {
  HarExporter._();

  /// Converts network entries to a HAR 1.2 JSON string.
  static String toHar(List<NetworkEntry> entries) {
    final harEntries = entries
        .where((e) => e.response != null)
        .map((e) => _buildEntry(e))
        .toList();

    final har = {
      'log': {
        'version': '1.2',
        'creator': {
          'name': 'Flutter BlackBox',
          'version': '0.6.0',
        },
        'entries': harEntries,
      },
    };

    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(har);
  }

  static Map<String, dynamic> _buildEntry(NetworkEntry entry) {
    final req = entry.request;
    final res = entry.response!;

    return {
      'startedDateTime': req.timestamp.toIso8601String(),
      'time': res.durationMs,
      'request': {
        'method': req.method,
        'url': req.url,
        'httpVersion': 'HTTP/1.1',
        'headers': req.headers.entries
            .map((e) => {'name': e.key, 'value': '${e.value}'})
            .toList(),
        'queryString': req.queryParameters.entries
            .map((e) => {'name': e.key, 'value': e.value})
            .toList(),
        'postData': req.body != null
            ? {
                'mimeType': req.headers['content-type'] ??
                    req.headers['Content-Type'] ??
                    'application/json',
                'text': req.body is String ? req.body : jsonEncode(req.body),
              }
            : null,
        'headersSize': -1,
        'bodySize': req.body != null
            ? (req.body is String
                ? (req.body as String).length
                : jsonEncode(req.body).length)
            : 0,
      },
      'response': {
        'status': res.statusCode,
        'statusText': _statusText(res.statusCode),
        'httpVersion': 'HTTP/1.1',
        'headers': res.headers.entries
            .map((e) => {'name': e.key, 'value': e.value})
            .toList(),
        'content': {
          'size': res.responseSizeBytes ?? 0,
          'mimeType': res.headers['content-type'] ?? 'application/json',
          'text': res.body is String ? res.body : jsonEncode(res.body ?? ''),
        },
        'headersSize': -1,
        'bodySize': res.responseSizeBytes ?? 0,
      },
      'cache': <String, dynamic>{},
      'timings': {
        'send': 0,
        'wait': res.durationMs,
        'receive': 0,
      },
    };
  }

  static String _statusText(int code) {
    const texts = {
      200: 'OK',
      201: 'Created',
      204: 'No Content',
      301: 'Moved Permanently',
      302: 'Found',
      304: 'Not Modified',
      400: 'Bad Request',
      401: 'Unauthorized',
      403: 'Forbidden',
      404: 'Not Found',
      405: 'Method Not Allowed',
      408: 'Request Timeout',
      422: 'Unprocessable Entity',
      429: 'Too Many Requests',
      500: 'Internal Server Error',
      502: 'Bad Gateway',
      503: 'Service Unavailable',
      504: 'Gateway Timeout',
    };
    return texts[code] ?? '';
  }
}
