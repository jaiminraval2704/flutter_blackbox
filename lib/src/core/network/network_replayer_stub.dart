import 'network_request.dart';
import 'network_response.dart';

/// Web/WASM stub for network replay.
/// `dart:io` is unavailable on Web, so we can't use `HttpClient`.
class NetworkReplayerImpl {
  static Future<NetworkResponse> replay(NetworkRequest original) async {
    return NetworkResponse(
      requestId: 'replay_web_stub',
      statusCode: 0,
      headers: const {},
      body:
          'Network Replay is not currently supported on Web/WASM environments.',
      durationMs: 0,
      failureType: NetworkFailureType.connection,
    );
  }
}
