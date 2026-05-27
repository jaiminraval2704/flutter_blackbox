import 'dart:async';
import 'dart:collection';

import 'crash_entry.dart';

/// Manages a collection of captured application crashes and errors.
class CrashStore {
  /// Creates a crash store with a fixed [capacity].
  CrashStore({this.capacity = 100});

  /// Maximum number of crashes to retain.
  final int capacity;

  final _entries = ListQueue<CrashEntry>();
  final _controller = StreamController<List<CrashEntry>>.broadcast();

  // Cached snapshot — invalidated on mutation.
  List<CrashEntry>? _cachedEntries;

  /// Broadcast stream that emits whenever a new crash is recorded.
  Stream<List<CrashEntry>> get stream => _controller.stream;

  /// Unmodifiable list of all recorded crash entries. Cached until the next mutation.
  List<CrashEntry> get entries =>
      _cachedEntries ??= List.unmodifiable(_entries);

  void add(CrashEntry entry) {
    if (_entries.length >= capacity) _entries.removeFirst();
    _entries.addLast(entry);
    _invalidateAndNotify();
  }

  void clear() {
    _entries.clear();
    _invalidateAndNotify();
  }

  List<Map<String, dynamic>> toJson() =>
      _entries.map((e) => e.toJson()).toList();

  void dispose() {
    _throttleTimer?.cancel();
    _controller.close();
  }

  // ── Private ─────────────────────────────────────────────────────────

  Timer? _throttleTimer;

  void _invalidateAndNotify() {
    _cachedEntries = null;
    if (_controller.isClosed) return;
    if (_throttleTimer?.isActive ?? false) return;
    _throttleTimer = Timer(const Duration(milliseconds: 250), () {
      if (!_controller.isClosed) {
        _controller.add(entries);
      }
    });
  }
}
