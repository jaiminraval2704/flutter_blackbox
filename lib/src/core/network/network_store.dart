import 'dart:async';
import 'dart:collection';

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
  NetworkStore({this.capacity = 50, this.redactor});

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

  /// Called by [BlackBoxHttpAdapter] when a request is dispatched.
  void onRequest(NetworkRequest request) {
    if (_entries.length >= capacity) {
      final removed = _entries.removeFirst();
      _index.remove(removed.request.id);
    }

    // Redact sensitive fields before storing
    final storedRequest = redactor != null
        ? NetworkRequest(
            id: request.id,
            method: request.method,
            url: request.url,
            timestamp: request.timestamp,
            headers: redactor!.redactHeaders(request.headers),
            body: redactor!.redactBody(request.body),
            queryParameters: request.queryParameters,
            isReplay: request.isReplay,
          )
        : request;

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
      // Redact response body before storing
      if (redactor != null) {
        entry.response = NetworkResponse(
          requestId: response.requestId,
          statusCode: response.statusCode,
          headers: response.headers,
          body: redactor!.redactBody(response.body),
          durationMs: response.durationMs,
          failureType: response.failureType,
          responseSizeBytes: response.responseSizeBytes,
        );
      } else {
        entry.response = response;
      }
      _invalidateAndNotify();
    }
  }

  void clear() {
    _entries.clear();
    _index.clear();
    _invalidateAndNotify();
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
