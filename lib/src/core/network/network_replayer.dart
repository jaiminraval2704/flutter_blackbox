import 'dart:convert';
import 'dart:io';

import '../../blackbox.dart';
import 'network_request.dart';
import 'network_response.dart';

/// Replays a previously captured [NetworkRequest] using `dart:io`'s
/// [HttpClient].
///
/// The replayed request is automatically logged into the
/// [BlackBox.instance.networkStore] as a new entry with [isReplay] = true.
///
/// > **Note**: This bypasses any Dio/http interceptors or auth-refresh
/// > logic the app may have configured. It fires the raw request as
/// > originally captured.
class NetworkReplayer {
  NetworkReplayer._();

  static int _replayCounter = 0;

  /// Re-fires the exact same HTTP request and logs the result.
  ///
  /// Returns the [NetworkResponse] from the replayed call.
  static Future<NetworkResponse> replay(NetworkRequest original) async {
    final replayId = 'replay_${_replayCounter++}';
    final sw = Stopwatch()..start();

    // Build a replayed NetworkRequest for the store
    final replayRequest = NetworkRequest(
      id: replayId,
      method: original.method,
      url: original.url,
      timestamp: DateTime.now(),
      headers: original.headers,
      body: original.body,
      queryParameters: original.queryParameters,
      isReplay: true,
    );

    // Log the outgoing request
    BlackBox.instance.networkStore.onRequest(replayRequest);

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);

    try {
      final uri = Uri.parse(original.url);
      final ioRequest = await client.openUrl(original.method, uri);

      // Copy original headers
      original.headers.forEach((key, value) {
        // Skip pseudo-headers and content-length (set by body write)
        if (key.toLowerCase() == 'content-length') return;
        if (key.toLowerCase() == 'host') return;
        ioRequest.headers.set(key, value.toString());
      });

      // Write body if present
      if (original.body != null) {
        String bodyStr;
        if (original.body is String) {
          bodyStr = original.body as String;
        } else {
          try {
            bodyStr = jsonEncode(original.body);
          } catch (_) {
            bodyStr = original.body.toString();
          }
        }
        ioRequest.headers
            .set('content-type', 'application/json; charset=utf-8');
        ioRequest.write(bodyStr);
      }

      final ioResponse = await ioRequest.close();
      sw.stop();

      // Read response body
      final responseBytes = await ioResponse.fold<List<int>>(
        <int>[],
        (prev, chunk) => prev..addAll(chunk),
      );
      final responseBody = utf8.decode(responseBytes, allowMalformed: true);

      // Parse response body as JSON if possible
      dynamic parsedBody;
      try {
        parsedBody = jsonDecode(responseBody);
      } catch (_) {
        parsedBody = responseBody;
      }

      // Collect response headers
      final responseHeaders = <String, String>{};
      ioResponse.headers.forEach((name, values) {
        responseHeaders[name] = values.join(', ');
      });

      final response = NetworkResponse(
        requestId: replayId,
        statusCode: ioResponse.statusCode,
        headers: responseHeaders,
        body: parsedBody,
        durationMs: sw.elapsedMilliseconds,
        responseSizeBytes: responseBytes.length,
      );

      BlackBox.instance.networkStore.onResponse(response);

      return response;
    } on SocketException catch (e) {
      sw.stop();
      final response = NetworkResponse(
        requestId: replayId,
        statusCode: 0,
        headers: const {},
        body: 'Connection error: ${e.message}',
        durationMs: sw.elapsedMilliseconds,
        failureType: NetworkFailureType.connection,
      );
      BlackBox.instance.networkStore.onResponse(response);
      return response;
    } on HttpException catch (e) {
      sw.stop();
      final response = NetworkResponse(
        requestId: replayId,
        statusCode: 0,
        headers: const {},
        body: 'HTTP error: ${e.message}',
        durationMs: sw.elapsedMilliseconds,
        failureType: NetworkFailureType.server,
      );
      BlackBox.instance.networkStore.onResponse(response);
      return response;
    } catch (e) {
      sw.stop();
      final response = NetworkResponse(
        requestId: replayId,
        statusCode: 0,
        headers: const {},
        body: 'Replay error: $e',
        durationMs: sw.elapsedMilliseconds,
        failureType: NetworkFailureType.connection,
      );
      BlackBox.instance.networkStore.onResponse(response);
      return response;
    } finally {
      client.close(force: false);
    }
  }
}
