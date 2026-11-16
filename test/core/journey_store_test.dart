import 'package:flutter_blackbox/src/core/journey/journey_event.dart';
import 'package:flutter_blackbox/src/core/journey/journey_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('JourneyStore bounds text and reports capacity eviction', () {
    final store = JourneyStore(capacity: 2);

    store.record(ErrorEvent(DateTime(2026), message: 'x' * (70 * 1024)));
    store.record(RouteEvent(DateTime(2026), route: '/two'));
    store.record(RouteEvent(DateTime(2026), route: '/three'));

    expect(store.events, hasLength(2));
    expect(store.droppedEntryCount, 1);
    expect(store.truncatedPayloadCount, 1);
    expect(store.approximateRetainedBytes, greaterThan(0));

    store.clear();
    expect(store.approximateRetainedBytes, 0);
    expect(store.droppedEntryCount, 0);
    expect(store.truncatedPayloadCount, 0);
  });
}
