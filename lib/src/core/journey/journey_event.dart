/// Base class for events captured in the user journey.
sealed class JourneyEvent {
  const JourneyEvent(this.timestamp);

  /// When the event occurred.
  final DateTime timestamp;

  /// Human-readable summary of the event.
  String get description;

  /// JSON-serialisable representation.
  Map<String, dynamic> toJson();
}

class AppLaunchEvent extends JourneyEvent {
  AppLaunchEvent(super.timestamp);

  @override
  String get description => 'App launched';

  @override
  Map<String, dynamic> toJson() => {
        'type': 'launch',
        'timestamp': timestamp.toIso8601String(),
      };
}

class RouteEvent extends JourneyEvent {
  RouteEvent(super.timestamp, {required this.route});
  final String route;

  @override
  String get description => 'Navigated to $route';

  @override
  Map<String, dynamic> toJson() => {
        'type': 'route',
        'route': route,
        'timestamp': timestamp.toIso8601String(),
      };
}

class TapEvent extends JourneyEvent {
  TapEvent(super.timestamp, {this.widgetKey, required this.location});
  final String? widgetKey;
  final String location;

  @override
  String get description =>
      'Tapped at $location${widgetKey != null ? ' ($widgetKey)' : ''}';

  @override
  Map<String, dynamic> toJson() => {
        'type': 'tap',
        'location': location,
        'widgetKey': widgetKey,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Represents an API call event in the user journey.
class ApiEvent extends JourneyEvent {
  /// Creates an [ApiEvent] with the given [timestamp], [method], [url], and [statusCode].
  ApiEvent(super.timestamp,
      {required this.method, required this.url, required this.statusCode});

  /// The HTTP method used for the API call (e.g., GET, POST).
  final String method;

  /// The URL of the API call.
  final String url;

  /// The HTTP status code returned by the API call.
  final int statusCode;

  @override
  String get description => 'API $method $url -> $statusCode';

  @override
  Map<String, dynamic> toJson() => {
        'type': 'api',
        'method': method,
        'url': url,
        'statusCode': statusCode,
        'timestamp': timestamp.toIso8601String(),
      };
}

class ErrorEvent extends JourneyEvent {
  ErrorEvent(super.timestamp, {required this.message});
  final String message;

  @override
  String get description => 'Error: $message';

  @override
  Map<String, dynamic> toJson() => {
        'type': 'error',
        'message': message,
        'timestamp': timestamp.toIso8601String(),
      };
}
