import 'dart:ui';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../blackbox.dart';
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
  final _repaintKey = GlobalKey();
  late final AnimationController _animController;

  // ── Resizable panel state ─────────────────────────────────────────
  final _panelHeightFraction = ValueNotifier<double>(0.85);
  late final Animation<double> _fadeAnimation;

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
      duration: const Duration(milliseconds: 220),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );

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
    setState(() => _isVisible = true);
    _animController.forward();
  }

  void _close() {
    _animController.reverse().then((_) {
      if (mounted) setState(() => _isVisible = false);
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
            if (trigger is FloatingButtonTrigger)
              _DraggableFloatingButton(
                onTap: _toggle,
                accentColor: themeData.accentColor,
              ),

            // ── The Overlay Panel ──────────────────────────────────────
            Offstage(
              offstage: !_isVisible && !_animController.isAnimating,
              child: IgnorePointer(
                ignoring: !_isVisible && !_animController.isAnimating,
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
                          pageBuilder: (context, _, __) => FadeTransition(
                            opacity: _fadeAnimation,
                            child: _ResizablePanel(
                              heightFraction: _panelHeightFraction,
                              onClose: _close,
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
    required this.captureScreen,
  });

  final ValueNotifier<double> heightFraction;
  final VoidCallback onClose;
  final Future<List<int>?> Function() captureScreen;

  @override
  Widget build(BuildContext context) {
    final theme = BlackBoxTheme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.transparent,
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
                              width: 40,
                              height: 5,
                              decoration: BoxDecoration(
                                color: theme.dragHandleColor,
                                borderRadius: BorderRadius.circular(2.5),
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
    required this.captureScreen,
  });

  final VoidCallback onClose;
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
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
                      ? const SearchPanel()
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
    required this.isSearching,
    required this.onSearchToggle,
  });

  final TabController tabController;
  final List<({IconData icon, String label})> tabs;
  final VoidCallback onClose;
  final bool isSearching;
  final VoidCallback onSearchToggle;

  @override
  Widget build(BuildContext context) {
    final theme = BlackBoxTheme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.headerBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
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
                  onPressed: onSearchToggle,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: Icon(Icons.close, color: theme.textSecondary, size: 18),
                  onPressed: onClose,
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
              indicatorColor: theme.accentColor,
              labelColor: theme.textPrimary,
              unselectedLabelColor: theme.textMuted,
              labelStyle:
                  const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
              tabAlignment: TabAlignment.start,
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
                    return Tab(
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
                      text: t.label,
                      iconMargin: const EdgeInsets.only(bottom: 2),
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _BlackBoxBadge extends StatelessWidget {
  const _BlackBoxBadge({required this.theme});
  final BlackBoxThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.badgeColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'BlackBox',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: .5,
        ),
      ),
    );
  }
}

class _DraggableFloatingButton extends StatefulWidget {
  const _DraggableFloatingButton({
    required this.onTap,
    required this.accentColor,
  });
  final VoidCallback onTap;
  final Color accentColor;

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

  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.1)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    const buttonSize = 40.0;

    return Positioned(
      right: _right.clamp(4.0, screenSize.width - buttonSize - 4),
      bottom: _bottom.clamp(4.0, screenSize.height - buttonSize - 4),
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
          // Snap to nearest horizontal edge
          final center = screenSize.width - _right - buttonSize / 2;
          setState(() {
            _right = center < screenSize.width / 2
                ? screenSize.width - buttonSize - 4
                : 4;
          });
          _isDragging = false;
        },
        onPanCancel: () {
          _isDragging = false;
        },
        onTap: () {
          if (!_isDragging) widget.onTap();
          _isDragging = false;
        },
        child: ScaleTransition(
          scale: _scaleAnim,
          child: Container(
            width: buttonSize,
            height: buttonSize,
            decoration: BoxDecoration(
              color: widget.accentColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: widget.accentColor.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.bug_report,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
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

  @override
  void initState() {
    super.initState();
    _built = List<Widget?>.filled(widget.children.length, null);
    _built[widget.index] = widget.children[widget.index]();
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
    if (_built[widget.index] == null) {
      _built[widget.index] = widget.children[widget.index]();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (int i = 0; i < widget.children.length; i++)
          if (_built[i] != null)
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              opacity: widget.index == i ? 1.0 : 0.0,
              child: IgnorePointer(
                ignoring: widget.index != i,
                child: TickerMode(
                  enabled: widget.index == i,
                  child: _built[i]!,
                ),
              ),
            ),
      ],
    );
  }
}
