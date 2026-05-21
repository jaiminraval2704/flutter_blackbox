/// Snapshot of an outgoing HTTP request captured by a [BlackBoxHttpAdapter].
class NetworkRequest {
  const NetworkRequest({
    required this.id,
    required this.method,
    required this.url,
    required this.timestamp,
    this.headers = const {},
    this.body,
    this.queryParameters = const {},
    this.isReplay = false,
  });

  /// Unique identifier for the network request.
  final String id;

  /// HTTP method (e.g., 'GET', 'POST').
  final String method;

  /// The destination URL.
  final String url;

  /// When the request was initiated.
  final DateTime timestamp;

  /// HTTP request headers.
  final Map<String, dynamic> headers;

  /// Optional request body payload.
  final dynamic body;

  /// URL query parameters.
  final Map<String, String> queryParameters;

  /// Whether this request was replayed from the Network panel.
  final bool isReplay;

  Map<String, dynamic> toJson() => {
        'id': id,
        'method': method,
        'url': url,
        'timestamp': timestamp.toIso8601String(),
        'headers': headers,
        if (body != null) 'body': body,
        if (queryParameters.isNotEmpty) 'queryParameters': queryParameters,
        if (isReplay) 'isReplay': true,
      };
}
