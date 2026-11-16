import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import '../capture/bounded_value.dart';
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
  NetworkRedactor? redactor;

  final _entries = ListQueue<NetworkEntry>();
  final _index = <String, NetworkEntry>{};
  final _controller = StreamController<List<NetworkEntry>>.broadcast();
  final _completedController =
      StreamController<NetworkEntry>.broadcast(sync: true);

  // Cached snapshot — invalidated on mutation.
  List<NetworkEntry>? _cachedEntries;
  int _droppedEntryCount = 0;
  int _truncatedPayloadCount = 0;
  int _retainedBytes = 0;

  // ── Public API ──────────────────────────────────────────────────────

  /// Unmodifiable list of all entries. Cached until the next mutation.
  List<NetworkEntry> get entries =>
      _cachedEntries ??= List.unmodifiable(_entries);

  Stream<List<NetworkEntry>> get stream => _controller.stream;

  /// Emits every completed request exactly once. Unlike [stream], this is not
  /// throttled and is intended for observers rather than UI rebuilding.
  Stream<NetworkEntry> get completedStream => _completedController.stream;

  int get droppedEntryCount => _droppedEntryCount;
  int get truncatedPayloadCount => _truncatedPayloadCount;
  int get approximateRetainedBytes => _retainedBytes;

  static const int _maxBodyBytes = 100 * 1024; // 100 KB limit

  String? _truncateBody(dynamic body) {
    if (body == null) return null;
    var snapshot = captureBoundedValue(body, maxBytes: _maxBodyBytes);
    var wasTruncated = snapshot.truncated;
    var safeValue = redactor?.redactBody(snapshot.value) ?? snapshot.value;
    var encoded = safeValue is String ? safeValue : jsonEncode(safeValue);

    if (utf8.encode(encoded).length > _maxBodyBytes) {
      // JSON escaping can expand a bounded object (for example, many control
      // characters). Re-capture only the already-detached snapshot at a
      // conservative budget; the original large graph is never serialized.
      snapshot = captureBoundedValue(
        snapshot.value,
        maxBytes: (_maxBodyBytes - 1024) ~/ 6,
      );
      wasTruncated = true;
      safeValue = redactor?.redactBody(snapshot.value) ?? snapshot.value;
      encoded = safeValue is String ? safeValue : jsonEncode(safeValue);
      if (utf8.encode(encoded).length > _maxBodyBytes) {
        encoded = jsonEncode(captureBoundedString(
          encoded,
          maxBytes: (_maxBodyBytes - 2) ~/ 6,
        ));
      }
    }
    if (wasTruncated) _truncatedPayloadCount++;
    return encoded;
  }

  /// Called by [BlackBoxHttpAdapter] when a request is dispatched.
  void onRequest(NetworkRequest request) {
    if (_entries.length >= capacity) {
      final removed = _entries.removeFirst();
      _retainedBytes -= _estimate(removed);
      if (_retainedBytes < 0) _retainedBytes = 0;
      _index.remove(removed.request.id);
      _droppedEntryCount++;
    }

    final headerSnapshot =
        captureBoundedValue(request.headers, maxBytes: 32 * 1024);
    if (headerSnapshot.truncated) _truncatedPayloadCount++;
    final capturedHeaders = headerSnapshot.value is Map<String, Object?>
        ? Map<String, dynamic>.from(headerSnapshot.value as Map)
        : <String, dynamic>{};
    final capturedMethod = captureBoundedString(request.method, maxBytes: 1024);
    final capturedUrl = captureBoundedString(request.url, maxBytes: 32 * 1024);
    if (capturedMethod != request.method || capturedUrl != request.url) {
      _truncatedPayloadCount++;
    }

    // Redact and truncate before storing.
    final storedRequest = NetworkRequest(
      id: request.id,
      method: capturedMethod,
      url: capturedUrl,
      timestamp: request.timestamp,
      headers: Map.unmodifiable(
        redactor?.redactHeaders(capturedHeaders) ?? capturedHeaders,
      ),
      body: _truncateBody(request.body),
      queryParameters: _captureStringMap(request.queryParameters, 16 * 1024),
      isReplay: request.isReplay,
    );

    final entry = NetworkEntry(request: storedRequest);
    _entries.addLast(entry);
    _retainedBytes += _estimate(entry);
    _index[request.id] = entry;
    _invalidateAndNotify();
  }

  /// Called by [BlackBoxHttpAdapter] when a response arrives.
  /// Uses O(1) map lookup instead of linear scan.
  void onResponse(NetworkResponse response) {
    final entry = _index[response.requestId];
    if (entry != null) {
      final wasPending = entry.isPending;
      _retainedBytes -= _estimate(entry);
      if (_retainedBytes < 0) _retainedBytes = 0;
      entry.response = NetworkResponse(
        requestId: response.requestId,
        statusCode: response.statusCode,
        headers: _captureStringMap(response.headers, 32 * 1024),
        body: _truncateBody(response.body),
        durationMs: response.durationMs,
        failureType: response.failureType,
        responseSizeBytes: response.responseSizeBytes,
        dnsMs: response.dnsMs,
        connectMs: response.connectMs,
        ttfbMs: response.ttfbMs,
        downloadMs: response.downloadMs,
      );
      _retainedBytes += _estimate(entry);
      if (wasPending && !_completedController.isClosed) {
        _completedController.add(entry);
      }
      _invalidateAndNotify();
    }
  }

  bool containsRequest(String requestId) => _index.containsKey(requestId);

  Map<String, String> _captureStringMap(
    Map<String, String> source,
    int maxBytes,
  ) {
    final snapshot = captureBoundedValue(source, maxBytes: maxBytes);
    if (snapshot.truncated) _truncatedPayloadCount++;
    final value = snapshot.value;
    if (value is! Map) return const {};
    return Map.unmodifiable(
      value.map((key, value) => MapEntry(key.toString(), value.toString())),
    );
  }

  /// Clears captured data while preserving this store's stream identity.
  void clear({bool notify = true}) {
    _reset(redactor: redactor, notify: notify);
  }

  /// Updates capture configuration without replacing the store instance.
  void reconfigure({NetworkRedactor? redactor, bool notify = true}) {
    _reset(redactor: redactor, notify: notify);
  }

  void _reset({required NetworkRedactor? redactor, required bool notify}) {
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _entries.clear();
    _retainedBytes = 0;
    _index.clear();
    _cachedEntries = null;
    _droppedEntryCount = 0;
    _truncatedPayloadCount = 0;
    this.redactor = redactor;
    if (notify && !_controller.isClosed) {
      _controller.add(entries);
    }
  }

  /// Remove a single entry by its request ID.
  void remove(String requestId) {
    final entry = _index.remove(requestId);
    if (entry != null) {
      _entries.remove(entry);
      _retainedBytes -= _estimate(entry);
      if (_retainedBytes < 0) _retainedBytes = 0;
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
    _completedController.close();
  }

  // ── Private ─────────────────────────────────────────────────────────

  Timer? _throttleTimer;

  int _estimate(NetworkEntry entry) =>
      (entry.request.url.length +
          entry.request.method.length +
          entry.request.headers.toString().length +
          entry.request.queryParameters.toString().length +
          (entry.request.body?.toString().length ?? 0) +
          (entry.response?.headers.toString().length ?? 0) +
          (entry.response?.body?.toString().length ?? 0)) *
      2;

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
