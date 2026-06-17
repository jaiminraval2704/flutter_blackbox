import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'network_redactor.dart';
import 'network_request.dart';
import 'network_response.dart';

/// Paired request/response record displayed in the network panel.
class NetworkEntry {
  NetworkEntry({required this.request}) : response = null;

  final NetworkRequest request;
  NetworkResponse? response;

  bool get isPending => response == null;
  int get durationMs => response?.durationMs ?? 0;
}

/// Stores the last [capacity] network entries and exposes them as a
/// broadcast [Stream].
class NetworkStore {
  NetworkStore({this.capacity = 500, this.redactor});

  final int capacity;

  /// Optional redactor for sanitising sensitive data before storage.
  final NetworkRedactor? redactor;

  final _entries = ListQueue<NetworkEntry>();
  final _index = <String, NetworkEntry>{};
  final _controller = StreamController<List<NetworkEntry>>.broadcast();

  // Cached snapshot — invalidated on mutation.
  List<NetworkEntry>? _cachedEntries;

  // ── Public API ──────────────────────────────────────────────────────

  /// Unmodifiable list of all entries. Cached until the next mutation.
  List<NetworkEntry> get entries =>
      _cachedEntries ??= List.unmodifiable(_entries);

  Stream<List<NetworkEntry>> get stream => _controller.stream;

  static const int _maxBodyBytes = 100 * 1024; // 100 KB limit

  String? _truncateBody(dynamic body) {
    if (body == null) return null;

    String bodyStr;
    if (body is String) {
      bodyStr = body;
    } else {
      try {
        bodyStr = jsonEncode(body);
      } catch (_) {
        bodyStr = body.toString();
      }
    }

    if (bodyStr.length > _maxBodyBytes) {
      return '${bodyStr.substring(0, _maxBodyBytes)}\n\n... [TRUNCATED - EXCEEDS 100KB]';
    }
    return bodyStr;
  }

  /// Called by [BlackBoxHttpAdapter] when a request is dispatched.
  void onRequest(NetworkRequest request) {
    if (_entries.length >= capacity) {
      final removed = _entries.removeFirst();
      _index.remove(removed.request.id);
    }

    // Redact and truncate before storing
    final storedRequest = NetworkRequest(
      id: request.id,
      method: request.method,
      url: request.url,
      timestamp: request.timestamp,
      headers: redactor?.redactHeaders(request.headers) ?? request.headers,
      body: _truncateBody(redactor?.redactBody(request.body) ?? request.body),
      queryParameters: request.queryParameters,
      isReplay: request.isReplay,
    );

    final entry = NetworkEntry(request: storedRequest);
    _entries.addLast(entry);
    _index[request.id] = entry;
    _invalidateAndNotify();
  }

  /// Called by [BlackBoxHttpAdapter] when a response arrives.
  /// Uses O(1) map lookup instead of linear scan.
  void onResponse(NetworkResponse response) {
    final entry = _index[response.requestId];
    if (entry != null) {
      entry.response = NetworkResponse(
        requestId: response.requestId,
        statusCode: response.statusCode,
        headers: response.headers,
        body:
            _truncateBody(redactor?.redactBody(response.body) ?? response.body),
        durationMs: response.durationMs,
        failureType: response.failureType,
        responseSizeBytes: response.responseSizeBytes,
        dnsMs: response.dnsMs,
        connectMs: response.connectMs,
        ttfbMs: response.ttfbMs,
        downloadMs: response.downloadMs,
      );
      _invalidateAndNotify();
    }
  }

  void clear() {
    _entries.clear();
    _index.clear();
    _invalidateAndNotify();
  }

  /// Remove a single entry by its request ID.
  void remove(String requestId) {
    final entry = _index.remove(requestId);
    if (entry != null) {
      _entries.remove(entry);
      _invalidateAndNotify();
    }
  }

  List<Map<String, dynamic>> toJson() => _entries
      .map((e) => {
            'request': e.request.toJson(),
            if (e.response != null) 'response': e.response!.toJson(),
          })
      .toList();

  void dispose() {
    _throttleTimer?.cancel();
    _controller.close();
  }

  // ── Private ─────────────────────────────────────────────────────────

  Timer? _throttleTimer;

  void _invalidateAndNotify() {
    _cachedEntries = null;
    if (_controller.isClosed) return;
    if (_throttleTimer?.isActive ?? false) return;

    _throttleTimer = Timer(const Duration(milliseconds: 250), () {
      if (!_controller.isClosed) {
        _controller.add(entries);
      }
    });
  }
}
