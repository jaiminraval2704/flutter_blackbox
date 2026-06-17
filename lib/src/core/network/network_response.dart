/// Categories for network failures.
enum NetworkFailureType { none, timeout, connection, server, format }

/// Snapshot of an HTTP response (or error) paired with its request.
class NetworkResponse {
  NetworkResponse({
    required this.requestId,
    this.statusCode = 0,
    required this.headers,
    this.body,
    required this.durationMs,
    this.failureType = NetworkFailureType.none,
    this.responseSizeBytes,
    this.dnsMs,
    this.connectMs,
    this.ttfbMs,
    this.downloadMs,
  });

  /// The ID of the originating [NetworkRequest].
  final String requestId;

  /// HTTP status code (e.g., 200, 404).
  final int statusCode;

  /// HTTP response headers.
  final Map<String, String> headers;

  /// Optional response body.
  final dynamic body;

  /// Time taken for the request to complete in milliseconds.
  final int durationMs;

  /// Type of failure if the request didn't complete successfully.
  final NetworkFailureType failureType;

  /// Total size of the response body in bytes.
  final int? responseSizeBytes;

  /// DNS lookup time in milliseconds.
  final int? dnsMs;

  /// TCP/TLS connection time in milliseconds.
  final int? connectMs;

  /// Time to first byte (server processing time) in milliseconds.
  final int? ttfbMs;

  /// Content download time in milliseconds.
  final int? downloadMs;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
  bool get isClientError => statusCode >= 400 && statusCode < 500;
  bool get isServerError => statusCode >= 500;

  /// Human-readable response size.
  String get formattedSize {
    if (responseSizeBytes == null) return '';
    final bytes = responseSizeBytes!;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Map<String, dynamic> toJson() => {
        'requestId': requestId,
        'statusCode': statusCode,
        'headers': headers,
        if (body != null) 'body': body,
        'durationMs': durationMs,
        'failureType': failureType.name,
        if (responseSizeBytes != null) 'responseSizeBytes': responseSizeBytes,
        if (dnsMs != null) 'dnsMs': dnsMs,
        if (connectMs != null) 'connectMs': connectMs,
        if (ttfbMs != null) 'ttfbMs': ttfbMs,
        if (downloadMs != null) 'downloadMs': downloadMs,
      };
}
