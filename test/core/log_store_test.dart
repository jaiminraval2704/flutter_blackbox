import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blackbox/src/core/log/log_entry.dart';
import 'package:flutter_blackbox/src/core/log/log_level.dart';
import 'package:flutter_blackbox/src/core/log/log_store.dart';

void main() {
  group('LogStore', () {
    late LogStore store;

    setUp(() => store = LogStore(capacity: 5));
    tearDown(() => store.dispose());

    LogEntry entry(String msg, {LogLevel level = LogLevel.info, String? tag}) =>
        LogEntry(
          id: msg,
          level: level,
          message: msg,
          timestamp: DateTime.now(),
          tag: tag,
        );

    test('adds entries and respects capacity', () {
      for (var i = 0; i < 7; i++) {
        store.add(entry('msg_$i'));
      }
      expect(store.entries.length, 5);
      expect(store.entries.first.message, 'msg_2'); // oldest dropped
      expect(store.droppedEntryCount, 2);
      expect(store.approximateRetainedBytes, greaterThan(0));
    });

    test('clear removes all entries', () {
      store.add(entry('a'));
      store.clear();
      expect(store.entries, isEmpty);
      expect(store.approximateRetainedBytes, 0);
    });

    test('filter by level', () {
      store.add(entry('info msg', level: LogLevel.info));
      store.add(entry('error msg', level: LogLevel.error));

      final errors = store.filter(level: LogLevel.error);
      expect(errors.length, 1);
      expect(errors.first.message, 'error msg');
    });

    test('filter by query', () {
      store.add(entry('payment failed'));
      store.add(entry('user logged in'));

      final results = store.filter(query: 'payment');
      expect(results.length, 1);
    });

    test('filter by tag', () {
      store.add(entry('tagged', tag: 'AuthBloc'));
      store.add(entry('untagged'));

      expect(store.filter(tag: 'AuthBloc').length, 1);
    });

    test('stream emits on add', () async {
      final emissions = <int>[];
      final sub = store.stream.listen((e) => emissions.add(e.length));

      store.add(entry('a'));
      store.add(entry('b'));

      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(emissions, [2]);
      await sub.cancel();
    });

    test('entries snapshot is cached until mutation', () {
      final before = store.entries;
      expect(identical(store.entries, before), isTrue);

      store.add(entry('new'));

      expect(identical(store.entries, before), isFalse);
    });

    test('detaches mutable metadata', () {
      final metadata = <String, dynamic>{
        'items': <Object?>[1, 2],
      };
      store.add(LogEntry(
        id: 'id',
        level: LogLevel.info,
        message: 'message',
        timestamp: DateTime.now(),
        data: metadata,
      ));

      (metadata['items'] as List<Object?>).add(3);

      expect(store.entries.single.data, {
        'items': [1, 2],
      });
    });

    test('filter by query matches error field', () {
      store.add(LogEntry(
        id: 'err1',
        level: LogLevel.error,
        message: 'Something crashed',
        timestamp: DateTime.now(),
        error: FormatException('Invalid JSON payload'),
      ));
      store.add(entry('regular message'));

      final results = store.filter(query: 'FormatException');
      expect(results.length, 1);
      expect(results.first.id, 'err1');
    });

    test(
        'removeWhere atomically deletes matching entries and updates retained bytes',
        () {
      store.add(entry('keep_1'));
      store.add(entry('delete_1'));
      store.add(entry('delete_2'));
      store.add(entry('keep_2'));

      final initialBytes = store.approximateRetainedBytes;
      store.removeWhere((e) => e.message.startsWith('delete_'));

      expect(store.entries.map((e) => e.message), ['keep_1', 'keep_2']);
      expect(store.approximateRetainedBytes, lessThan(initialBytes));
      expect(store.approximateRetainedBytes, greaterThanOrEqualTo(0));
    });

    test('toJson returns serialisable list', () {
      store.add(entry('hello', level: LogLevel.warning));
      final json = store.toJson();
      expect(json.first['message'], 'hello');
      expect(json.first['level'], 'WARN');
    });
  });
}
