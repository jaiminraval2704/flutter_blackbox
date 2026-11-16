import 'package:flutter/widgets.dart';

import '../../blackbox.dart';
import '../../companion/firebase_streamer.dart';
import '../capture/bounded_value.dart';
import 'journey_event.dart';
import 'journey_store.dart';
import 'navigation_store.dart';

/// Records navigation events without executing application route builders or
/// walking the application element tree.
class BlackBoxNavigatorObserver extends NavigatorObserver {
  BlackBoxNavigatorObserver(
    this._store, {
    this.navigationStore,
    this.routeNameResolver,
  });

  final JourneyStore _store;
  final NavigationStore? navigationStore;

  /// Optional fallback for applications that use unnamed routes.
  String? Function(Route<dynamic> route)? routeNameResolver;

  String _routeName(Route<dynamic> route) {
    final configuredName = route.settings.name;
    if (configuredName != null && configuredName.isNotEmpty) {
      return captureBoundedString(configuredName, maxBytes: 8 * 1024);
    }

    if (route.settings is Page) {
      try {
        final child = (route.settings as dynamic).child;
        if (child is Widget) {
          return captureBoundedString(
            child.runtimeType.toString(),
            maxBytes: 8 * 1024,
          );
        }
      } catch (_) {
        // Not every Page implementation exposes a child.
      }
    }

    try {
      final resolved = routeNameResolver?.call(route);
      if (resolved != null && resolved.isNotEmpty) {
        return captureBoundedString(resolved, maxBytes: 8 * 1024);
      }
    } catch (_) {
      // Diagnostics must never break application navigation.
    }

    return captureBoundedString(
      route.runtimeType.toString(),
      maxBytes: 8 * 1024,
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!BlackBox.isCapturing) return;
    final name = _routeName(route);
    _store.record(RouteEvent(DateTime.now(), route: name));
    navigationStore?.onPush(name, route.settings.arguments);
    _broadcast('push', name, route.settings.arguments);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!BlackBox.isCapturing) return;
    final name = _routeName(route);
    _store.record(RouteEvent(DateTime.now(), route: 'popped $name'));
    navigationStore?.onPop(name, route.settings.arguments);
    _broadcast('pop', name, route.settings.arguments);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (!BlackBox.isCapturing || newRoute == null) return;
    final name = _routeName(newRoute);
    _store.record(RouteEvent(DateTime.now(), route: 'replaced with $name'));
    navigationStore?.onReplace(
      name,
      newRoute.settings.arguments,
      oldRoute?.settings.name,
    );
    _broadcast('replace', name, newRoute.settings.arguments);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!BlackBox.isCapturing) return;
    final name = _routeName(route);
    _store.record(RouteEvent(DateTime.now(), route: 'removed $name'));
    navigationStore?.onRemove(name, route.settings.arguments);
    _broadcast('remove', name, route.settings.arguments);
  }

  void _broadcast(String action, String route, Object? arguments) {
    FirebaseStreamer.instance.broadcast('navigation', {
      'action': action,
      'route': route,
      if (arguments != null) 'arguments': arguments,
    });
  }
}
