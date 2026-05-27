import 'dart:async';
import 'dart:collection';

import 'log_entry.dart';
import 'log_level.dart';

/// Ring-buffer log store with a [Stream] interface.
///
/// Holds at most [capacity] entries. Oldest entries are dropped when
/// the buffer is full. All mutations are synchronous; consumers react
/// via [stream].
class LogStore {
  LogStore({this.capacity = 1000});

  final int capacity;

  final _buffer = ListQueue<LogEntry>();
  final _controller = StreamController<List<LogEntry>>.broadcast();

  // ── Public API ──────────────────────────────────────────────────────

  /// All currently stored entries, oldest-first.
  List<LogEntry> get entries => List.unmodifiable(_buffer);

  /// Emits the full updated list whenever a new entry is added or the
  /// store is cleared.
  Stream<List<LogEntry>> get stream => _controller.stream;

  /// Add a new log entry.
  void add(LogEntry entry) {
    if (_buffer.length >= capacity) _buffer.removeFirst();
    _buffer.addLast(entry);
    _notify();
  }

  /// Remove all entries.
  void clear() {
    _buffer.clear();
    _notify();
  }

  /// Remove the entry at [index] (0-based, oldest-first).
  void removeAt(int index) {
    if (index < 0 || index >= _buffer.length) return;
    final list = _buffer.toList();
    list.removeAt(index);
    _buffer.clear();
    _buffer.addAll(list);
    _notify();
  }

  /// Filter entries by [level] and optional [query] string.
  Iterable<LogEntry> filter({
    LogLevel? level,
    String? query,
    String? tag,
  }) {
    final q = query?.toLowerCase();

    return _buffer.where((e) {
      if (level != null && e.level != level) return false;
      if (tag != null && e.tag != tag) return false;
      if (q != null && q.isNotEmpty) {
        final inMessage = e.message.toLowerCase().contains(q);
        final inTag = e.tag?.toLowerCase().contains(q) ?? false;
        final inData = e.data?.toString().toLowerCase().contains(q) ?? false;
        if (!inMessage && !inTag && !inData) return false;
      }
      return true;
    });
  }

  /// Export all entries as a JSON-serialisable list.
  List<Map<String, dynamic>> toJson() =>
      _buffer.map((e) => e.toJson()).toList();

  void dispose() {
    _throttleTimer?.cancel();
    _controller.close();
  }

  // ── Private ─────────────────────────────────────────────────────────

  Timer? _throttleTimer;

  void _notify() {
    if (_controller.isClosed) return;
    if (_throttleTimer?.isActive ?? false) return;

    _throttleTimer = Timer(const Duration(milliseconds: 250), () {
      if (!_controller.isClosed) {
        _controller.add(List.unmodifiable(_buffer));
      }
    });
  }
}
