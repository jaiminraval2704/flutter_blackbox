import 'package:flutter/material.dart';
import 'package:flutter_blackbox/flutter_blackbox.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(BlackBox.dispose);

  test('unnamed imperative routes do not execute their builder', () {
    var builderCalled = false;
    BlackBox.setup(enabled: true);
    final route = MaterialPageRoute<void>(
      builder: (_) {
        builderCalled = true;
        return const SizedBox();
      },
    );

    BlackBox.journeyObserver.didPush(route, null);

    expect(builderCalled, isFalse);
    expect(
      BlackBox.instance.navigationStore.history.single.routeName,
      contains('MaterialPageRoute'),
    );
  });

  test('route name resolver provides an unnamed-route migration path', () {
    BlackBox.setup(
      enabled: true,
      routeNameResolver: (_) => 'CheckoutPage',
    );
    final route = MaterialPageRoute<void>(builder: (_) => const SizedBox());

    BlackBox.journeyObserver.didPush(route, null);

    expect(
      BlackBox.instance.navigationStore.history.single.routeName,
      'CheckoutPage',
    );
  });

  test('a throwing route resolver cannot break navigation tracking', () {
    BlackBox.setup(
      enabled: true,
      routeNameResolver: (_) => throw StateError('resolver failed'),
    );
    final route = MaterialPageRoute<void>(builder: (_) => const SizedBox());

    expect(
      () => BlackBox.journeyObserver.didPush(route, null),
      returnsNormally,
    );
    expect(BlackBox.instance.navigationStore.history, hasLength(1));
  });
}
