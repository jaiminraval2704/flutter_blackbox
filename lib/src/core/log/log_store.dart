import 'dart:async';
import 'dart:collection';

import '../capture/bounded_value.dart';
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
  List<LogEntry>? _cachedEntries;
  int _droppedEntryCount = 0;
  int _truncatedPayloadCount = 0;
  int _retainedBytes = 0;

  // ── Public API ──────────────────────────────────────────────────────

  /// All currently stored entries, oldest-first.
  List<LogEntry> get entries => _cachedEntries ??= List.unmodifiable(_buffer);

  /// Emits the full updated list whenever a new entry is added or the
  /// store is cleared.
  Stream<List<LogEntry>> get stream => _controller.stream;

  int get droppedEntryCount => _droppedEntryCount;
  int get truncatedPayloadCount => _truncatedPayloadCount;
  int get approximateRetainedBytes => _retainedBytes;

  /// Add a new log entry.
  void add(LogEntry entry) {
    final message = captureBoundedString(entry.message, maxBytes: 64 * 1024);
    final data = captureBoundedValue(entry.data, maxBytes: 32 * 1024);
    final error = captureBoundedValue(entry.error, maxBytes: 32 * 1024);
    final stack = entry.stackTrace == null
        ? null
        : captureBoundedString(
            entry.stackTrace.toString(),
            maxBytes: 128 * 1024,
          );
    final tag = entry.tag == null
        ? null
        : captureBoundedString(entry.tag!, maxBytes: 4 * 1024);
    if (message != entry.message ||
        tag != entry.tag ||
        data.truncated ||
        error.truncated ||
        (stack != null && stack != entry.stackTrace.toString())) {
      _truncatedPayloadCount++;
    }
    if (_buffer.length >= capacity) {
      _retainedBytes -= _estimate(_buffer.removeFirst());
      if (_retainedBytes < 0) _retainedBytes = 0;
      _droppedEntryCount++;
    }
    final capturedEntry = LogEntry(
      id: entry.id,
      level: entry.level,
      message: message,
      timestamp: entry.timestamp,
      tag: tag,
      data: data.value is Map<String, Object?>
          ? Map<String, dynamic>.unmodifiable(data.value as Map)
          : null,
      error: error.value,
      stackTrace: stack == null ? null : StackTrace.fromString(stack),
    );
    _buffer.addLast(capturedEntry);
    _retainedBytes += _estimate(capturedEntry);
    _invalidateAndNotify();
  }

  /// Remove all entries.
  void clear({bool notify = true}) {
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _buffer.clear();
    _retainedBytes = 0;
    _cachedEntries = null;
    _droppedEntryCount = 0;
    _truncatedPayloadCount = 0;
    if (notify && !_controller.isClosed) {
      _controller.add(entries);
    }
  }

  /// Remove the entry at [index] (0-based, oldest-first).
  void removeAt(int index) {
    if (index < 0 || index >= _buffer.length) return;
    final list = _buffer.toList();
    _retainedBytes -= _estimate(list.removeAt(index));
    if (_retainedBytes < 0) _retainedBytes = 0;
    _buffer.clear();
    _buffer.addAll(list);
    _invalidateAndNotify();
  }

  /// Removes all entries that satisfy [test].
  void removeWhere(bool Function(LogEntry) test) {
    final toRemove = _buffer.where(test).toList();
    if (toRemove.isEmpty) return;
    for (final e in toRemove) {
      _retainedBytes -= _estimate(e);
    }
    if (_retainedBytes < 0) _retainedBytes = 0;
    _buffer.removeWhere(test);
    _invalidateAndNotify();
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
        final inError = e.error?.toString().toLowerCase().contains(q) ?? false;
        if (!inMessage && !inTag && !inData && !inError) return false;
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

  int _estimate(LogEntry entry) =>
      (entry.message.length +
          (entry.tag?.length ?? 0) +
          (entry.data?.toString().length ?? 0) +
          (entry.error?.toString().length ?? 0) +
          (entry.stackTrace?.toString().length ?? 0)) *
      2;

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
