import 'dart:async';
import 'dart:collection';

import '../capture/bounded_value.dart';
import 'socket_event.dart';

/// Manages the history of Socket.IO events.
class SocketStore {
  /// Creates a store with a fixed [capacity].
  SocketStore({this.capacity = 100});

  /// Maximum number of events to retain in memory.
  final int capacity;

  final _events = ListQueue<SocketEvent>();
  final _controller = StreamController<List<SocketEvent>>.broadcast();
  List<SocketEvent>? _cachedEvents;
  int _droppedEntryCount = 0;
  int _truncatedPayloadCount = 0;
  int _retainedBytes = 0;

  /// Unmodifiable list of all recorded socket events.
  List<SocketEvent> get events => _cachedEvents ??= List.unmodifiable(_events);

  /// Broadcast stream of the event list, throttled to 250ms.
  Stream<List<SocketEvent>> get stream => _controller.stream;

  int get droppedEntryCount => _droppedEntryCount;
  int get truncatedPayloadCount => _truncatedPayloadCount;
  int get approximateRetainedBytes => _retainedBytes;

  void onEvent(SocketEvent event) {
    final data = captureBoundedValue(event.data, maxBytes: 64 * 1024);
    final eventName = captureBoundedString(event.eventName, maxBytes: 4 * 1024);
    if (data.truncated || eventName != event.eventName) {
      _truncatedPayloadCount++;
    }
    if (_events.length >= capacity) {
      _retainedBytes -= _estimate(_events.removeFirst());
      _droppedEntryCount++;
    }
    final capturedEvent = SocketEvent(
      id: event.id,
      eventName: eventName,
      data: data.value,
      timestamp: event.timestamp,
      direction: event.direction,
    );
    _events.addLast(capturedEvent);
    _retainedBytes += _estimate(capturedEvent);
    _invalidateAndNotify();
  }

  void clear({bool notify = true}) {
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _events.clear();
    _retainedBytes = 0;
    _cachedEvents = null;
    _droppedEntryCount = 0;
    _truncatedPayloadCount = 0;
    if (notify && !_controller.isClosed) {
      _controller.add(events);
    }
  }

  List<Map<String, dynamic>> toJson() =>
      _events.map((e) => e.toJson()).toList();

  void dispose() {
    _throttleTimer?.cancel();
    _controller.close();
  }

  Timer? _throttleTimer;

  int _estimate(SocketEvent event) =>
      (event.eventName.length + (event.data?.toString().length ?? 0)) * 2;

  void _invalidateAndNotify() {
    _cachedEvents = null;
    if (_controller.isClosed) return;
    if (_throttleTimer?.isActive ?? false) return;
    _throttleTimer = Timer(const Duration(milliseconds: 250), () {
      if (!_controller.isClosed) _controller.add(events);
    });
  }
}
