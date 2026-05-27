import 'dart:async';
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../blackbox.dart';
import '../core/network/network_store.dart';
import '../core/crash/crash_entry.dart';
import '../core/performance/fps_monitor.dart';
import 'blackbox_trigger.dart';
import 'panels/log_panel.dart';
import 'panels/navigation_panel.dart';
import 'panels/network_panel.dart';
import 'panels/performance_panel.dart';
import 'panels/rebuild_panel.dart';
import 'panels/search_panel.dart';
import 'panels/socket_panel.dart';
import 'panels/storage_panel.dart';
import 'panels/device_panel.dart';
import 'panels/qa_panel.dart';
import 'widgets/blackbox_theme.dart';

/// Wrap your [MaterialApp] (or [CupertinoApp]) with this widget.
///
/// It inserts a transparent [Overlay] above your app's Navigator so
/// the debug panel never interferes with routing, back gestures, or
/// bottom sheets.
///
/// ```dart
/// runApp(BlackBoxOverlay(child: const MyApp()));
/// ```
class BlackBoxOverlay extends StatefulWidget {
  /// Creates an overlay wrapper.
  const BlackBoxOverlay({super.key, required this.child});

  /// The root application widget (usually your [MaterialApp]).
  final Widget child;

  /// A builder method to guarantee correct widget nesting order natively.
  /// Pass this directly to [MaterialApp.builder] or [CupertinoApp.builder].
  ///
  /// ```dart
  /// MaterialApp(
  ///   builder: BlackBoxOverlay.builder(),
  /// )
  /// ```
  static Widget Function(BuildContext, Widget?) builder() {
    return (BuildContext context, Widget? child) {
      return BlackBoxOverlay(
        child: child ?? const SizedBox.shrink(),
      );
    };
  }

  @override
  State<BlackBoxOverlay> createState() => _BlackBoxOverlayState();
}

class _BlackBoxOverlayState extends State<BlackBoxOverlay>
    with SingleTickerProviderStateMixin {
  bool _isVisible = false;
  bool _isHudPinned = false;
  final _repaintKey = GlobalKey();
  late final AnimationController _animController;

  // ── Resizable panel state ─────────────────────────────────────────
  final _panelHeightFraction = ValueNotifier<double>(0.95);
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  // A stable global key for the internal navigator.
  // This prevents the navigator (and its internal Overlay/OverlayEntry items)
  // from being needlessly destroyed and recreated during parent rebuilds
  // (such as when the keyboard opens/closes triggering a MediaQuery update).
  static final GlobalKey<NavigatorState> _navigatorKey =
      GlobalKey<NavigatorState>();

  // Stored handler reference for cleanup.
  KeyEventCallback? _keyHandler;

  // Shake detection.
  // Full shake detection requires sensors_plus (blackbox_sensors companion).
  // onShakeDetected() is the hook called by that companion package.
  // Without it, use BlackBoxTrigger.floatingButton() or BlackBoxTrigger.hotkey().
  // static const _shakeGravity = 9.8;
  DateTime _lastShake = DateTime.now();

  /// Entry point for shake detection from blackbox_sensors companion.
  void onShakeDetected() {
    final now = DateTime.now();
    if (now.difference(_lastShake).inMilliseconds < 1000) return;
    _lastShake = now;
    _toggle();
  }

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
    ));

    BlackBox.instance.registerOverlayCallbacks(
      open: _open,
      close: _close,
      toggle: _toggle,
    );

    _setupTrigger();
  }

  void _setupTrigger() {
    final trigger = BlackBox.instance.trigger;
    switch (trigger) {
      case HotkeyTrigger(:final key, :final ctrl, :final shift):
        _keyHandler = _handleKey(key, ctrl, shift);
        HardwareKeyboard.instance.addHandler(_keyHandler!);
      case ShakeTrigger():
      // Full shake requires sensors_plus via blackbox_sensors companion.
      // Call state.onShakeDetected() from your accelerometer listener.
      case FloatingButtonTrigger():
      case NoneTrigger():
    }
  }

  KeyEventCallback _handleKey(LogicalKeyboardKey key, bool ctrl, bool shift) {
    return (KeyEvent event) {
      if (event is! KeyDownEvent) return false;
      final ctrlHeld = HardwareKeyboard.instance.isControlPressed;
      final shiftHeld = HardwareKeyboard.instance.isShiftPressed;
      if (event.logicalKey == key &&
          (!ctrl || ctrlHeld) &&
          (!shift || shiftHeld)) {
        _toggle();
        return true;
      }
      return false;
    };
  }

  void _open() {
    if (_isVisible) return;
    HapticFeedback.mediumImpact();
    setState(() => _isVisible = true);
    _animController.forward();
  }

  void _close() {
    if (!_isVisible) return; // Guard against double-close
    HapticFeedback.lightImpact();
    _isVisible = false; // Mark immediately to prevent re-entry
    _animController.reverse().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _toggle() => _isVisible ? _close() : _open();

  /// Captures a screenshot of the app content (before the overlay).
  Future<List<int>?> _captureScreen() async {
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final data = await image.toByteData(format: ImageByteFormat.png);
      return data?.buffer.asUint8List().toList();
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _panelHeightFraction.dispose();
    if (_keyHandler != null) {
      HardwareKeyboard.instance.removeHandler(_keyHandler!);
      _keyHandler = null;
    }
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!BlackBox.instance.isEnabled) return widget.child;

    final trigger = BlackBox.instance.trigger;
    final themeData = BlackBox.instance.theme;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: BlackBoxTheme(
        data: themeData,
        child: Stack(
          children: [
            // ── App content wrapped in RepaintBoundary for screenshots ──
            RepaintBoundary(
              key: _repaintKey,
              child: widget.child,
            ),

            // ── Floating button trigger (draggable) ─────────────────────
            if (trigger is FloatingButtonTrigger || _isHudPinned)
              _DraggableFloatingButton(
                onTap: _toggle,
                accentColor: themeData.accentColor,
                forceHudMode: _isHudPinned,
                onCloseHud: () => setState(() => _isHudPinned = false),
              ),

            // ── The Overlay Panel ──────────────────────────────────────
            RepaintBoundary(
              child: Offstage(
                offstage: !_isVisible && !_animController.isAnimating,
                child: IgnorePointer(
                  ignoring: !_isVisible && !_animController.isAnimating,
                  child: Theme(
                    data: ThemeData.dark().copyWith(
                      colorScheme: const ColorScheme.dark(),
                      scaffoldBackgroundColor: Colors.transparent,
                    ),
                    child: Localizations(
                      locale: const Locale('en', 'US'),
                      delegates: const [
                        DefaultMaterialLocalizations.delegate,
                        DefaultWidgetsLocalizations.delegate,
                      ],
                      child: Material(
                        color: Colors.transparent,
                        child: HeroControllerScope.none(
                          child: Navigator(
                            key: _navigatorKey,
                            onGenerateRoute: (_) => PageRouteBuilder(
                              opaque: false,
                              pageBuilder: (context, _, __) => SlideTransition(
                                position: _slideAnimation,
                                child: FadeTransition(
                                  opacity: _fadeAnimation,
                                  child: _ResizablePanel(
                                    heightFraction: _panelHeightFraction,
                                    onClose: _close,
                                    onPinToHud: () {
                                      HapticFeedback.lightImpact();
                                      setState(() => _isHudPinned = true);
                                      _close();
                                    },
                                    captureScreen: _captureScreen,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Resizable panel wrapper — drag handle + backdrop
// ─────────────────────────────────────────────────────────────────────────────

class _ResizablePanel extends StatelessWidget {
  const _ResizablePanel({
    required this.heightFraction,
    required this.onClose,
    required this.onPinToHud,
    required this.captureScreen,
  });

  final ValueNotifier<double> heightFraction;
  final VoidCallback onClose;
  final VoidCallback onPinToHud;
  final Future<List<int>?> Function() captureScreen;

  @override
  Widget build(BuildContext context) {
    final theme = BlackBoxTheme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: ValueListenableBuilder<double>(
        valueListenable: heightFraction,
        builder: (context, fraction, child) {
          return Stack(
            children: [
              // ── Semi-transparent backdrop ──
              Positioned.fill(
                child: GestureDetector(
                  onTap: onClose,
                  child: Container(
                    color:
                        theme.backdropColor.withValues(alpha: fraction * 0.5),
                  ),
                ),
              ),
              // ── Panel positioned at the bottom ──
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: screenHeight * fraction,
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      // ── Drag handle ──
                      GestureDetector(
                        onVerticalDragUpdate: (details) {
                          final delta = -details.delta.dy / screenHeight;
                          final newFraction =
                              (fraction + delta).clamp(0.3, 1.0);
                          heightFraction.value = newFraction;
                        },
                        onDoubleTap: () {
                          heightFraction.value = fraction < 0.75 ? 0.85 : 0.5;
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          color: Colors.transparent,
                          child: Center(
                            child: Container(
                              width: 44,
                              height: 5,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withValues(alpha: 0.15),
                                    Colors.white.withValues(alpha: 0.4),
                                    Colors.white.withValues(alpha: 0.15),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(2.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white.withValues(alpha: 0.1),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // ── Panel body ──
                      Expanded(
                        child: child!,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        child: _BlackBoxPanel(
          onClose: onClose,
          onPinToHud: onPinToHud,
          captureScreen: captureScreen,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Panel shell with tab bar
// ─────────────────────────────────────────────────────────────────────────────

class _BlackBoxPanel extends StatefulWidget {
  const _BlackBoxPanel({
    required this.onClose,
    required this.onPinToHud,
    required this.captureScreen,
  });

  final VoidCallback onClose;
  final VoidCallback onPinToHud;
  final Future<List<int>?> Function() captureScreen;

  @override
  State<_BlackBoxPanel> createState() => _BlackBoxPanelState();
}

class _BlackBoxPanelState extends State<_BlackBoxPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _isSearching = false;

  late final List<({IconData icon, String label})> _filteredTabs;
  late final List<Widget Function()> _filteredViews;

  @override
  void initState() {
    super.initState();

    final hasStorage = BlackBox.instance.storageAdapters.isNotEmpty;
    final hasSockets = BlackBox.instance.socketAdapters.isNotEmpty;

    final allTabs = [
      (icon: Icons.wifi, label: 'Network', view: () => const NetworkPanel()),
      (
        icon: Icons.article_outlined,
        label: 'Logs',
        view: () => const LogPanel()
      ),
      (icon: Icons.speed, label: 'Perf', view: () => const PerformancePanel()),
      (
        icon: Icons.refresh,
        label: 'Rebuilds',
        view: () => const RebuildPanel()
      ),
      if (hasStorage)
        (
          icon: Icons.storage_outlined,
          label: 'Storage',
          view: () => const StoragePanel()
        ),
      if (BlackBox.journeyObserver.navigator != null)
        (
          icon: Icons.route,
          label: 'Routes',
          view: () => const NavigationPanel()
        ),
      if (hasSockets)
        (
          icon: Icons.power,
          label: 'Socket IO',
          view: () => const SocketPanel()
        ),
      (
        icon: Icons.phone_android,
        label: 'Device',
        view: () => const DevicePanel()
      ),
      (
        icon: Icons.bug_report_outlined,
        label: 'QA',
        view: () => QaPanel(captureScreen: widget.captureScreen)
      ),
    ];

    _filteredTabs = allTabs.map((t) => (icon: t.icon, label: t.label)).toList();
    _filteredViews = allTabs.map((t) => t.view).toList();

    _tabController = TabController(length: _filteredTabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        HapticFeedback.selectionClick();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _navigateToSource(String source) {
    String targetLabel = '';
    switch (source) {
      case 'Network':
        targetLabel = 'Network';
        break;
      case 'Logs':
        targetLabel = 'Logs';
        break;
      case 'Crash':
        targetLabel = 'QA';
        break;
      case 'Socket':
        targetLabel = 'Socket IO';
        break;
    }
    
    final index = _filteredTabs.indexWhere((t) => t.label == targetLabel);
    if (index != -1) {
      _tabController.animateTo(index);
      setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            children: [
              // ── Header ───────────────────────────────────────────────
              _PanelHeader(
                tabController: _tabController,
                tabs: _filteredTabs,
                onClose: widget.onClose,
                onPinToHud: widget.onPinToHud,
                isSearching: _isSearching,
                onSearchToggle: () {
                  setState(() => _isSearching = !_isSearching);
                },
              ),
              const SizedBox(height: 8),
              // ── Tab content ──────────────────────────────────────────
              Expanded(
                child: _PanelCard(
                  child: _isSearching
                      ? SearchPanel(
                          onResultTap: _navigateToSource,
                        )
                      : ListenableBuilder(
                          listenable: _tabController,
                          builder: (context, _) => _LazyIndexedStack(
                            index: _tabController.index,
                            children: _filteredViews,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.tabController,
    required this.tabs,
    required this.onClose,
    required this.onPinToHud,
    required this.isSearching,
    required this.onSearchToggle,
  });

  final TabController tabController;
  final List<({IconData icon, String label})> tabs;
  final VoidCallback onClose;
  final VoidCallback onPinToHud;
  final bool isSearching;
  final VoidCallback onSearchToggle;

  @override
  Widget build(BuildContext context) {
    final theme = BlackBoxTheme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.headerBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.0),
                  Colors.white.withValues(alpha: 0.10),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _BlackBoxBadge(theme: theme),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    isSearching ? Icons.search_off : Icons.search,
                    color:
                        isSearching ? theme.accentColor : theme.textSecondary,
                    size: 18,
                  ),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    onSearchToggle();
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.push_pin_outlined,
                      color: Colors.white54, size: 18),
                  onPressed: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    HapticFeedback.lightImpact();
                    onPinToHud();
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: Icon(Icons.close, color: theme.textSecondary, size: 18),
                  onPressed: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    HapticFeedback.lightImpact();
                    onClose();
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          if (!isSearching)
            TabBar(
              controller: tabController,
              isScrollable: true,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  colors: [
                    theme.accentColor.withValues(alpha: 0.25),
                    theme.accentColor.withValues(alpha: 0.15),
                  ],
                ),
                border: Border.all(
                  color: theme.accentColor.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
              indicatorPadding:
                  const EdgeInsets.symmetric(horizontal: -8, vertical: 6),
              labelPadding: const EdgeInsets.symmetric(horizontal: 12),
              labelColor: theme.textPrimary,
              unselectedLabelColor: theme.textMuted,
              labelStyle:
                  const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
              unselectedLabelStyle:
                  const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
              tabAlignment: TabAlignment.start,
              dividerColor: Colors.transparent,
              tabs: tabs.map((t) {
                final isQa = t.label == 'QA';
                return StreamBuilder<List<dynamic>>(
                  stream: isQa
                      ? BlackBox.instance.crashStore.stream
                      : const Stream<List<dynamic>>.empty(),
                  initialData:
                      isQa ? BlackBox.instance.crashStore.entries : <dynamic>[],
                  builder: (context, snapshot) {
                    final hasCrash = isQa && ((snapshot.data ?? []).isNotEmpty);
                    return SizedBox(
                      width: 50,
                      child: Tab(
                        iconMargin: const EdgeInsets.only(bottom: 4),
                        icon: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(t.icon, size: 16),
                            if (hasCrash)
                              Positioned(
                                right: -4,
                                top: -2,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('CRASH',
                                      style: TextStyle(
                                          fontSize: 6,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ),
                          ],
                        ),
                        child: Text(
                          t.label,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  },
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = BlackBoxTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.0),
                  Colors.white.withValues(alpha: 0.08),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _BlackBoxBadge extends StatelessWidget {
  const _BlackBoxBadge({required this.theme});
  final BlackBoxThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.badgeColor,
            theme.badgeColor.withValues(alpha: 0.75),
          ],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.badgeColor.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Text(
        'BlackBox',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: .6,
        ),
      ),
    );
  }
}

class _DraggableFloatingButton extends StatefulWidget {
  const _DraggableFloatingButton({
    required this.onTap,
    required this.accentColor,
    this.forceHudMode = false,
    this.onCloseHud,
  });

  final VoidCallback onTap;
  final Color accentColor;
  final bool forceHudMode;
  final VoidCallback? onCloseHud;

  @override
  State<_DraggableFloatingButton> createState() =>
      _DraggableFloatingButtonState();
}

class _DraggableFloatingButtonState extends State<_DraggableFloatingButton>
    with SingleTickerProviderStateMixin {
  // Position stored as offsets from bottom-right corner.
  double _right = 16;
  double _bottom = 80;
  bool _isDragging = false;
  bool _isHudMode = false;

  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;

  // Live HUD data
  String? _lastSeenRequestId;
  int _lastPingMs = 0;
  int _crashCount = 0;
  double _fps = 0;

  StreamSubscription<List<NetworkEntry>>? _networkSub;
  StreamSubscription<List<CrashEntry>>? _crashSub;
  StreamSubscription<FpsSnapshot>? _fpsSub;

  @override
  void initState() {
    super.initState();
    _isHudMode = widget.forceHudMode;
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500));

    if (!WidgetsBinding.instance.runtimeType.toString().contains('Test')) {
      _ctrl.repeat(reverse: true);
    }

    _scaleAnim = Tween<double>(begin: 1.0, end: 1.1)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

    // Subscribe to live data for HUD.
    // The stream is throttled (250ms) and may deliver stale snapshots where
    // the newest entries are still pending. We use the event only as a
    // trigger and read the freshest data directly from the store.
    _networkSub = BlackBox.instance.networkStore.stream.listen((_) {
      _refreshNetworkHud();
    });
    // Also pick up any data already in the store.
    _refreshNetworkHud();

    _crashSub = BlackBox.instance.crashStore.stream.listen((crashes) {
      if (mounted) setState(() => _crashCount = crashes.length);
    });

    _fpsSub = BlackBox.instance.fpsMonitor.stream.listen((snapshot) {
      if (mounted) setState(() => _fps = snapshot.fps);
    });
  }

  @override
  void dispose() {
    _networkSub?.cancel();
    _crashSub?.cancel();
    _fpsSub?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _DraggableFloatingButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.forceHudMode != oldWidget.forceHudMode && widget.forceHudMode) {
      setState(() => _isHudMode = true);
    }
  }

  /// Reads the freshest data directly from the store (bypassing the throttled
  /// stream snapshot) and updates the HUD if a newer completed request exists.
  void _refreshNetworkHud() {
    if (!mounted) return;
    final entries = BlackBox.instance.networkStore.entries;
    if (entries.isEmpty) return;

    // Walk backwards to find the most recent entry with a completed response.
    for (int i = entries.length - 1; i >= 0; i--) {
      final entry = entries[i];
      if (entry.response != null) {
        // Only update if it's a different request than what we already show.
        if (entry.request.id != _lastSeenRequestId) {
          setState(() {
            _lastSeenRequestId = entry.request.id;
            _lastPingMs = entry.durationMs;
          });
        }
        return;
      }
    }
  }

  Color _pingColor() {
    if (_lastPingMs == 0) return Colors.white38;
    if (_lastPingMs < 200) return const Color(0xFF4ADE80);
    if (_lastPingMs < 500) return const Color(0xFFFBBF24);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    const buttonSize = 40.0;
    const hudHeight = 36.0;
    const hudWidth = 200.0;

    final currentWidth = _isHudMode ? hudWidth : buttonSize;
    final currentHeight = _isHudMode ? hudHeight : buttonSize;

    return AnimatedPositioned(
      duration: _isDragging ? Duration.zero : const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      right: _right.clamp(4.0, screenSize.width - currentWidth - 4),
      bottom: _bottom.clamp(4.0, screenSize.height - currentHeight - 4),
      child: GestureDetector(
        onPanStart: (_) => _isDragging = false,
        onPanUpdate: (details) {
          _isDragging = true;
          setState(() {
            _right -= details.delta.dx;
            _bottom -= details.delta.dy;
          });
        },
        onPanEnd: (_) {
          setState(() {
            // Snap to nearest horizontal edge
            final center = screenSize.width - _right - currentWidth / 2;
            _right = center < screenSize.width / 2
                ? screenSize.width - currentWidth - 4
                : 4;
          });
          _isDragging = false;
        },
        onPanCancel: () => _isDragging = false,
        onTap: () {
          if (!_isDragging) widget.onTap();
          _isDragging = false;
        },
        child: RepaintBoundary(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            width: _isHudMode ? hudWidth : buttonSize,
            height: _isHudMode ? hudHeight : buttonSize,
            decoration: BoxDecoration(
              color: _isHudMode
                  ? widget.accentColor.withValues(alpha: 0.9)
                  : widget.accentColor,
              borderRadius: BorderRadius.circular(
                _isHudMode ? hudHeight / 2 : buttonSize / 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.accentColor.withValues(alpha: 0.35),
                  blurRadius: _isHudMode ? 12 : 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: _isHudMode ? _buildHudContent() : _buildButtonContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildButtonContent() {
    final isDesktop = _isDesktopPlatform();
    return Stack(
      alignment: Alignment.center,
      children: [
        ScaleTransition(
          scale: _scaleAnim,
          child: const Center(
            child: Icon(Icons.bug_report, color: Colors.white, size: 20),
          ),
        ),
        if (isDesktop)
          Positioned(
            bottom: 2,
            right: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text(
                '⌘⇧D',
                style: TextStyle(
                  fontSize: 6,
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  bool _isDesktopPlatform() {
    final platform = Theme.of(context).platform;
    return platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux;
  }

  Widget _buildHudContent() {
    final fpsColor = _fps >= 55
        ? const Color(0xFF4ADE80)
        : _fps >= 30
            ? const Color(0xFFFBBF24)
            : const Color(0xFFEF4444);

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 8),
          // FPS
          Icon(Icons.speed, color: fpsColor, size: 13),
          const SizedBox(width: 3),
          Text(
            '${_fps.round()}',
            style: TextStyle(
              color: fpsColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          Container(
            width: 1,
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: Colors.white24,
          ),
          // Network latency (ping)
          Icon(Icons.wifi, color: _pingColor(), size: 13),
          const SizedBox(width: 3),
          Text(
            _lastPingMs > 0 ? '${_lastPingMs}ms' : '---',
            style: TextStyle(
              color: _pingColor(),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          Container(
            width: 1,
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: Colors.white24,
          ),
          // Crash count
          Icon(
            Icons.warning_amber_rounded,
            color: _crashCount > 0 ? const Color(0xFFEF4444) : Colors.white38,
            size: 13,
          ),
          const SizedBox(width: 3),
          Text(
            '$_crashCount',
            style: TextStyle(
              color: _crashCount > 0 ? const Color(0xFFEF4444) : Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          // Unpin button
          GestureDetector(
            onTap: () {
              setState(() {
                _isHudMode = false;
                widget.onCloseHud?.call();
              });
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white54, size: 12),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _LazyIndexedStack extends StatefulWidget {
  const _LazyIndexedStack({required this.index, required this.children});
  final int index;
  final List<Widget Function()> children;

  @override
  State<_LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<_LazyIndexedStack> {
  late List<Widget?> _built;
  // Tracks which tabs have completed their initial layout pass.
  final Set<int> _warmedUp = {};

  @override
  void initState() {
    super.initState();
    _built = List<Widget?>.filled(widget.children.length, null);
    _buildAndWarmUp(widget.index);
  }

  @override
  void didUpdateWidget(_LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_built.length != widget.children.length) {
      final newBuilt = List<Widget?>.filled(widget.children.length, null);
      final minLength = _built.length < widget.children.length
          ? _built.length
          : widget.children.length;
      for (int i = 0; i < minLength; i++) {
        newBuilt[i] = _built[i];
      }
      _built = newBuilt;
    }
    _buildAndWarmUp(widget.index);
  }

  void _buildAndWarmUp(int index) {
    if (_built[index] == null) {
      // Build the panel but keep it invisible for one frame so Flutter
      // can measure and lay it out before it becomes visible.
      _built[index] = widget.children[index]();
      // Schedule the warm-up completion after the layout pass.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _warmedUp.add(index));
      });
    } else if (!_warmedUp.contains(index)) {
      // Already built but not yet warmed up — mark it now.
      _warmedUp.add(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (int i = 0; i < widget.children.length; i++)
          if (_built[i] != null)
            Offstage(
              offstage: !(widget.index == i && _warmedUp.contains(i)),
              child: TickerMode(
                enabled: widget.index == i,
                child: _built[i]!,
              ),
            ),
      ],
    );
  }
}
