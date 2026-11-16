import 'dart:async';

/// Tracks widget rebuild counts and exposes them as a broadcast stream.
class RebuildStore {
  final _counts = <String, int>{};
  final _controller = StreamController<Map<String, int>>.broadcast();
  Map<String, int>? _cachedCounts;
  int _droppedEntryCount = 0;
  DateTime? _trackingStartedAt;

  Timer? _throttleTimer;

  /// Maximum number of unique widgets to track to prevent memory leaks.
  int capacity = 500;

  /// Current rebuild count for each tracked widget label.
  Map<String, int> get counts => _cachedCounts ??= Map.unmodifiable(_counts);

  int get droppedEntryCount => _droppedEntryCount;
  int get approximateRetainedBytes => _counts.keys.fold(
        0,
        (total, name) => total + name.length * 2 + 8,
      );

  /// Duration since the first widget rebuild was recorded.
  Duration get trackingDuration => _trackingStartedAt != null
      ? DateTime.now().difference(_trackingStartedAt!)
      : Duration.zero;

  /// Broadcast stream of the current rebuild counts, throttled to 500ms.
  Stream<Map<String, int>> get stream => _controller.stream;

  /// Record a single rebuild for [widgetName].
  void record(String widgetName) {
    _trackingStartedAt ??= DateTime.now();
    if (!_counts.containsKey(widgetName) && _counts.length >= capacity) {
      // Find the entry with the lowest rebuild count and remove it to prevent memory leaks
      String? lowestKey;
      int lowestCount = 2147483647; // Max int
      for (final entry in _counts.entries) {
        if (entry.value < lowestCount) {
          lowestCount = entry.value;
          lowestKey = entry.key;
        }
      }
      if (lowestKey != null) _counts.remove(lowestKey);
      _droppedEntryCount++;
    }
    _counts[widgetName] = (_counts[widgetName] ?? 0) + 1;
    _invalidateAndNotify();
  }

  /// Sorted entries, highest rebuild count first.
  List<MapEntry<String, int>> get sortedEntries {
    final entries = _counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  void reset({bool notify = true}) {
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _counts.clear();
    _trackingStartedAt = null;
    _cachedCounts = null;
    _droppedEntryCount = 0;
    if (notify && !_controller.isClosed) {
      _controller.add(counts);
    }
  }

  void dispose() {
    _throttleTimer?.cancel();
    _controller.close();
  }

  void _invalidateAndNotify() {
    _cachedCounts = null;
    if (_controller.isClosed) return;
    if (_throttleTimer?.isActive ?? false) return;
    _throttleTimer = Timer(const Duration(milliseconds: 500), () {
      if (!_controller.isClosed) {
        _controller.add(counts);
      }
    });
  }
}
