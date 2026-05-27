import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Offloads heavy JSON operations to a background isolate via [compute].
///
/// Only activates for payloads larger than [_kThresholdBytes] (50 KB).
/// Smaller payloads are processed synchronously to avoid isolate overhead.
class JsonIsolate {
  JsonIsolate._();

  /// Payloads smaller than this are processed synchronously.
  static const _kThresholdBytes = 50 * 1024; // 50 KB

  /// Pretty-prints a JSON [body] (Map, List, or JSON string).
  ///
  /// Returns a nicely indented JSON string for display. Falls back to
  /// [body.toString()] if the input is not valid JSON.
  static Future<String> prettyPrint(dynamic body) async {
    if (body == null) return 'null';

    final raw = body is String ? body : jsonEncode(body);

    if (raw.length < _kThresholdBytes) {
      return _prettyPrintSync(raw);
    }

    return compute(_prettyPrintSync, raw);
  }

  /// Synchronous pretty-print implementation (runs in isolate for large payloads).
  static String _prettyPrintSync(String raw) {
    try {
      final decoded = jsonDecode(raw);
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(decoded);
    } catch (_) {
      return raw;
    }
  }

  /// Decodes a JSON string in a background isolate if it's large.
  static Future<dynamic> decode(dynamic data) async {
    if (data is Map || data is List) return data;
    if (data is String) {
      if (data.length < _kThresholdBytes) {
        return _decodeSync(data);
      }
      return compute(_decodeSync, data);
    }
    return data;
  }

  static dynamic _decodeSync(String data) {
    try {
      return jsonDecode(data);
    } catch (_) {
      return data;
    }
  }

  /// Estimates the byte size of a body payload.
  static int estimateSize(dynamic body) {
    if (body == null) return 0;
    if (body is String) return body.length;
    try {
      return jsonEncode(body).length;
    } catch (_) {
      return body.toString().length;
    }
  }
}
