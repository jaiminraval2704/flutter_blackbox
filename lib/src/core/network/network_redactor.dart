import 'dart:convert';

/// Automatically masks sensitive fields in network request/response data.
///
/// Used by [NetworkStore] to redact headers and body payloads before
/// they are stored and displayed in the Network panel.
///
/// ```dart
/// BlackBox.setup(
///   redactSensitiveData: true, // enabled by default
/// );
/// ```
///
/// To customise which fields are redacted, pass a [NetworkRedactor]:
///
/// ```dart
/// BlackBox.setup(
///   networkRedactor: NetworkRedactor(
///     sensitiveHeaders: [
///       ...NetworkRedactor.defaultSensitiveHeaders,
///       'x-custom-secret',
///     ],
///   ),
/// );
/// ```
class NetworkRedactor {
  /// Creates a redactor with configurable sensitive patterns.
  NetworkRedactor({
    this.sensitiveHeaders = defaultSensitiveHeaders,
    this.sensitiveBodyFields = defaultSensitiveBodyFields,
  })  : _lowerHeaders = sensitiveHeaders.map((h) => h.toLowerCase()).toSet(),
        _lowerBodyFields =
            sensitiveBodyFields.map((f) => f.toLowerCase()).toSet();

  /// Placeholder shown in place of redacted values.
  static const redactedPlaceholder = '••••••••';

  /// Default header names whose values are masked (case-insensitive).
  static const defaultSensitiveHeaders = <String>[
    'authorization',
    'x-api-key',
    'cookie',
    'set-cookie',
    'proxy-authorization',
    'x-auth-token',
    'x-access-token',
    'x-refresh-token',
  ];

  /// Default body field names whose values are masked (case-insensitive).
  static const defaultSensitiveBodyFields = <String>[
    'password',
    'passwd',
    'pass',
    'secret',
    'token',
    'access_token',
    'refresh_token',
    'api_key',
    'apikey',
    'authorization',
    'credit_card',
    'card_number',
    'cvv',
    'cvc',
    'ssn',
    'pin',
    'otp',
    'private_key',
    'client_secret',
  ];

  /// Header names to redact (case-insensitive).
  final List<String> sensitiveHeaders;

  /// Body field names to redact (case-insensitive).
  final List<String> sensitiveBodyFields;

  /// Cached lowercase sets for O(1) lookups.
  final Set<String> _lowerHeaders;
  final Set<String> _lowerBodyFields;

  // ── Public API ──────────────────────────────────────────────────────

  /// Returns a copy of [headers] with sensitive values replaced.
  Map<String, dynamic> redactHeaders(Map<String, dynamic> headers) {
    if (headers.isEmpty) return headers;
    final result = <String, dynamic>{};
    for (final entry in headers.entries) {
      if (_lowerHeaders.contains(entry.key.toLowerCase())) {
        result[entry.key] = redactedPlaceholder;
      } else {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  /// Recursively walks [body] (Map/List/JSON string) and redacts
  /// sensitive field values.
  ///
  /// Non-Map/List values are returned unchanged.
  dynamic redactBody(dynamic body) {
    if (body == null) return null;
    if (body is Map) return _redactMap(body);
    if (body is List) return body.map(redactBody).toList();
    if (body is String) return _tryRedactJsonString(body);
    return body;
  }

  // ── Private ─────────────────────────────────────────────────────────

  Map<String, dynamic> _redactMap(Map<dynamic, dynamic> map) {
    final result = <String, dynamic>{};
    for (final entry in map.entries) {
      final key = entry.key.toString();
      if (_lowerBodyFields.contains(key.toLowerCase())) {
        result[key] = redactedPlaceholder;
      } else if (entry.value is Map) {
        result[key] = _redactMap(entry.value as Map);
      } else if (entry.value is List) {
        result[key] = (entry.value as List).map(redactBody).toList();
      } else {
        result[key] = entry.value;
      }
    }
    return result;
  }

  /// If [s] looks like a JSON object or array, decode → redact → re-encode.
  /// Otherwise return as-is.
  String _tryRedactJsonString(String s) {
    if (s.isEmpty) return s;
    final trimmed = s.trimLeft();
    if (trimmed.isEmpty || (trimmed[0] != '{' && trimmed[0] != '[')) {
      return s;
    }
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map || decoded is List) {
        final redacted = redactBody(decoded);
        return jsonEncode(redacted);
      }
    } catch (_) {
      // Not valid JSON — return as-is
    }
    return s;
  }
}
