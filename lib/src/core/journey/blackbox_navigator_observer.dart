import 'package:flutter/widgets.dart';

import '../../blackbox.dart';
import 'journey_event.dart';
import 'journey_store.dart';
import 'navigation_store.dart';

class BlackBoxNavigatorObserver extends NavigatorObserver {
  BlackBoxNavigatorObserver(
    this._store, {
    this.navigationStore,
  });
  final JourneyStore _store;

  /// Optional navigation store for route tracking with arguments.
  final NavigationStore? navigationStore;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!BlackBox.instance.isEnabled) return;
    final name = route.settings.name ?? route.runtimeType.toString();
    _store.record(RouteEvent(DateTime.now(), route: name));
    navigationStore?.onPush(name, route.settings.arguments);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!BlackBox.instance.isEnabled) return;
    final name = route.settings.name ?? route.runtimeType.toString();
    _store.record(RouteEvent(DateTime.now(), route: 'popped $name'));
    navigationStore?.onPop(name, route.settings.arguments);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (!BlackBox.instance.isEnabled) return;
    if (newRoute != null) {
      final name = newRoute.settings.name ?? newRoute.runtimeType.toString();
      _store.record(RouteEvent(DateTime.now(), route: 'replaced with $name'));
      navigationStore?.onReplace(
        name,
        newRoute.settings.arguments,
        oldRoute?.settings.name,
      );
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!BlackBox.instance.isEnabled) return;
    final name = route.settings.name ?? route.runtimeType.toString();
    _store.record(RouteEvent(DateTime.now(), route: 'removed $name'));
    navigationStore?.onRemove(name, route.settings.arguments);
  }
}
