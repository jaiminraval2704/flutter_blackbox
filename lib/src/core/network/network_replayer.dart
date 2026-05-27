import 'network_request.dart';
import 'network_response.dart';

import 'network_replayer_stub.dart'
    if (dart.library.io) 'network_replayer_impl.dart';

/// Replays a previously captured [NetworkRequest].
///
/// The replayed request is automatically logged into the
/// [BlackBox.instance.networkStore] as a new entry with [isReplay] = true.
///
/// > **Note**: This bypasses any Dio/http interceptors or auth-refresh
/// > logic the app may have configured. It fires the raw request as
/// > originally captured.
class NetworkReplayer {
  NetworkReplayer._();

  /// Re-fires the exact same HTTP request and logs the result.
  ///
  /// Returns the [NetworkResponse] from the replayed call.
  static Future<NetworkResponse> replay(NetworkRequest original) {
    return NetworkReplayerImpl.replay(original);
  }
}
