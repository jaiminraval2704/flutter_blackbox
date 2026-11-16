import 'dart:async';
import 'dart:collection';

import '../capture/bounded_value.dart';

/// A single entry in the navigation history.
class NavigationEntry {
  const NavigationEntry({
    required this.routeName,
    required this.action,
    this.arguments,
    required this.timestamp,
    required this.stackDepth,
  });

  /// The route name (from [RouteSettings.name]) or runtimeType fallback.
  final String routeName;

  /// The navigation action: `push`, `pop`, `replace`, `remove`.
  final String action;

  /// The arguments passed to the route via [RouteSettings.arguments].
  final Object? arguments;

  /// When the navigation event occurred.
  final DateTime timestamp;

  /// Depth in the navigation stack at the time of this event.
  final int stackDepth;

  Map<String, dynamic> toJson() => {
        'routeName': routeName,
        'action': action,
        if (arguments != null) 'arguments': arguments.toString(),
        'timestamp': timestamp.toIso8601String(),
        'stackDepth': stackDepth,
      };
}

/// Tracks the live navigation stack and full navigation history.
///
/// Used by [BlackBoxNavigatorObserver] to capture route pushes, pops,
/// replacements, and removals — along with their arguments.
class NavigationStore {
  NavigationStore({this.capacity = 100});

  /// Maximum number of history entries to retain.
  final int capacity;

  // ── Internal state ──────────────────────────────────────────────────

  final _history = ListQueue<NavigationEntry>();
  final _stack = <NavigationEntry>[];
  final _controller = StreamController<List<NavigationEntry>>.broadcast();
  List<NavigationEntry>? _cachedHistory;
  int _droppedEntryCount = 0;
  int _truncatedPayloadCount = 0;

  // ── Public API ──────────────────────────────────────────────────────

  /// Full navigation history (oldest first).
  List<NavigationEntry> get history =>
      _cachedHistory ??= List.unmodifiable(_history);

  /// The current live navigation stack (bottom = root, top = current).
  List<NavigationEntry> get currentStack => List.unmodifiable(_stack);

  /// Stream that emits whenever navigation changes.
  Stream<List<NavigationEntry>> get stream => _controller.stream;

  int get droppedEntryCount => _droppedEntryCount;
  int get truncatedPayloadCount => _truncatedPayloadCount;
  int get approximateRetainedBytes => _history.fold(
        0,
        (total, entry) =>
            total +
            (entry.routeName.length +
                    entry.action.length +
                    (entry.arguments?.toString().length ?? 0)) *
                2,
      );

  /// Record a push event.
  void onPush(String routeName, Object? arguments) {
    routeName = _captureRouteName(routeName);
    final capturedArguments = _captureArguments(arguments);
    final entry = NavigationEntry(
      routeName: routeName,
      action: 'push',
      arguments: capturedArguments,
      timestamp: DateTime.now(),
      stackDepth: _stack.length + 1,
    );
    _stack.add(entry);
    _addToHistory(entry);
  }

  /// Record a pop event.
  void onPop(String routeName, Object? arguments) {
    routeName = _captureRouteName(routeName);
    final capturedArguments = _captureArguments(arguments);
    // Remove the top of the stack if it matches
    if (_stack.isNotEmpty) {
      _stack.removeLast();
    }
    final entry = NavigationEntry(
      routeName: routeName,
      action: 'pop',
      arguments: capturedArguments,
      timestamp: DateTime.now(),
      stackDepth: _stack.length,
    );
    _addToHistory(entry);
  }

  /// Record a replace event.
  void onReplace(
      String newRouteName, Object? newArguments, String? oldRouteName) {
    newRouteName = _captureRouteName(newRouteName);
    final capturedArguments = _captureArguments(newArguments);
    // Replace the top of the stack
    if (_stack.isNotEmpty) {
      _stack.removeLast();
    }
    final entry = NavigationEntry(
      routeName: newRouteName,
      action: 'replace',
      arguments: capturedArguments,
      timestamp: DateTime.now(),
      stackDepth: _stack.length + 1,
    );
    _stack.add(entry);
    _addToHistory(entry);
  }

  /// Record a remove event.
  void onRemove(String routeName, Object? arguments) {
    routeName = _captureRouteName(routeName);
    final capturedArguments = _captureArguments(arguments);
    _stack.removeWhere((e) => e.routeName == routeName);
    final entry = NavigationEntry(
      routeName: routeName,
      action: 'remove',
      arguments: capturedArguments,
      timestamp: DateTime.now(),
      stackDepth: _stack.length,
    );
    _addToHistory(entry);
  }

  void clear({bool notify = true}) {
    _history.clear();
    _stack.clear();
    _cachedHistory = null;
    _droppedEntryCount = 0;
    _truncatedPayloadCount = 0;
    if (notify) _notify();
  }

  void dispose() {
    _controller.close();
  }

  // ── Private ─────────────────────────────────────────────────────────

  void _addToHistory(NavigationEntry entry) {
    if (_history.length >= capacity) {
      _history.removeFirst();
      _droppedEntryCount++;
    }
    _history.addLast(entry);
    _cachedHistory = null;
    _notify();
  }

  Object? _captureArguments(Object? arguments) {
    final snapshot = captureBoundedValue(arguments, maxBytes: 16 * 1024);
    if (snapshot.truncated) _truncatedPayloadCount++;
    return snapshot.value;
  }

  String _captureRouteName(String routeName) {
    final captured = captureBoundedString(routeName, maxBytes: 8 * 1024);
    if (captured != routeName) _truncatedPayloadCount++;
    return captured;
  }

  void _notify() {
    if (!_controller.isClosed) {
      _controller.add(history);
    }
  }
}
