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
import 'core/performance/memory_info.dart' as memory_info;
import 'core/report/blackbox_device_info.dart';
import 'core/report/blackbox_report.dart';
import 'core/socket/socket_event.dart';
import 'core/socket/socket_store.dart';
import 'overlay/blackbox_trigger.dart';
import 'overlay/widgets/blackbox_theme.dart';
import 'companion/firebase_streamer.dart';

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
  /// Reconfigured in [setup] while preserving its stream identity.
  final networkStore = NetworkStore();

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

  StreamSubscription<NetworkEntry>? _journeySub;
  StreamSubscription<FpsSnapshot>? _fpsSub;

  // ── Rebuild tracking state ────────────────────────────────────────────

  bool _autoRebuildTracking = false;
  DebugPrintCallback? _originalDebugPrint;

  /// Whether the overlay is globally enabled.
  /// When `false`, [setup] and [BlackBoxOverlay] become no-ops.
  bool get isEnabled => _enabled;

  /// Whether BlackBox is currently accepting new diagnostic events.
  static bool get isCapturing =>
      _instance._enabled && !_instance._capturePaused;

  /// Capture state used by the existing overlay controls.
  ValueListenable<bool> get captureStateListenable => _captureState;

  /// Process RSS measured when the current capture session was reset.
  int get captureBaselineRss => _captureBaselineRss;

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
  bool _capturePaused = false;
  final _RefreshableValueNotifier<bool> _captureState =
      _RefreshableValueNotifier<bool>(kDebugMode);
  int _captureBaselineRss = 0;
  bool _redactSensitiveData = true;
  BlackBoxTrigger _trigger = const BlackBoxTrigger.shake();
  BlackBoxThemeData _theme = const BlackBoxThemeData.dark();
  final List<BlackBoxHttpAdapter> _httpAdapters = [];
  final List<BlackBoxSocketAdapter> _socketAdapters = [];
  BlackBoxLogAdapter? _logAdapter;
  FlutterExceptionHandler? _originalFlutterError;
  bool Function(Object, StackTrace)? _originalPlatformError;
  bool _crashHandlersInstalled = false;

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
  VoidCallback? _startAnnotation;
  VoidCallback? _clearAnnotations;
  Object? _overlayCallbackOwner;

  void registerOverlayCallbacks({
    Object? owner,
    required VoidCallback open,
    required VoidCallback close,
    required VoidCallback toggle,
    required VoidCallback startAnnotation,
    required VoidCallback clearAnnotations,
  }) {
    _overlayCallbackOwner = owner;
    _openOverlay = open;
    _closeOverlay = close;
    _toggleOverlay = toggle;
    _startAnnotation = startAnnotation;
    _clearAnnotations = clearAnnotations;
  }

  /// Removes callbacks owned by a disposed overlay without clearing callbacks
  /// that may already belong to a newer overlay instance.
  void unregisterOverlayCallbacks(Object owner) {
    if (!identical(_overlayCallbackOwner, owner)) return;
    _overlayCallbackOwner = null;
    _openOverlay = null;
    _closeOverlay = null;
    _toggleOverlay = null;
    _startAnnotation = null;
    _clearAnnotations = null;
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
  /// [routeNameResolver] - Optional fallback for applications using unnamed routes.
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
    String? Function(Route<dynamic> route)? routeNameResolver,
  }) {
    dev.Timeline.startSync('BlackBox.setup');
    final dk = _instance;
    try {
      // Tear down prior runtime hooks without closing singleton streams.
      dk._tearDownRuntime();

      dk._enabled = enabled ?? kDebugMode;
      dk._capturePaused = false;
      dk._captureState.value = dk._enabled;
      dk._redactSensitiveData = redactSensitiveData;
      dk._theme = theme;
      dk.rebuildStore.capacity = maxRebuildTrackCount;
      journeyObserver.routeNameResolver = routeNameResolver;

      final effectiveRedactor =
          redactSensitiveData ? (networkRedactor ?? NetworkRedactor()) : null;
      dk.networkStore.reconfigure(redactor: effectiveRedactor);
      dk._clearCapturedData(notify: true, includeNetwork: false);

      dk._trigger = trigger;
      _userIgnoredWidgets.clear();
      if (ignoredRebuildWidgets.isNotEmpty) {
        _userIgnoredWidgets.addAll(ignoredRebuildWidgets);
      }

      if (!dk._enabled) return;

      // ── Log adapter ────────────────────────────────────────────────────
      final la = logAdapter ?? PrintLogAdapter();
      dk._logAdapter = la;
      la.onLogCallback = (entry) {
        if (BlackBox.isCapturing) dk.logStore.add(entry);
      };
      la.attach();

      // ── HTTP adapters ──────────────────────────────────────────────────
      for (final adapter in httpAdapters) {
        adapter.onRequestCallback = (request) {
          if (BlackBox.isCapturing) dk.networkStore.onRequest(request);
        };
        // A response may complete a request captured immediately before pause.
        adapter.onResponseCallback = dk.networkStore.onResponse;
        adapter.interceptCallback = dk.mockEngine.intercept;
        dk._httpAdapters.add(adapter);
        adapter.attach();
      }

      // ── Journey tracking + observer notification for API calls ────────
      dk._journeySub = dk.networkStore.completedStream.listen((entry) {
        if (!BlackBox.isCapturing || entry.response == null) return;
        dk.journeyStore.record(ApiEvent(
          DateTime.now(),
          method: entry.request.method,
          url: entry.request.url,
          statusCode: entry.response!.statusCode,
        ));
        dk._notifyObserversNetwork(entry);
      });

      // ── Storage adapters ────────────────────────────────────────────────
      dk._storageAdapters.addAll(storageAdapters);

      // ── Observers ───────────────────────────────────────────────────────
      dk._observers.addAll(observers);

      // ── Socket adapters ─────────────────────────────────────────────────
      for (final adapter in socketAdapters) {
        adapter.onEventCallback = (event) {
          if (BlackBox.isCapturing) dk.socketStore.onEvent(event);
        };
        dk._socketAdapters.add(adapter);
        adapter.attach();
      }

      // ── FPS monitor ────────────────────────────────────────────────────
      dk.fpsMonitor.start();
      int lastFpsBroadcastMs = 0;
      dk._fpsSub = dk.fpsMonitor.stream.listen((snapshot) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        // Broadcast every 500ms for near-real-time performance charts.
        if (nowMs - lastFpsBroadcastMs >= 500) {
          FirebaseStreamer.instance.broadcast('performance', {
            'fps': snapshot.fps,
            'avgFrameMs': snapshot.avgFrameMs,
          });
          lastFpsBroadcastMs = nowMs;
        }
      });

      // ── Crash handling ─────────────────────────────────────────────────
      dk._hookCrashHandlers();
    } catch (_) {
      // Do not leave half-attached adapters or global handlers behind when
      // application-provided setup code throws.
      dk._tearDownRuntime();
      rethrow;
    } finally {
      dev.Timeline.finishSync();
    }
  }

  void _tearDownRuntime() {
    if (_autoRebuildTracking) BlackBox.stopRebuildTracking();
    _enabled = false;
    _capturePaused = false;
    _captureState.value = false;

    if (_crashHandlersInstalled) {
      FlutterError.onError = _originalFlutterError;
      PlatformDispatcher.instance.onError = _originalPlatformError;
      _crashHandlersInstalled = false;
    }
    _originalFlutterError = null;
    _originalPlatformError = null;
    journeyObserver.routeNameResolver = null;

    unawaited(_journeySub?.cancel());
    _journeySub = null;
    unawaited(_fpsSub?.cancel());
    _fpsSub = null;
    fpsMonitor.pause();
    FirebaseStreamer.instance.stop();

    final logAdapter = _logAdapter;
    try {
      logAdapter?.detach();
    } catch (_) {
      // Teardown is best-effort so one adapter cannot strand the others.
    }
    logAdapter?.onLogCallback = null;
    _logAdapter = null;
    for (final adapter in _httpAdapters) {
      try {
        adapter.detach();
      } catch (_) {
        // Continue detaching the remaining adapters.
      }
      adapter.onRequestCallback = null;
      adapter.onResponseCallback = null;
      adapter.interceptCallback = null;
    }
    for (final adapter in _socketAdapters) {
      try {
        adapter.detach();
      } catch (_) {
        // Continue detaching the remaining adapters.
      }
      adapter.onEventCallback = null;
    }
    _httpAdapters.clear();
    _socketAdapters.clear();
    _storageAdapters.clear();
    _observers.clear();
  }

  void _clearCapturedData({required bool notify, bool includeNetwork = true}) {
    if (includeNetwork) networkStore.clear(notify: notify);
    logStore.clear(notify: notify);
    crashStore.clear(notify: notify);
    socketStore.clear(notify: notify);
    rebuildStore.reset(notify: notify);
    navigationStore.clear(notify: notify);
    journeyStore.clear();
    fpsMonitor.reset(notify: notify);
    FirebaseStreamer.instance.resetMetrics();
    try {
      _captureBaselineRss = _enabled ? memory_info.getCurrentRss() : 0;
    } catch (_) {
      _captureBaselineRss = 0;
    }
  }

  void _hookCrashHandlers() {
    if (_crashHandlersInstalled) return;
    _originalFlutterError = FlutterError.onError;
    _originalPlatformError = PlatformDispatcher.instance.onError;
    _crashHandlersInstalled = true;

    FlutterError.onError = (FlutterErrorDetails details) {
      if (BlackBox.isCapturing) {
        final now = DateTime.now();
        final String exceptionStr = details.exceptionAsString();
        final String fullDetails = details.toString();

        final crash = CrashEntry(
          id: 'crash_${_idCounter++}',
          message: fullDetails,
          stackTrace: details.stack,
          library: details.library,
          timestamp: now,
          isFlutterError: true,
        );
        crashStore.add(crash);
        _notifyObserversCrash(crash);

        BlackBox.log(
          exceptionStr,
          level: LogLevel.error,
          tag: 'Crash',
          data: {'details': fullDetails},
          error: details.exception,
          stackTrace: details.stack,
        );
        if (details.library != 'rendering library') {
          scheduleMicrotask(() => BlackBox.open());
        }
      }
      _originalFlutterError?.call(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      if (BlackBox.isCapturing) {
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
    if (!BlackBox.isCapturing) return;
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

  /// Manually records an error or exception to the Crash Store.
  ///
  /// This is useful for try-catch blocks where you want to report an error
  /// directly to BlackBox (and its connected observers like Crashlytics)
  /// without crashing the app.
  static void recordError(
    dynamic exception,
    StackTrace? stack, {
    dynamic reason,
    bool isFatal = false,
    bool printDetails = true,
  }) {
    if (!BlackBox.isCapturing) return;

    final now = DateTime.now();
    final message =
        reason != null ? '$reason: $exception' : exception.toString();

    final crash = CrashEntry(
      id: 'crash_${_idCounter++}',
      message: message,
      stackTrace: stack,
      timestamp: now,
      isFlutterError: false,
    );

    _instance.crashStore.add(crash);
    _instance._notifyObserversCrash(crash);

    BlackBox.log(
      message,
      level: LogLevel.error,
      tag: isFatal ? 'Fatal Crash' : 'Caught Error',
      error: exception,
      stackTrace: stack,
    );

    if (printDetails) {
      dev.log(
        message,
        name: 'BlackBox.recordError',
        error: exception,
        stackTrace: stack,
        level: 1000, // SEVERE
      );
    }
  }

  // ── Rebuild tracking ────────────────────────────────────────────────

  /// Start automatic rebuild tracking for ALL widgets.
  /// Uses Flutter's `debugPrintRebuildDirtyWidgets` (debug mode only).
  static void startRebuildTracking() {
    if (!kDebugMode || !BlackBox.isCapturing) return;
    final dk = _instance;
    if (dk._autoRebuildTracking) return;
    dk._autoRebuildTracking = true;
    debugPrintRebuildDirtyWidgets = true;

    dk._originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null &&
          (message.startsWith('Rebuilding ') ||
              message.startsWith('Building '))) {
        // Flutter's format: "Rebuilding WidgetName(dirty)"
        final name = _parseWidgetName(message);
        if (name != null && BlackBox.isCapturing) {
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
    if (!BlackBox.isCapturing) return;
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
  static void open() {
    if (_instance._enabled) _instance._openOverlay?.call();
  }

  /// Programmatically closes the BlackBox overlay.
  static void close() => _instance._closeOverlay?.call();

  /// Programmatically Toggles the BlackBox overlay's visibility.
  static void toggle() {
    if (_instance._enabled) _instance._toggleOverlay?.call();
  }

  /// Starts the QA annotation mode.
  static void startAnnotation() {
    if (_instance._enabled) _instance._startAnnotation?.call();
  }

  /// Clears any existing QA annotations.
  static void clearAnnotations() {
    _instance._clearAnnotations?.call();
  }

  /// Pauses new capture while retaining the current diagnostic session.
  static void pauseCapture() {
    final dk = _instance;
    if (!dk._enabled || dk._capturePaused) return;
    dk._capturePaused = true;
    dk._captureState.value = false;
    dk.fpsMonitor.pause();
  }

  /// Resumes capture without clearing previously captured diagnostics.
  static void resumeCapture() {
    final dk = _instance;
    if (!dk._enabled || !dk._capturePaused) return;
    dk._capturePaused = false;
    dk._captureState.value = true;
    dk.fpsMonitor.resume();
  }

  /// Clears captured diagnostics without changing whether capture is paused.
  static void clearCapturedData() {
    final dk = _instance;
    dk._clearCapturedData(notify: true);
    dk._clearAnnotations?.call();
    dk._captureState.refresh();
  }

  // ── Report ────────────────────────────────────────────────────────────

  /// Build a [BlackBoxReport] from current store state.
  static Future<BlackBoxReport> buildReport({
    String? bugTitle,
    BugSeverity severity = BugSeverity.medium,
    String? notes,
    List<int>? screenshotPngBytes,
  }) async {
    final dk = _instance;
    final journey = List<String>.from(dk.journeyStore.numberedSteps);
    final network = dk.networkStore.toJson();
    final failedRequests = network.where((entry) {
      final response = entry['response'];
      return response is Map<String, dynamic> &&
          response['statusCode'] is int &&
          (response['statusCode'] as int) >= 400;
    }).toList(growable: false);
    final logs = dk.logStore.toJson();
    final sockets = dk.socketStore.toJson();
    final crashes = dk.crashStore.toJson();
    final appInfo = await _appInfo() ?? <String, String>{};
    final deviceInfo = await _getDeviceInfo();
    return BlackBoxReport(
      bugTitle: bugTitle,
      severity: severity,
      timestamp: DateTime.now(),
      appInfo: appInfo,
      deviceInfo: deviceInfo,
      userJourney: journey,
      failedRequests: failedRequests,
      logs: logs,
      networkRequests: network,
      socketEvents: sockets,
      crashes: crashes,
      screenshotPngBytes: screenshotPngBytes,
      notes: notes,
    );
  }

  /// Uploads a generated [report] to Firebase Realtime Database for viewing
  /// on the companion web dashboard. Returns the assigned `reportId` on success.
  static Future<String?> uploadReport(BlackBoxReport report) =>
      FirebaseStreamer.instance.uploadReport(report);

  // ── Dispose ───────────────────────────────────────────────────────────

  static void dispose() {
    final dk = _instance;
    dk._tearDownRuntime();
    dk._clearCapturedData(notify: false);
  }

  // ── Observer notifications ───────────────────────────────────────────

  void _notifyObserversCrash(CrashEntry crash) {
    FirebaseStreamer.instance.broadcast('crashes', crash.toJson());
    for (final observer in _observers) {
      try {
        observer.onCrash(crash);
      } catch (_) {
        // Never let an observer crash take down the app.
      }
    }
  }

  /// Broadcasts device info and app info to the companion web dashboard.
  /// Called once when the companion session connects.
  static Future<void> broadcastDeviceInfo() async {
    try {
      final deviceInfo = await _getDeviceInfo();
      final appInfo = await _appInfo();
      FirebaseStreamer.instance.deviceName = deviceInfo.deviceModel;
      FirebaseStreamer.instance.broadcast('deviceInfo', {
        ...deviceInfo.toJson(),
        if (appInfo != null) ...appInfo,
      });
    } catch (_) {
      // Don't crash the app if device info fails.
    }
  }

  void _notifyObserversLog(LogEntry log) {
    FirebaseStreamer.instance.broadcast('logs', log.toJson());
    for (final observer in _observers) {
      try {
        observer.onLog(log);
      } catch (_) {
        // Never let an observer crash take down the app.
      }
    }
  }

  void _notifyObserversNetwork(NetworkEntry entry) {
    FirebaseStreamer.instance.broadcast('network', {
      'request': entry.request.toJson(),
      'response': entry.response?.toJson(),
    });
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

class _RefreshableValueNotifier<T> extends ValueNotifier<T> {
  _RefreshableValueNotifier(super.value);

  void refresh() => notifyListeners();
}
