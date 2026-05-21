import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blackbox/src/core/journey/navigation_store.dart';

void main() {
  group('NavigationStore', () {
    late NavigationStore store;

    setUp(() => store = NavigationStore(capacity: 5));
    tearDown(() => store.dispose());

    test('initial state is empty', () {
      expect(store.history, isEmpty);
      expect(store.currentStack, isEmpty);
    });

    test('onPush adds to stack and history', () {
      store.onPush('/home', null);
      expect(store.currentStack.length, 1);
      expect(store.currentStack.first.routeName, '/home');
      expect(store.currentStack.first.action, 'push');
      expect(store.currentStack.first.stackDepth, 1);
      expect(store.history.length, 1);
    });

    test('onPop removes from stack and adds to history', () {
      store.onPush('/home', null);
      store.onPush('/details', {'id': 42});
      expect(store.currentStack.length, 2);

      store.onPop('/details', {'id': 42});
      expect(store.currentStack.length, 1);
      expect(store.currentStack.last.routeName, '/home');
      expect(store.history.length, 3); // push, push, pop
      expect(store.history.last.action, 'pop');
    });

    test('onReplace replaces top of stack', () {
      store.onPush('/home', null);
      store.onPush('/old', null);

      store.onReplace('/new', {'key': 'value'}, '/old');
      expect(store.currentStack.length, 2);
      expect(store.currentStack.last.routeName, '/new');
      expect(store.currentStack.last.arguments, {'key': 'value'});
      expect(store.currentStack.last.action, 'replace');
    });

    test('onRemove removes matching route from stack', () {
      store.onPush('/home', null);
      store.onPush('/modal', null);
      store.onPush('/top', null);

      store.onRemove('/modal', null);
      expect(store.currentStack.length, 2);
      expect(store.currentStack.map((e) => e.routeName).toList(),
          ['/home', '/top']);
    });

    test('capacity limit drops oldest history entries', () {
      for (var i = 0; i < 7; i++) {
        store.onPush('/page_$i', null);
      }
      // Capacity is 5 — oldest 2 entries are dropped from history
      expect(store.history.length, 5);
      expect(store.history.first.routeName, '/page_2');
    });

    test('stack depth is tracked correctly', () {
      store.onPush('/a', null);
      expect(store.currentStack.last.stackDepth, 1);

      store.onPush('/b', null);
      expect(store.currentStack.last.stackDepth, 2);

      store.onPop('/b', null);
      // After pop, the pop entry in history has stack depth 1
      expect(store.history.last.stackDepth, 1);
    });

    test('clear empties everything', () {
      store.onPush('/a', null);
      store.onPush('/b', null);
      store.clear();
      expect(store.history, isEmpty);
      expect(store.currentStack, isEmpty);
    });

    test('stream emits on push', () async {
      final events = <List<NavigationEntry>>[];
      final sub = store.stream.listen(events.add);

      store.onPush('/a', null);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(events.length, 1);
      expect(events.first.length, 1);
      await sub.cancel();
    });

    test('arguments are preserved', () {
      final args = {'userId': 123, 'name': 'Test'};
      store.onPush('/profile', args);

      expect(store.currentStack.first.arguments, args);
      expect(store.history.first.arguments, args);
    });

    test('toJson serialises entries', () {
      store.onPush('/home', {'key': 'value'});
      final json = store.history.first.toJson();
      expect(json['routeName'], '/home');
      expect(json['action'], 'push');
      expect(json['arguments'], "{key: value}");
      expect(json['stackDepth'], 1);
      expect(json.containsKey('timestamp'), isTrue);
    });
  });
}
