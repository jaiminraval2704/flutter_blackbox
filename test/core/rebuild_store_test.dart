import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blackbox/src/core/rebuild/rebuild_store.dart';

void main() {
  group('RebuildStore', () {
    late RebuildStore store;

    setUp(() {
      store = RebuildStore();
    });

    tearDown(() {
      store.dispose();
    });

    test('initial state is empty', () {
      expect(store.counts, isEmpty);
    });

    test('record increments count for a widget', () {
      store.record('MyWidget');
      expect(store.counts['MyWidget'], 1);

      store.record('MyWidget');
      expect(store.counts['MyWidget'], 2);
    });

    test('capacity limit is enforced and removes lowest count', () {
      store.capacity = 3;

      store.record('WidgetA'); // 1
      store.record('WidgetA'); // 2

      store.record('WidgetB'); // 1
      store.record('WidgetB'); // 2
      store.record('WidgetB'); // 3

      store.record('WidgetC'); // 1

      expect(store.counts.length, 3);
      expect(store.counts.keys, containsAll(['WidgetA', 'WidgetB', 'WidgetC']));

      // Adding a 4th unique widget should evict WidgetC, since it has the lowest count (1)
      store.record('WidgetD');

      expect(store.counts.length, 3);
      expect(store.counts.keys, containsAll(['WidgetA', 'WidgetB', 'WidgetD']));
      expect(store.counts.containsKey('WidgetC'), isFalse);
    });

    test('reset clears all counts', () {
      store.record('WidgetA');
      expect(store.counts, isNotEmpty);

      store.reset();
      expect(store.counts, isEmpty);
    });

    test('sortedEntries returns entries sorted by count descending', () {
      store.record('WidgetA'); // 1
      store.record('WidgetB'); // 2
      store.record('WidgetB');
      store.record('WidgetC'); // 3
      store.record('WidgetC');
      store.record('WidgetC');

      final sorted = store.sortedEntries;
      expect(sorted[0].key, 'WidgetC');
      expect(sorted[0].value, 3);
      expect(sorted[1].key, 'WidgetB');
      expect(sorted[1].value, 2);
      expect(sorted[2].key, 'WidgetA');
      expect(sorted[2].value, 1);
    });
  });
}
