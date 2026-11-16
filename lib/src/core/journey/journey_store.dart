import 'dart:collection';

import '../capture/bounded_value.dart';
import 'journey_event.dart';

/// Records a sequence of user actions and navigation events.
class JourneyStore {
  /// Creates a journey store with a fixed [capacity].
  JourneyStore({this.capacity = 50});

  /// Maximum number of journey events to retain.
  final int capacity;

  final _events = ListQueue<JourneyEvent>();
  int _droppedEntryCount = 0;
  int _truncatedPayloadCount = 0;
  int _retainedBytes = 0;

  /// Unmodifiable list of all recorded journey events.
  List<JourneyEvent> get events => _events.toList(growable: false);

  int get droppedEntryCount => _droppedEntryCount;
  int get truncatedPayloadCount => _truncatedPayloadCount;
  int get approximateRetainedBytes => _retainedBytes;

  List<String> get numberedSteps {
    return _events.toList().asMap().entries.map((e) {
      final index = e.key + 1;
      return '$index. ${e.value.description}';
    }).toList();
  }

  void record(JourneyEvent event) {
    event = _captureEvent(event);
    if (_events.length >= capacity) {
      _retainedBytes -= _events.removeFirst().description.length * 2;
      _droppedEntryCount++;
    }
    _events.addLast(event);
    _retainedBytes += event.description.length * 2;
  }

  void clear() {
    _events.clear();
    _droppedEntryCount = 0;
    _truncatedPayloadCount = 0;
    _retainedBytes = 0;
  }

  JourneyEvent _captureEvent(JourneyEvent event) {
    String bounded(String value, int maxBytes) {
      final captured = captureBoundedString(value, maxBytes: maxBytes);
      if (captured != value) _truncatedPayloadCount++;
      return captured;
    }

    if (event is RouteEvent) {
      return RouteEvent(
        event.timestamp,
        route: bounded(event.route, 8 * 1024),
      );
    }
    if (event is TapEvent) {
      return TapEvent(
        event.timestamp,
        widgetKey: event.widgetKey == null
            ? null
            : bounded(event.widgetKey!, 4 * 1024),
        location: bounded(event.location, 4 * 1024),
      );
    }
    if (event is ApiEvent) {
      return ApiEvent(
        event.timestamp,
        method: bounded(event.method, 1024),
        url: bounded(event.url, 32 * 1024),
        statusCode: event.statusCode,
      );
    }
    if (event is ErrorEvent) {
      return ErrorEvent(
        event.timestamp,
        message: bounded(event.message, 64 * 1024),
      );
    }
    return event;
  }
}
