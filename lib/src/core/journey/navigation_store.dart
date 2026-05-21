import 'dart:async';
import 'dart:collection';

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

  // ── Public API ──────────────────────────────────────────────────────

  /// Full navigation history (oldest first).
  List<NavigationEntry> get history => _history.toList(growable: false);

  /// The current live navigation stack (bottom = root, top = current).
  List<NavigationEntry> get currentStack => List.unmodifiable(_stack);

  /// Stream that emits whenever navigation changes.
  Stream<List<NavigationEntry>> get stream => _controller.stream;

  /// Record a push event.
  void onPush(String routeName, Object? arguments) {
    final entry = NavigationEntry(
      routeName: routeName,
      action: 'push',
      arguments: arguments,
      timestamp: DateTime.now(),
      stackDepth: _stack.length + 1,
    );
    _stack.add(entry);
    _addToHistory(entry);
  }

  /// Record a pop event.
  void onPop(String routeName, Object? arguments) {
    // Remove the top of the stack if it matches
    if (_stack.isNotEmpty) {
      _stack.removeLast();
    }
    final entry = NavigationEntry(
      routeName: routeName,
      action: 'pop',
      arguments: arguments,
      timestamp: DateTime.now(),
      stackDepth: _stack.length,
    );
    _addToHistory(entry);
  }

  /// Record a replace event.
  void onReplace(
      String newRouteName, Object? newArguments, String? oldRouteName) {
    // Replace the top of the stack
    if (_stack.isNotEmpty) {
      _stack.removeLast();
    }
    final entry = NavigationEntry(
      routeName: newRouteName,
      action: 'replace',
      arguments: newArguments,
      timestamp: DateTime.now(),
      stackDepth: _stack.length + 1,
    );
    _stack.add(entry);
    _addToHistory(entry);
  }

  /// Record a remove event.
  void onRemove(String routeName, Object? arguments) {
    _stack.removeWhere((e) => e.routeName == routeName);
    final entry = NavigationEntry(
      routeName: routeName,
      action: 'remove',
      arguments: arguments,
      timestamp: DateTime.now(),
      stackDepth: _stack.length,
    );
    _addToHistory(entry);
  }

  void clear() {
    _history.clear();
    _stack.clear();
    _notify();
  }

  void dispose() {
    _controller.close();
  }

  // ── Private ─────────────────────────────────────────────────────────

  void _addToHistory(NavigationEntry entry) {
    if (_history.length >= capacity) _history.removeFirst();
    _history.addLast(entry);
    _notify();
  }

  void _notify() {
    if (!_controller.isClosed) {
      _controller.add(history);
    }
  }
}
