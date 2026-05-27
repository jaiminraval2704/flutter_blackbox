import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'adapters/http/blackbox_http_adapter.dart';
import 'adapters/log/blackbox_log_adapter.dart';
import 'adapters/log/print_log_adapter.dart';
import 'adapters/socket/blackbox_socket_adapter.dart';
import 'adapters/storage/blackbox_storage_adapter.dart';
import 'adapters/observer/blackbox_observer.dart';
import 'core/report/package_info_impl.dart'
    if (dart.library.html) 'core/report/package_info_stub.dart'
    if (dart.library.js_interop) 'core/report/package_info_stub.dart';
import 'core/report/platform_info_impl.dart'
    if (dart.library.html) 'core/report/platform_info_stub.dart'
    if (dart.library.js_interop) 'core/report/platform_info_stub.dart';
import 'core/rebuild/rebuild_store.dart';
import 'core/crash/crash_entry.dart';
import 'core/crash/crash_store.dart';
import 'core/journey/blackbox_navigator_observer.dart';
import 'core/journey/journey_event.dart';
import 'core/journey/journey_store.dart';
import 'core/journey/navigation_store.dart';
import 'core/log/log_entry.dart';
import 'core/log/log_level.dart';
import 'core/log/log_store.dart';
import 'core/network/mock_engine.dart';
import 'core/network/mock_response.dart';
import 'core/network/network_redactor.dart';
import 'core/network/network_store.dart';
import 'core/network/network_response.dart';
import 'core/performance/fps_monitor.dart';
import 'core/report/blackbox_device_info.dart';
import 'core/report/blackbox_report.dart';
import 'core/socket/socket_event.dart';
import 'core/socket/socket_store.dart';
import 'overlay/blackbox_trigger.dart';
import 'overlay/widgets/blackbox_theme.dart';

/// Central singleton that owns all BlackBox stores and wires adapters.
///
/// Call [BlackBox.setup] once in [main] before [runApp].
///
/// ```dart
/// void main() {
///   BlackBox.setup(
///     httpAdapters: [DioBlackBoxAdapter(dio)],
///     trigger: BlackBoxTrigger.shake(),
///   );
///   runApp(BlackBoxOverlay(child: const MyApp()));
/// }
/// ```
class BlackBox {
  BlackBox._();

  static final BlackBox _instance = BlackBox._();

  static BlackBox get instance => _instance;

  // Monotonic counter for globally unique IDs.
  static int _idCounter = 0;

  // ── Internal stores ──────────────────────────────────────────────────

  /// Store for recorded log entries.
  final logStore = LogStore();

  /// Store for intercepted network requests.
  ///
  /// Re-created in [setup] when a [NetworkRedactor] is provided.
  NetworkStore networkStore = NetworkStore();

  /// Engine for mocking network responses based on URL patterns.
  final mockEngine = MockEngine();

  /// Monitor for tracking FPS and frame performance.
  final fpsMonitor = FpsMonitor();

  /// Store for captured platform and Flutter crashes.
  final crashStore = CrashStore();

  /// Store for user navigation and interaction journey.
  final journeyStore = JourneyStore();

  /// Store for route navigation history with arguments.
  final navigationStore = NavigationStore();

  /// Store for intercepted Socket.IO events.
  final socketStore = SocketStore();

  /// Store for widget rebuild counts and tracking state.
  final rebuildStore = RebuildStore();

  // ── Storage adapters ──────────────────────────────────────────────────

  final List<BlackBoxStorageAdapter> _storageAdapters = [];

  // ── Observers ─────────────────────────────────────────────────────────

  final List<BlackBoxObserver> _observers = [];

  /// Registered observers (e.g., Crashlytics, Sentry forwarding).
  List<BlackBoxObserver> get observers => List.unmodifiable(_observers);

  // ── Journey stream subscription ──────────────────────────────────────

  StreamSubscription<List<NetworkEntry>>? _journeySub;

  // ── Rebuild tracking state ────────────────────────────────────────────

  bool _autoRebuildTracking = false;
  DebugPrintCallback? _originalDebugPrint;

  /// Whether the overlay is globally enabled.
  /// When `false`, [setup] and [BlackBoxOverlay] become no-ops.
  bool get isEnabled => _enabled;

  /// Whether the auto-rebuild tracking is currently active.
  bool get isAutoRebuildTrackingEnabled => _autoRebuildTracking;

  /// A [NavigatorObserver] that logs navigation events to the [journeyStore]
  /// and [navigationStore].
  /// Add this to your [MaterialApp.navigatorObservers].
  static final journeyObserver = BlackBoxNavigatorObserver(
    _instance.journeyStore,
    navigationStore: _instance.navigationStore,
  );

  // ── Configuration ────────────────────────────────────────────────────

  bool _enabled = kDebugMode;
  bool _redactSensitiveData = true;
  BlackBoxTrigger _trigger = const BlackBoxTrigger.shake();
  BlackBoxThemeData _theme = const BlackBoxThemeData.dark();
  final List<BlackBoxHttpAdapter> _httpAdapters = [];
  final List<BlackBoxSocketAdapter> _socketAdapters = [];
  BlackBoxLogAdapter? _logAdapter;
  FlutterExceptionHandler? _originalFlutterError;
  bool Function(Object, StackTrace)? _originalPlatformError;

  /// Whether sensitive storage keys are redacted in the overlay.
  /// Defaults to `true` — sensitive values show as `••••••••`.
  bool get redactSensitiveData => _redactSensitiveData;

  /// Registered storage adapters (e.g., SharedPreferences, Hive).
  List<BlackBoxStorageAdapter> get storageAdapters =>
      List.unmodifiable(_storageAdapters);

  /// Registered socket adapters (e.g., Socket.IO).
  List<BlackBoxSocketAdapter> get socketAdapters =>
      List.unmodifiable(_socketAdapters);

  /// Current trigger used to open the overlay.
  BlackBoxTrigger get trigger => _trigger;

  /// Current theme for the overlay UI.
  BlackBoxThemeData get theme => _theme;

  /// Registered network adapters (e.g., Dio, dart:http).
  List<BlackBoxHttpAdapter> get httpAdapters =>
      List.unmodifiable(_httpAdapters);

  // ── Overlay callback (set by BlackBoxOverlay widget) ───────────────────

  VoidCallback? _openOverlay;
  VoidCallback? _closeOverlay;
  VoidCallback? _toggleOverlay;

  void registerOverlayCallbacks({
    required VoidCallback open,
    required VoidCallback close,
    required VoidCallback toggle,
  }) {
    _openOverlay = open;
    _closeOverlay = close;
    _toggleOverlay = toggle;
  }

  // ── Public static API ────────────────────────────────────────────────

  /// Configures and initializes the BlackBox singleton.
  ///
  /// [httpAdapters] - List of [BlackBoxHttpAdapter] to intercept network calls (Dio, http).
  /// [socketAdapters] - List of [BlackBoxSocketAdapter] to intercept Socket.IO events.
  /// [logAdapter] - The adapter used to capture logs. Defaults to [PrintLogAdapter].
  /// [storageAdapters] - List of [BlackBoxStorageAdapter] to inspect app storage.
  /// [observers] - List of [BlackBoxObserver] to forward events to external services (Crashlytics, Sentry, etc.).
  /// [trigger] - How to open the overlay. Defaults to [BlackBoxTrigger.shake].
  /// [theme] - Custom theme for the overlay UI. Defaults to [BlackBoxThemeData.dark].
  /// [ignoredRebuildWidgets] - List of widget names to exclude from rebuild tracking.
  /// [enabled] - If the library should be active. Defaults to [kDebugMode].
  /// [redactSensitiveData] - Whether to mask sensitive keys in storage and network panels.
  /// [networkRedactor] - Custom redactor for network payload sanitisation.
  /// [maxRebuildTrackCount] - Maximum unique widgets to track rebuilds for. Defaults to 500.
  static void setup({
    List<BlackBoxHttpAdapter> httpAdapters = const [],
    List<BlackBoxSocketAdapter> socketAdapters = const [],
    BlackBoxLogAdapter? logAdapter,
    List<BlackBoxStorageAdapter> storageAdapters = const [],
    List<BlackBoxObserver> observers = const [],
    BlackBoxTrigger trigger = const BlackBoxTrigger.shake(),
    BlackBoxThemeData theme = const BlackBoxThemeData.dark(),
    List<String> ignoredRebuildWidgets = const [],
    NetworkRedactor? networkRedactor,
    bool? enabled,
    bool redactSensitiveData = true,
    int maxRebuildTrackCount = 500,
  }) {
    final dk = _instance;

    // ── Tear down previous setup (idempotent) ──────────────────────────
    dk._logAdapter?.detach();
    for (final a in dk._httpAdapters) {
      a.detach();
    }
    for (final a in dk._socketAdapters) {
      a.detach();
    }
    dk._journeySub?.cancel();
    dk.fpsMonitor.stop();
    dk._httpAdapters.clear();
    dk._socketAdapters.clear();
    dk._storageAdapters.clear();
    dk._observers.clear();

    dk._enabled = enabled ?? kDebugMode;
    dk._redactSensitiveData = redactSensitiveData;
    dk._theme = theme;
    dk.rebuildStore.capacity = maxRebuildTrackCount;

    // ── Network store with optional redactor ───────────────────────────
    dk.networkStore.dispose();
    final effectiveRedactor =
        redactSensitiveData ? (networkRedactor ?? NetworkRedactor()) : null;
    dk.networkStore = NetworkStore(redactor: effectiveRedactor);

    // Clear all other stores to prevent memory buildup / data bleed between setup runs (e.g. across unit tests)
    dk.logStore.clear();
    dk.crashStore.clear();
    dk.socketStore.clear();
    dk.rebuildStore.reset();
    dk.navigationStore.clear();
    dk.journeyStore.clear();

    dk._trigger = trigger;
    _userIgnoredWidgets.clear();
    if (ignoredRebuildWidgets.isNotEmpty) {
      _userIgnoredWidgets.addAll(ignoredRebuildWidgets);
    }

    if (!dk._enabled) return;

    // ── Log adapter ────────────────────────────────────────────────────
    final la = logAdapter ?? PrintLogAdapter();
    dk._logAdapter = la;
    la.onLogCallback = (entry) => dk.logStore.add(entry);
    la.attach();

    // ── HTTP adapters ──────────────────────────────────────────────────
    for (final adapter in httpAdapters) {
      adapter.onRequestCallback = dk.networkStore.onRequest;
      adapter.onResponseCallback = dk.networkStore.onResponse;
      adapter.interceptCallback = dk.mockEngine.intercept;
      adapter.attach();
      dk._httpAdapters.add(adapter);
    }

    // ── Journey tracking + observer notification for API calls ────────
    dk._journeySub = dk.networkStore.stream.listen((entries) {
      if (entries.isNotEmpty) {
        final last = entries.last;
        if (last.response != null) {
          dk.journeyStore.record(ApiEvent(
            DateTime.now(),
            method: last.request.method,
            url: last.request.url,
            statusCode: last.response!.statusCode,
          ));
          // Notify observers about network activity
          dk._notifyObserversNetwork(last);
        }
      }
    });

    // ── Storage adapters ────────────────────────────────────────────────
    dk._storageAdapters.addAll(storageAdapters);

    // ── Observers ───────────────────────────────────────────────────────
    dk._observers.addAll(observers);

    // ── Socket adapters ─────────────────────────────────────────────────
    for (final adapter in socketAdapters) {
      adapter.onEventCallback = dk.socketStore.onEvent;
      adapter.attach();
      dk._socketAdapters.add(adapter);
    }

    // ── FPS monitor ────────────────────────────────────────────────────
    dk.fpsMonitor.start();

    // ── Crash handling ─────────────────────────────────────────────────
    dk._hookCrashHandlers();
  }

  void _hookCrashHandlers() {
    _originalFlutterError ??= FlutterError.onError;
    _originalPlatformError ??= PlatformDispatcher.instance.onError;

    FlutterError.onError = (FlutterErrorDetails details) {
      if (_enabled) {
        final now = DateTime.now();
        final crash = CrashEntry(
          id: 'crash_${_idCounter++}',
          message: details.exceptionAsString(),
          stackTrace: details.stack,
          library: details.library,
          timestamp: now,
          isFlutterError: true,
        );
        crashStore.add(crash);
        _notifyObserversCrash(crash);
        BlackBox.log(
          details.exceptionAsString(),
          level: LogLevel.error,
          tag: 'Crash',
          error: details.exception,
          stackTrace: details.stack,
        );
        scheduleMicrotask(() => BlackBox.open());
      }
      _originalFlutterError?.call(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      if (_enabled) {
        final now = DateTime.now();
        final crash = CrashEntry(
          id: 'crash_${_idCounter++}',
          message: error.toString(),
          stackTrace: stack,
          timestamp: now,
          isFlutterError: false,
        );
        crashStore.add(crash);
        _notifyObserversCrash(crash);
        BlackBox.log(
          error.toString(),
          level: LogLevel.error,
          tag: 'Crash',
          error: error,
          stackTrace: stack,
        );
        scheduleMicrotask(() => BlackBox.open());
      }
      final handled = _originalPlatformError?.call(error, stack) ?? false;
      return handled;
    };
  }

  // ── Logging ──────────────────────────────────────────────────────────

  /// Logs a custom message to the BlackBox log store.
  ///
  /// [message] - The log message.
  /// [level] - Importance of the log (debug, info, warning, error).
  /// [tag] - Optional category for filtering (e.g., 'Auth', 'UI').
  /// [data] - Optional metadata map.
  /// [error] - Associated error object.
  /// [stackTrace] - Associated stack trace.
  static void log(
    String message, {
    LogLevel level = LogLevel.debug,
    String? tag,
    Map<String, dynamic>? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!_instance._enabled) return;
    final now = DateTime.now();
    final entry = LogEntry(
      id: 'log_${_idCounter++}',
      level: level,
      message: message,
      timestamp: now,
      tag: tag,
      data: data,
      error: error,
      stackTrace: stackTrace,
    );
    _instance.logStore.add(entry);
    _instance._notifyObserversLog(entry);

    final tagStr = tag != null ? '[$tag] ' : '';
    final dataStr = data != null ? ' | Data: $data' : '';
    final errStr = error != null ? ' | Error: $error' : '';
    dev.log('[${level.name.toUpperCase()}] $tagStr$message$dataStr$errStr',
        name: 'BlackBox');
  }

  // ── Rebuild tracking ────────────────────────────────────────────────

  /// Start automatic rebuild tracking for ALL widgets.
  /// Uses Flutter's `debugPrintRebuildDirtyWidgets` (debug mode only).
  static void startRebuildTracking() {
    if (!kDebugMode) return;
    final dk = _instance;
    dk._autoRebuildTracking = true;
    debugPrintRebuildDirtyWidgets = true;

    dk._originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null &&
          (message.startsWith('Rebuilding ') ||
              message.startsWith('Building '))) {
        // Flutter's format: "Rebuilding WidgetName(dirty)"
        final name = _parseWidgetName(message);
        if (name != null) {
          dk.rebuildStore.record(name);
        }
        // Suppress the log from printing to the IDE console to prevent extreme spam
        return;
      }
      dk._originalDebugPrint?.call(message ?? '', wrapWidth: wrapWidth ?? 100);
    };
  }

  /// Stop automatic rebuild tracking.
  static void stopRebuildTracking() {
    final dk = _instance;
    dk._autoRebuildTracking = false;
    debugPrintRebuildDirtyWidgets = false;
    if (dk._originalDebugPrint != null) {
      debugPrint = dk._originalDebugPrint!;
      dk._originalDebugPrint = null;
    }
  }

  // Built-in widgets to ignore — immutable defaults.
  static const _defaultIgnoredWidgets = <String>{
    'Text', 'Container', 'Padding', 'SizedBox', 'Column', 'Row', 'Align',
    'Center', 'Positioned', 'Expanded', 'Flexible', 'Stack', 'ListView',
    'GestureDetector', 'InkWell', 'ConstrainedBox', 'DecoratedBox', 'Theme',
    'Opacity', 'Transform', 'ClipRRect', 'ClipOval', 'ClipPath', 'ClipRect',
    'IgnorePointer', 'AbsorbPointer', 'RepaintBoundary', 'FittedBox',
    'FractionallySizedBox', 'LayoutBuilder', 'Builder', 'StatefulBuilder',
    'StreamBuilder', 'FutureBuilder', 'ValueListenableBuilder',
    'AnimatedBuilder', 'Icon', 'Image', 'RichText', 'DefaultTextStyle',
    'MediaQuery', 'Directionality', 'Visibility', 'Scaffold', 'AppBar',
    'BottomNavigationBar', 'FloatingActionButton', 'Drawer', 'GridView',
    'SingleChildScrollView', 'CustomScrollView', 'SliverToBoxAdapter',
    'SliverList', 'SliverGrid', 'Card', 'Divider', 'ListTile', 'Placeholder',
    'Tooltip', 'SafeArea', 'Hero', 'Material', 'Ink', 'AnimatedContainer',
    'AnimatedPadding', 'AnimatedOpacity', 'AnimatedCrossFade',
    'AnimatedSwitcher', 'AnimatedSize', 'AnimatedPositioned', 'Wrap',
    'Flow', 'Table', 'PageView', 'Scrollbar', 'RefreshIndicator', 'Navigator',
    'Overlay', 'FocusScope', 'KeyedSubtree', 'Semantics', 'MergeSemantics',
    'ExcludeSemantics', 'ColoredBox', 'FractionalTranslation', 'RotatedBox',
    'BackdropFilter', 'PhysicalModel', 'PhysicalShape', 'CustomPaint',
    'Offstage', 'TickerMode', 'Focus', 'FocusNode', 'FocusTraversalGroup',
    'UnmanagedRestorationScope', 'RestorationScope', 'NotificationListener',
    'ScrollConfiguration', 'Scrollable', 'MouseRegion', 'Listener',
    'SemanticsDebugger', 'AnimatedTheme', 'IconTheme', 'ColorFiltered',
    'AnimatedDefaultTextStyle', 'PrimaryScrollController', 'SharedAppData',
    'MatrixTransition', 'Consumer', 'Provider', 'Selector', 'BlocBuilder',
    'BlocProvider', 'BlocListener', 'BlocConsumer', 'GetBuilder', 'Obx',
    'AutomaticKeepAlive', 'KeepAlive', 'Viewport', 'ShrinkWrappingViewport',
    'SliverPadding', 'RawScrollbar', 'RawGestureDetector', 'ScrollSemantics',
    'ScrollBehavior', 'GlowingOverscrollIndicator',
    'OverscrollIndicatorNotification',
    // 60fps Animators & deep framework listeners
    'LinearProgressIndicator', 'CircularProgressIndicator',
    'CupertinoActivityIndicator',
    'StretchingOverscrollIndicator', 'ListenableBuilder', 'Actions',
    'TweenAnimationBuilder',
    'AnimatedWidget', 'RotationTransition', 'ScaleTransition', 'SizeTransition',
    // Internal Overlay/Blackbox widgets (to prevent infinite loops)
    'BlackBoxOverlay', 'DevkitOverlay', 'RebuildTrackerWidget',
    '_RebuildTrackerWidgetState',
    'TouchEater', 'Draggable', 'PositionedTransition', 'SlideTransition',
    // Riverpod internal widgets
    'ConsumerWidget', 'HookConsumerWidget', 'StatefulHookConsumerWidget',
  };

  // User-supplied additions — cleared and re-populated on each setup() call.
  static final _userIgnoredWidgets = <String>{};

  // Pre-compiled RegExp — avoids recompiling on every rebuild callback.
  static final _rebuildRegExp = RegExp(r'(?:Building|Rebuilding)\s+(\w+)\(');

  static String? _parseWidgetName(String message) {
    // Flutter debug output: "Rebuilding MyWidget(dirty, state: _MyWidgetState#abc12)"
    final match = _rebuildRegExp.firstMatch(message.trim());
    if (match != null) {
      final name = match.group(1)!;
      // Filter out framework-internal or noisy widgets
      if (name.startsWith('_') ||
          _defaultIgnoredWidgets.contains(name) ||
          _userIgnoredWidgets.contains(name)) {
        return null;
      }
      return name;
    }
    return null;
  }

  // ── Socket IO ──────────────────────────────────────────────────────────

  /// Manually log a socket event.
  ///
  /// Prefer using [BlackBoxSocketAdapter] (e.g. `SocketIOBlackBoxAdapter`)
  /// which captures events automatically without code changes.
  ///
  /// This method is provided as a **fallback** for socket libraries that
  /// don't have a built-in adapter yet.
  static void logSocketEvent(
    String eventName,
    dynamic data, {
    SocketDirection direction = SocketDirection.incoming,
  }) {
    if (!_instance._enabled) return;
    final now = DateTime.now();
    final event = SocketEvent(
      id: 'soc_${_idCounter++}',
      eventName: eventName,
      data: data,
      timestamp: now,
      direction: direction,
    );
    _instance.socketStore.onEvent(event);
  }

  // ── Network mocking ───────────────────────────────────────────────────

  /// Register a mock rule. Active immediately — no restart needed.
  static String mock({
    required Object pattern,
    String method = '*',
    required MockResponse response,
  }) {
    return _instance.mockEngine.addRule(
      pattern: pattern,
      method: method,
      response: response,
    );
  }

  /// Removes a mock rule by its ID.
  static void removeMock(String id) => _instance.mockEngine.removeRule(id);

  // ── Overlay control ───────────────────────────────────────────────────

  /// Programmatically opens the BlackBox overlay.
  static void open() => _instance._openOverlay?.call();

  /// Programmatically closes the BlackBox overlay.
  static void close() => _instance._closeOverlay?.call();

  /// Programmatically toggles the BlackBox overlay visibility.
  static void toggle() => _instance._toggleOverlay?.call();

  // ── Report ────────────────────────────────────────────────────────────

  /// Build a [BlackBoxReport] from current store state.
  static Future<BlackBoxReport> buildReport({
    String? bugTitle,
    BugSeverity severity = BugSeverity.medium,
    String? notes,
    List<int>? screenshotPngBytes,
  }) async {
    final dk = _instance;
    return BlackBoxReport(
      bugTitle: bugTitle,
      severity: severity,
      timestamp: DateTime.now(),
      appInfo: await _appInfo() ?? {},
      deviceInfo: await _getDeviceInfo(),
      userJourney: dk.journeyStore.numberedSteps,
      failedRequests: dk.networkStore.entries
          .where((e) => e.response != null && e.response!.statusCode >= 400)
          .map((e) => {
                'request': e.request.toJson(),
                'response': e.response!.toJson(),
              })
          .toList(),
      logs: dk.logStore.toJson(),
      networkRequests: dk.networkStore.toJson(),
      socketEvents: dk.socketStore.toJson(),
      crashes: dk.crashStore.toJson(),
      screenshotPngBytes: screenshotPngBytes,
      notes: notes,
    );
  }

  // ── Dispose ───────────────────────────────────────────────────────────

  static void dispose() {
    final dk = _instance;

    if (dk._originalFlutterError != null) {
      FlutterError.onError = dk._originalFlutterError;
      dk._originalFlutterError = null;
    }
    if (dk._originalPlatformError != null) {
      PlatformDispatcher.instance.onError = dk._originalPlatformError;
      dk._originalPlatformError = null;
    }

    dk._journeySub?.cancel();
    dk._journeySub = null;
    dk._logAdapter?.detach();
    dk._logAdapter = null;
    for (final a in dk._httpAdapters) {
      a.detach();
    }
    for (final a in dk._socketAdapters) {
      a.detach();
    }
    dk.fpsMonitor.dispose();
    dk.logStore.dispose();
    dk.networkStore.dispose();
    dk.crashStore.dispose();
    dk.socketStore.dispose();
    dk.rebuildStore.dispose();
    dk.navigationStore.dispose();
    dk.journeyStore.clear();
    dk._httpAdapters.clear();
    dk._socketAdapters.clear();
    dk._storageAdapters.clear();
    dk._observers.clear();
    dk._openOverlay = null;
    dk._closeOverlay = null;
    dk._toggleOverlay = null;
    dk._enabled = false;
    BlackBox.stopRebuildTracking();
  }

  // ── Observer notifications ───────────────────────────────────────────

  void _notifyObserversCrash(CrashEntry crash) {
    for (final observer in _observers) {
      try {
        observer.onCrash(crash);
      } catch (_) {
        // Never let an observer crash take down the app.
      }
    }
  }

  void _notifyObserversLog(LogEntry log) {
    for (final observer in _observers) {
      try {
        observer.onLog(log);
      } catch (_) {
        // Never let an observer crash take down the app.
      }
    }
  }

  void _notifyObserversNetwork(NetworkEntry entry) {
    final res = entry.response;
    if (res == null) return;

    for (final observer in _observers) {
      try {
        if (res.statusCode >= 400 ||
            res.failureType != NetworkFailureType.none) {
          observer.onNetworkError(entry);
        } else {
          observer.onNetworkResponse(entry);
        }
      } catch (_) {
        // Never let an observer crash take down the app.
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  static Future<Map<String, String>?> _appInfo() async {
    return await getPackageInfo();
  }

  // ── Device Info Parsing ───────────────────────────────────────────────

  static BlackBoxDeviceInfo? _cachedDeviceInfo;

  static Future<BlackBoxDeviceInfo> _getDeviceInfo() async {
    return _cachedDeviceInfo ??= await _fetchDeviceInfo();
  }

  static Future<BlackBoxDeviceInfo> _fetchDeviceInfo() async {
    return await fetchPlatformDeviceInfo();
  }
}
