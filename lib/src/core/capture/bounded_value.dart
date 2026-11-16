import 'dart:collection';

/// A detached diagnostic value captured within a bounded traversal budget.
class BoundedValue {
  const BoundedValue({
    required this.value,
    required this.approximateBytes,
    required this.truncated,
  });

  final Object? value;
  final int approximateBytes;
  final bool truncated;
}

/// Detaches common JSON-like values without first serializing the full object.
BoundedValue captureBoundedValue(
  Object? value, {
  required int maxBytes,
  int maxDepth = 8,
  int maxItems = 200,
}) {
  final capture = _BoundedCapture(maxBytes, maxDepth, maxItems);
  return capture.run(value);
}

String captureBoundedString(String value, {required int maxBytes}) =>
    _truncateString(value, maxBytes).$1;

class _BoundedCapture {
  _BoundedCapture(this.maxBytes, this.maxDepth, this.maxItems);

  final int maxBytes;
  final int maxDepth;
  final int maxItems;
  final Set<Object> _visiting = HashSet<Object>.identity();
  int _usedBytes = 0;
  int _visitedItems = 0;
  bool _truncated = false;

  BoundedValue run(Object? value) {
    Object? captured;
    try {
      captured = _visit(value, 0);
    } catch (_) {
      _truncated = true;
      captured = '[unavailable]';
    }
    return BoundedValue(
      value: captured,
      approximateBytes: _usedBytes,
      truncated: _truncated,
    );
  }

  Object? _visit(Object? value, int depth) {
    if (_usedBytes >= maxBytes) return _marker();
    if (value == null || value is bool || value is int) {
      _consume(value?.toString().length ?? 4);
      return value;
    }
    if (value is double) {
      final safeValue = value.isFinite ? value : value.toString();
      _consume(safeValue.toString().length);
      if (!value.isFinite) _truncated = true;
      return safeValue;
    }
    if (value is String) return _takeString(value);
    if (depth >= maxDepth) return _marker();
    if (++_visitedItems > maxItems) return _marker();

    if (value is Map) {
      if (!_visiting.add(value)) return _circularMarker();
      final result = <String, Object?>{};
      _consume(2);
      try {
        for (final entry in value.entries) {
          if (_usedBytes >= maxBytes || ++_visitedItems > maxItems) {
            _truncated = true;
            break;
          }
          final key = _takeString(entry.key.toString());
          _consume(3);
          result[key] = _visit(entry.value, depth + 1);
        }
      } finally {
        _visiting.remove(value);
      }
      return Map<String, Object?>.unmodifiable(result);
    }

    if (value is Iterable) {
      if (!_visiting.add(value)) return _circularMarker();
      final result = <Object?>[];
      _consume(2);
      try {
        for (final item in value) {
          if (_usedBytes >= maxBytes || ++_visitedItems > maxItems) {
            _truncated = true;
            break;
          }
          result.add(_visit(item, depth + 1));
          _consume(1);
        }
      } finally {
        _visiting.remove(value);
      }
      return List<Object?>.unmodifiable(result);
    }

    _truncated = true;
    try {
      return _takeString(value.toString());
    } catch (_) {
      return '[unavailable]';
    }
  }

  String _takeString(String value) {
    final remaining = maxBytes - _usedBytes;
    if (remaining <= 0) return _marker();
    final (captured, bytes, truncated) = _truncateString(value, remaining);
    _usedBytes += bytes;
    _truncated |= truncated;
    return captured;
  }

  String _marker() {
    _truncated = true;
    return '…[truncated]';
  }

  String _circularMarker() {
    _truncated = true;
    return '[circular]';
  }

  void _consume(int bytes) {
    _usedBytes = (_usedBytes + bytes).clamp(0, maxBytes);
    if (_usedBytes >= maxBytes) _truncated = true;
  }
}

(String, int, bool) _truncateString(String value, int maxBytes) {
  if (maxBytes <= 0) return ('', 0, value.isNotEmpty);
  var bytes = 0;
  var end = 0;
  for (final rune in value.runes) {
    final runeBytes = rune <= 0x7f
        ? 1
        : rune <= 0x7ff
            ? 2
            : rune <= 0xffff
                ? 3
                : 4;
    if (bytes + runeBytes > maxBytes) break;
    bytes += runeBytes;
    end += rune > 0xffff ? 2 : 1;
  }
  final truncated = end < value.length;
  return (value.substring(0, end), bytes, truncated);
}
