import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class CompanionServer {
  static final CompanionServer _instance = CompanionServer._();
  static CompanionServer get instance => _instance;

  CompanionServer._();

  HttpServer? _server;
  final List<WebSocket> _clients = [];

  bool get isRunning => _server != null;

  Future<void> start({int port = 8080}) async {
    if (isRunning) return;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      debugPrint('🚀 BlackBox Companion Server started on port $port');

      _server!.listen((HttpRequest request) async {
        if (request.uri.path == '/ws') {
          try {
            final socket = await WebSocketTransformer.upgrade(request);
            _clients.add(socket);
            debugPrint('📱 Companion Web App connected!');

            socket.listen(
              (message) {},
              onDone: () => _clients.remove(socket),
              onError: (e) => _clients.remove(socket),
            );
          } catch (e) {
            debugPrint('WebSocket upgrade failed: $e');
          }
        } else {
          // Serve simple HTML indicating the server is running
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.html
            ..write(
                '<html><body><h1>BlackBox Companion Server</h1><p>Running on port $port</p></body></html>');
          await request.response.close();
        }
      });
    } catch (e) {
      debugPrint('Failed to start Companion Server: $e');
    }
  }

  void stop() {
    _server?.close(force: true);
    for (final client in _clients) {
      client.close();
    }
    _clients.clear();
    _server = null;
  }

  void broadcast(String type, Map<String, dynamic> data) {
    if (_clients.isEmpty) return;
    final payload = jsonEncode({
      'type': type,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    });
    for (final client in _clients) {
      client.add(payload);
    }
  }
}
