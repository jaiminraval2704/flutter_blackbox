import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Streams BlackBox data to the companion web dashboard via the
/// Firebase Realtime Database **REST API**.
///
/// This approach uses zero native dependencies — only pure-Dart HTTP — so it
/// adds virtually nothing to the host app's binary size.
class FirebaseStreamer {
  static final FirebaseStreamer _instance = FirebaseStreamer._();
  static FirebaseStreamer get instance => _instance;

  FirebaseStreamer._();

  /// Base URL for the Firebase Realtime Database.
  static const _databaseUrl =
      'https://flutter-blackbox-companion-default-rtdb.firebaseio.com';

  final http.Client _client = http.Client();
  String? _sessionId;
  bool _isStreaming = false;
  String? _lastError;
  String? deviceName;
  Timer? _heartbeatTimer;
  Timer? _lastSeenTimer;
  VoidCallback? onConnectionLost;

  bool get isStreaming => _isStreaming;
  String? get sessionId => _sessionId;
  String? get lastError => _lastError;

  /// Starts streaming to the given [sessionId].
  ///
  /// Sets the session status to connected and begins a heartbeat that
  /// periodically checks whether the web companion is still alive.
  Future<void> start(String sessionId) async {
    if (!kDebugMode) return;
    if (_isStreaming) return;
    try {
      _sessionId = sessionId;

      // Set connection status to true
      final statusUrl =
          Uri.parse('$_databaseUrl/sessions/$_sessionId/status.json');
      final response = await _client.put(
        statusUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'connected': true,
          'lastSeen': DateTime.now().millisecondsSinceEpoch,
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
            'Failed to connect: HTTP ${response.statusCode} — ${response.body}');
      }

      _isStreaming = true;
      _lastError = null;
      debugPrint('🚀 BlackBox streaming to Firebase session: $_sessionId');

      // Start a heartbeat to detect if the web app disconnects
      _heartbeatTimer?.cancel();
      _heartbeatTimer =
          Timer.periodic(const Duration(seconds: 5), (_) => _checkConnection());

      // Write lastSeen timestamp every 3 seconds so the web companion
      // can detect when the device app dies unexpectedly.
      _lastSeenTimer?.cancel();
      _lastSeenTimer =
          Timer.periodic(const Duration(seconds: 3), (_) => _writeLastSeen());
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Failed to start Firebase Streamer: $e');
      rethrow;
    }
  }

  Future<void> _checkConnection() async {
    if (!_isStreaming || _sessionId == null) return;
    try {
      final statusUrl =
          Uri.parse('$_databaseUrl/sessions/$_sessionId/status.json');
      final response =
          await _client.get(statusUrl).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['connected'] == false) {
          debugPrint('Web app disconnected. Stopping mobile streamer.');
          stop();
          onConnectionLost?.call();
        } else {
          if (_offlineQueue.isNotEmpty && !_isFlushingQueue) {
            _flushQueue();
          }
        }
      }
    } catch (_) {
      // Silently ignore connectivity blips — the next tick will retry.
    }
  }

  /// Writes a heartbeat timestamp to Firebase so the web companion
  /// can detect when the device app dies without calling stop().
  Future<void> _writeLastSeen() async {
    if (!_isStreaming || _sessionId == null) return;
    try {
      final statusUrl =
          Uri.parse('$_databaseUrl/sessions/$_sessionId/status.json');
      await _client
          .patch(
            statusUrl,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'lastSeen': DateTime.now().millisecondsSinceEpoch,
            }),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Silently ignore — next tick will retry.
    }
  }

  /// Stops streaming and marks the session as disconnected.
  void stop() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _lastSeenTimer?.cancel();
    _lastSeenTimer = null;

    if (_sessionId != null) {
      final statusUrl =
          Uri.parse('$_databaseUrl/sessions/$_sessionId/status.json');
      // Fire-and-forget — we don't await the disconnect write.
      _client
          .put(
            statusUrl,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'connected': false}),
          )
          .catchError((_) => http.Response('', 500));
    }
    _isStreaming = false;
    _sessionId = null;
  }

  final List<_QueuedEvent> _offlineQueue = [];
  bool _isFlushingQueue = false;

  /// Broadcasts data to the companion web dashboard under the given [type]
  /// node (e.g. `logs`, `network`, `crashes`, `navigation`, etc.).
  void broadcast(String type, Map<String, dynamic> data) {
    if (!kDebugMode) return;
    if (!_isStreaming || _sessionId == null) return;

    final safeData = _sanitize(data);

    final payload = jsonEncode({
      ...safeData as Map<String, dynamic>,
      'timestamp': DateTime.now().toIso8601String(),
      if (deviceName != null) 'deviceName': deviceName,
    });

    _sendOrQueue(type, payload);
  }

  Future<void> _sendOrQueue(String type, String payload) async {
    final url = Uri.parse('$_databaseUrl/sessions/$_sessionId/$type.json');
    try {
      final response = await _client
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: payload,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (_offlineQueue.isNotEmpty && !_isFlushingQueue) {
          _flushQueue();
        }
      } else {
        if (_offlineQueue.length < 1000) {
          _offlineQueue.add(_QueuedEvent(type, payload));
        }
      }
    } catch (_) {
      if (_offlineQueue.length < 1000) {
        _offlineQueue.add(_QueuedEvent(type, payload));
      }
    }
  }

  Future<void> _flushQueue() async {
    if (_isFlushingQueue) return;
    _isFlushingQueue = true;

    final queueCopy = List.of(_offlineQueue);
    _offlineQueue.clear();

    for (final event in queueCopy) {
      if (!_isStreaming) break;
      await _sendOrQueue(event.type, event.payload);
    }

    _isFlushingQueue = false;
  }

  dynamic _sanitize(dynamic value) {
    if (value == null) return null;
    if (value is String || value is num || value is bool) return value;
    if (value is List) {
      return value.map((e) => _sanitize(e)).toList();
    }
    if (value is Map) {
      final sanitized = <String, dynamic>{};
      value.forEach((k, v) {
        if (k is String) {
          sanitized[k] = _sanitize(v);
        } else {
          sanitized[k.toString()] = _sanitize(v);
        }
      });
      return sanitized;
    }
    return value.toString();
  }
}

class _QueuedEvent {
  final String type;
  final String payload;
  _QueuedEvent(this.type, this.payload);
}
