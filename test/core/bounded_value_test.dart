import 'dart:convert';

import 'package:flutter_blackbox/src/core/capture/bounded_value.dart';
import 'package:flutter_test/flutter_test.dart';

class _BadString {
  @override
  String toString() => throw StateError('no string');
}

void main() {
  group('captureBoundedValue', () {
    test('detaches nested caller-owned collections', () {
      final source = <String, Object?>{
        'nested': <Object?>[1, 2],
      };

      final result = captureBoundedValue(source, maxBytes: 1024);
      (source['nested'] as List<Object?>).add(3);

      expect(result.value, {
        'nested': [1, 2],
      });
      expect(
        () => (result.value as Map<String, Object?>)['new'] = true,
        throwsUnsupportedError,
      );
    });

    test('stops circular and unbounded structures', () {
      final circular = <Object?>[];
      circular.add(circular);

      final circularResult = captureBoundedValue(circular, maxBytes: 1024);
      final infiniteResult = captureBoundedValue(
        Iterable<int>.generate(1000000),
        maxBytes: 1024,
        maxItems: 20,
      );

      expect(circularResult.truncated, isTrue);
      expect(circularResult.value.toString(), contains('[circular]'));
      expect(infiniteResult.truncated, isTrue);
      expect((infiniteResult.value as List<Object?>).length, lessThan(100));
    });

    test('uses a UTF-8 byte boundary without splitting runes', () {
      final result = captureBoundedString('😀😀😀', maxBytes: 8);

      expect(result, '😀😀');
      expect(utf8.encode(result), hasLength(8));
    });

    test('sanitises values that JSON cannot encode', () {
      final result = captureBoundedValue(
        {'number': double.nan, 'bad': _BadString()},
        maxBytes: 1024,
      );

      expect(() => jsonEncode(result.value), returnsNormally);
      expect(result.truncated, isTrue);
    });
  });
}
