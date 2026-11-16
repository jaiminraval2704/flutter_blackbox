import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/capture/bounded_value.dart';
import '../core/report/blackbox_report.dart';

/// Streams BlackBox data to the companion web dashboard via the
/// Firebase Realtime Database **REST API**.
///
/// This approach uses zero native dependencies — only pure-Dart HTTP — so it
/// adds virtually nothing to the host app's binary size.
class FirebaseStreamer {
  static final FirebaseStreamer _instance = FirebaseStreamer._();
  static FirebaseStreamer get instance => _instance;

  FirebaseStreamer._() : _client = http.Client();

  @visibleForTesting
  FirebaseStreamer.test(http.Client client) : _client = client;

  /// Base URL for the Firebase Realtime Database.
  static const _databaseUrl =
      'https://flutter-blackbox-companion-default-rtdb.firebaseio.com';

  final http.Client _client;
  String? _sessionId;
  bool _isStreaming = false;
  String? _lastError;
  String? deviceName;
  Timer? _heartbeatTimer;
  Timer? _lastSeenTimer;
  VoidCallback? onConnectionLost;
  int? _checkingConnectionGeneration;
  int? _writingLastSeenGeneration;
  bool _isDrainingQueue = false;
  int _sessionGeneration = 0;
  int _queuedBytes = 0;
  int _droppedEventCount = 0;
  int _truncatedEventCount = 0;

  static const int _maxQueuedEvents = 100;
  static const int _maxQueuedBytes = 2 * 1024 * 1024;
  static const int _maxPayloadBytes = 100 * 1024;

  bool get isStreaming => _isStreaming;
  String? get sessionId => _sessionId;
  String? get lastError => _lastError;
  int get queuedBytes => _queuedBytes;
  int get droppedEventCount => _droppedEventCount;
  int get truncatedEventCount => _truncatedEventCount;

  void resetMetrics() {
    _droppedEventCount = 0;
    _truncatedEventCount = 0;
  }

  /// Starts streaming to the given [sessionId].
  ///
  /// Sets the session status to connected and begins a heartbeat that
  /// periodically checks whether the web companion is still alive.
  Future<void> start(String sessionId) async {
    if (!kDebugMode) return;
    if (_isStreaming) return;
    final generation = ++_sessionGeneration;
    try {
      _sessionId = sessionId;

      // Set connection status to true
      final statusUrl =
          Uri.parse('$_databaseUrl/sessions/$_sessionId/status.json');
      final response = await _client
          .put(
            statusUrl,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'connected': true,
              'lastSeen': DateTime.now().millisecondsSinceEpoch,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (generation != _sessionGeneration || _sessionId != sessionId) return;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
            'Failed to connect: HTTP ${response.statusCode} — ${response.body}');
      }

      _isStreaming = true;
      _lastError = null;
      debugPrint('🚀 BlackBox streaming to Firebase session: $_sessionId');

      // Start a heartbeat to detect if the web app disconnects
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _checkConnection(generation, sessionId),
      );

      // Write lastSeen timestamp every 3 seconds so the web companion
      // can detect when the device app dies unexpectedly.
      _lastSeenTimer?.cancel();
      _lastSeenTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _writeLastSeen(generation, sessionId),
      );
    } catch (e) {
      if (generation != _sessionGeneration) return;
      _sessionId = null;
      _lastError = e.toString();
      debugPrint('Failed to start Firebase Streamer: $e');
      rethrow;
    }
  }

  Future<void> _checkConnection(int generation, String sessionId) async {
    if (!_isCurrentSession(generation, sessionId) ||
        _checkingConnectionGeneration == generation) {
      return;
    }
    _checkingConnectionGeneration = generation;
    try {
      final statusUrl =
          Uri.parse('$_databaseUrl/sessions/$sessionId/status.json');
      final response =
          await _client.get(statusUrl).timeout(const Duration(seconds: 10));
      if (_isCurrentSession(generation, sessionId) &&
          response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['connected'] == false) {
          debugPrint('Web app disconnected. Stopping mobile streamer.');
          final callback = onConnectionLost;
          stop();
          callback?.call();
        } else {
          unawaited(_drainQueue(generation, sessionId));
        }
      }
    } catch (_) {
      // Silently ignore connectivity blips — the next tick will retry.
    } finally {
      if (_checkingConnectionGeneration == generation) {
        _checkingConnectionGeneration = null;
      }
    }
  }

  /// Writes a heartbeat timestamp to Firebase so the web companion
  /// can detect when the device app dies without calling stop().
  Future<void> _writeLastSeen(int generation, String sessionId) async {
    if (!_isCurrentSession(generation, sessionId) ||
        _writingLastSeenGeneration == generation) {
      return;
    }
    _writingLastSeenGeneration = generation;
    try {
      final statusUrl =
          Uri.parse('$_databaseUrl/sessions/$sessionId/status.json');
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
    } finally {
      if (_writingLastSeenGeneration == generation) {
        _writingLastSeenGeneration = null;
      }
    }
  }

  /// Stops streaming and marks the session as disconnected.
  void stop() {
    final sessionId = _sessionId;
    _sessionGeneration++;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _lastSeenTimer?.cancel();
    _lastSeenTimer = null;

    _isStreaming = false;
    _sessionId = null;
    _checkingConnectionGeneration = null;
    _writingLastSeenGeneration = null;
    _offlineQueue.clear();
    _queuedBytes = 0;

    if (sessionId != null) {
      final statusUrl =
          Uri.parse('$_databaseUrl/sessions/$sessionId/status.json');
      // Fire-and-forget — we don't await the disconnect write.
      _client
          .patch(
            statusUrl,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'connected': false}),
          )
          .catchError((_) => http.Response('', 500));
    }
  }

  final List<_QueuedEvent> _offlineQueue = [];

  /// Broadcasts data to the companion web dashboard under the given [type]
  /// node (e.g. `logs`, `network`, `crashes`, `navigation`, etc.).
  void broadcast(String type, Map<String, dynamic> data) {
    if (!kDebugMode) return;
    if (!_isStreaming || _sessionId == null) return;

    final snapshot = captureBoundedValue(
      data,
      maxBytes: _maxPayloadBytes - 512,
    );
    if (snapshot.truncated) _truncatedEventCount++;
    final safeData = snapshot.value is Map<String, Object?>
        ? snapshot.value as Map<String, Object?>
        : const <String, Object?>{};

    final payload = jsonEncode({
      ...safeData,
      'timestamp': DateTime.now().toIso8601String(),
      if (deviceName != null) 'deviceName': deviceName,
    });

    final payloadBytes = utf8.encode(payload).length;
    if (payloadBytes > _maxPayloadBytes) {
      _droppedEventCount++;
      return;
    }
    _enqueue(_QueuedEvent(type, payload, payloadBytes));
    unawaited(_drainQueue(_sessionGeneration, _sessionId!));
  }

  void _enqueue(_QueuedEvent event) {
    while (_offlineQueue.isNotEmpty &&
        (_offlineQueue.length >= _maxQueuedEvents ||
            _queuedBytes + event.bytes > _maxQueuedBytes)) {
      _queuedBytes -= _offlineQueue.removeAt(0).bytes;
      _droppedEventCount++;
    }
    _offlineQueue.add(event);
    _queuedBytes += event.bytes;
  }

  Future<void> _drainQueue(int generation, String sessionId) async {
    if (_isDrainingQueue || !_isCurrentSession(generation, sessionId)) return;
    _isDrainingQueue = true;
    try {
      while (_offlineQueue.isNotEmpty &&
          _isCurrentSession(generation, sessionId)) {
        final event = _offlineQueue.first;
        final url =
            Uri.parse('$_databaseUrl/sessions/$sessionId/${event.type}.json');
        try {
          final response = await _client
              .post(
                url,
                headers: {'Content-Type': 'application/json'},
                body: event.payload,
              )
              .timeout(const Duration(seconds: 10));
          if (!_isCurrentSession(generation, sessionId)) return;
          if (response.statusCode < 200 || response.statusCode >= 300) return;
          _offlineQueue.removeAt(0);
          _queuedBytes -= event.bytes;
        } catch (_) {
          return;
        }
      }
    } finally {
      _isDrainingQueue = false;
      final currentSession = _sessionId;
      if (generation != _sessionGeneration &&
          _isStreaming &&
          currentSession != null &&
          _offlineQueue.isNotEmpty) {
        unawaited(_drainQueue(_sessionGeneration, currentSession));
      }
    }
  }

  /// Uploads a generated QA report bundle to Firebase Realtime Database.
  ///
  /// Writes to both `reports/$reportId.json` and (if active)
  /// `sessions/$sessionId/reports/$reportId.json`.
  Future<String?> uploadReport(BlackBoxReport report) async {
    final reportId = DateTime.now().millisecondsSinceEpoch.toString();
    try {
      final payload = <String, dynamic>{
        'reportId': reportId,
        'sessionId': _sessionId,
        'title': report.bugTitle ?? 'QA Bug Report',
        'bugTitle': report.bugTitle ?? 'QA Bug Report',
        'severity': report.severity.name,
        'notes': report.notes ?? '',
        'createdAt': report.timestamp.toIso8601String(),
        'timestamp': report.timestamp.toIso8601String(),
        'appInfo': report.appInfo,
        'deviceInfo': report.deviceInfo.toJson(),
        'device': report.deviceInfo.toJson(),
        'socketEvents': report.socketEvents,
        'userJourney': report.userJourney,
        'navigationHistory':
            report.userJourney.map((step) => {'route': step}).toList(),
        'recentNetworkRequests': report.networkRequests.take(20).toList(),
        'networkRequests': report.networkRequests,
        'failedRequests': report.failedRequests,
        'recentLogs': report.logs.take(50).toList(),
        'logs': report.logs,
        'crashes': report.crashes,
      };

      if (report.screenshotPngBytes != null &&
          report.screenshotPngBytes!.isNotEmpty) {
        payload['screenshotBase64'] = base64Encode(report.screenshotPngBytes!);
        payload['hasScreenshot'] = true;
      }

      final jsonBody = jsonEncode(payload);

      // Write to global reports list
      final globalUrl = Uri.parse('$_databaseUrl/reports/$reportId.json');
      await _client
          .put(
            globalUrl,
            headers: {'Content-Type': 'application/json'},
            body: jsonBody,
          )
          .timeout(const Duration(seconds: 15));

      // If streaming, also attach directly to current session
      if (_sessionId != null) {
        final sessionUrl = Uri.parse(
            '$_databaseUrl/sessions/$_sessionId/reports/$reportId.json');
        await _client
            .put(
              sessionUrl,
              headers: {'Content-Type': 'application/json'},
              body: jsonBody,
            )
            .timeout(const Duration(seconds: 15));
      }

      return reportId;
    } catch (e) {
      debugPrint('[BlackBox] Failed to upload report to Firebase: $e');
      return null;
    }
  }

  bool _isCurrentSession(int generation, String sessionId) =>
      _isStreaming &&
      generation == _sessionGeneration &&
      _sessionId == sessionId;
}

class _QueuedEvent {
  final String type;
  final String payload;
  final int bytes;
  _QueuedEvent(this.type, this.payload, this.bytes);
}
