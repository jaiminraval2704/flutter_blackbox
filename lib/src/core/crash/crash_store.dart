import 'dart:async';
import 'dart:collection';

import '../capture/bounded_value.dart';
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
  int _droppedEntryCount = 0;
  int _truncatedPayloadCount = 0;
  int _retainedBytes = 0;

  /// Broadcast stream that emits whenever a new crash is recorded.
  Stream<List<CrashEntry>> get stream => _controller.stream;

  /// Unmodifiable list of all recorded crash entries. Cached until the next mutation.
  List<CrashEntry> get entries =>
      _cachedEntries ??= List.unmodifiable(_entries);

  int get droppedEntryCount => _droppedEntryCount;
  int get truncatedPayloadCount => _truncatedPayloadCount;
  int get approximateRetainedBytes => _retainedBytes;

  void add(CrashEntry entry) {
    final message = captureBoundedString(entry.message, maxBytes: 128 * 1024);
    final originalStack = entry.stackTrace?.toString();
    final stack = originalStack == null
        ? null
        : captureBoundedString(originalStack, maxBytes: 128 * 1024);
    final library = entry.library == null
        ? null
        : captureBoundedString(entry.library!, maxBytes: 4 * 1024);
    if (message != entry.message ||
        stack != originalStack ||
        library != entry.library) {
      _truncatedPayloadCount++;
    }
    if (_entries.length >= capacity) {
      _retainedBytes -= _estimate(_entries.removeFirst());
      _droppedEntryCount++;
    }
    final capturedEntry = CrashEntry(
      id: entry.id,
      message: message,
      stackTrace: stack == null ? null : StackTrace.fromString(stack),
      library: library,
      timestamp: entry.timestamp,
      isFlutterError: entry.isFlutterError,
    );
    _entries.addLast(capturedEntry);
    _retainedBytes += _estimate(capturedEntry);
    _invalidateAndNotify();
  }

  void clear({bool notify = true}) {
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _entries.clear();
    _retainedBytes = 0;
    _cachedEntries = null;
    _droppedEntryCount = 0;
    _truncatedPayloadCount = 0;
    if (notify && !_controller.isClosed) {
      _controller.add(entries);
    }
  }

  List<Map<String, dynamic>> toJson() =>
      _entries.map((e) => e.toJson()).toList();

  void dispose() {
    _throttleTimer?.cancel();
    _controller.close();
  }

  // ── Private ─────────────────────────────────────────────────────────

  Timer? _throttleTimer;

  int _estimate(CrashEntry entry) =>
      (entry.message.length +
          (entry.stackTrace?.toString().length ?? 0) +
          (entry.library?.length ?? 0)) *
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
