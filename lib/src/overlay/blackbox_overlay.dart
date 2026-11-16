import 'dart:async';
import 'dart:ui' show ImageByteFormat, ImageFilter;
import 'dart:ui' as ui show Image;
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
import 'panels/qa/qa_annotation_layer.dart';
import 'panels/companion_panel.dart';
import 'widgets/blackbox_colors.dart';
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

  final _floatingButtonKey = GlobalKey<_DraggableFloatingButtonState>();

  // ── QA Annotation State ───────────────────────────────────────────
  bool _isAnnotating = false;
  final _strokes = <AnnotationStroke>[];
  AnnotationTool _currentTool = AnnotationTool.freehand;
  int _repaintVersion = 0;
  bool _isCapturingScreenshot = false;
  final _screenshotNotifier = ValueNotifier<List<int>?>(null);
  int _screenshotGeneration = 0;

  void _requestRepaint() {
    if (mounted) setState(() => _repaintVersion++);
  }

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
      owner: this,
      open: _open,
      close: _close,
      toggle: _toggle,
      startAnnotation: _startAnnotation,
      clearAnnotations: _clearAnnotations,
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
    _floatingButtonKey.currentState?.clearBadge();
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

  void _startAnnotation() {
    _close();
    setState(() => _isAnnotating = true);
  }

  void _clearAnnotations() {
    if (mounted) {
      setState(() {
        _strokes.clear();
        _repaintVersion++;
      });
    }
  }

  void _addStroke(AnnotationStroke stroke) {
    if (mounted) {
      setState(() {
        if (_strokes.length < 100) _strokes.add(stroke);
        _repaintVersion++;
      });
    }
  }

  void _finishAnnotationAndCapture() {
    setState(() {
      _isAnnotating = false;
      _isCapturingScreenshot = true;
    });
    // Wait one frame to ensure HUD is hidden
    final generation = ++_screenshotGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || generation != _screenshotGeneration) return;
      try {
        final bytes = await _captureScreen();
        if (mounted && generation == _screenshotGeneration) {
          if (bytes != null) _screenshotNotifier.value = bytes;
          _open();
        }
      } catch (_) {
        if (mounted && generation == _screenshotGeneration) _open();
      } finally {
        if (mounted) {
          setState(() => _isCapturingScreenshot = false);
        }
      }
    });
  }

  /// Captures a screenshot of the app content (before the overlay).
  Future<List<int>?> _captureScreen() async {
    ui.Image? image;
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      image = await boundary.toImage(pixelRatio: 2.0);
      final data = await image.toByteData(format: ImageByteFormat.png);
      return data?.buffer.asUint8List().toList();
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
    }
  }

  @override
  void dispose() {
    _screenshotGeneration++;
    BlackBox.instance.unregisterOverlayCallbacks(this);
    _screenshotNotifier.value = null;
    _screenshotNotifier.dispose();
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
              child: Stack(
                children: [
                  widget.child,
                  if (_isAnnotating || _isCapturingScreenshot)
                    QaAnnotationLayer(
                      strokes: _strokes,
                      currentTool: _currentTool,
                      isInteractive: _isAnnotating,
                      repaintVersion: _repaintVersion,
                      onStrokeComplete: _addStroke,
                      onRepaintRequested: _requestRepaint,
                    ),
                ],
              ),
            ),

            // ── Floating button trigger (draggable) ─────────────────────
            if (trigger is FloatingButtonTrigger ||
                _isHudPinned ||
                _isAnnotating)
              _DraggableFloatingButton(
                key: _floatingButtonKey,
                onTap: _isAnnotating ? () {} : _toggle,
                accentColor: themeData.accentColor,
                forceHudMode: _isHudPinned,
                isAnnotationMode: _isAnnotating,
                annotationControls:
                    _buildAnnotationControls(themeData.accentColor),
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
                                    screenshotNotifier: _screenshotNotifier,
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

  Widget _buildAnnotationControls(Color accentColor) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: SizedBox(
        width: 336,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildToolBtn(AnnotationTool.freehand, Icons.edit),
              _buildToolBtn(AnnotationTool.line, Icons.horizontal_rule),
              _buildToolBtn(
                  AnnotationTool.circle, Icons.radio_button_unchecked),
              _buildToolBtn(AnnotationTool.rectangle, Icons.crop_square),
              _buildToolBtn(AnnotationTool.move, Icons.open_with),
              Container(
                  width: 1,
                  height: 24,
                  color: Colors.white24,
                  margin: const EdgeInsets.symmetric(horizontal: 4)),
              _buildActionBtn(
                icon: Icons.undo,
                color: Colors.white,
                onPressed: _strokes.isEmpty
                    ? null
                    : () {
                        setState(() {
                          _strokes.removeLast();
                          _repaintVersion++;
                        });
                      },
              ),
              _buildActionBtn(
                icon: Icons.check,
                color: const Color(0xFF34D399),
                onPressed: _finishAnnotationAndCapture,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionBtn(
      {required IconData icon, required Color color, VoidCallback? onPressed}) {
    final isEnabled = onPressed != null;
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.05),
        ),
        child: Icon(icon,
            color: isEnabled ? color : color.withValues(alpha: 0.3), size: 20),
      ),
    );
  }

  Widget _buildToolBtn(AnnotationTool tool, IconData icon) {
    final isActive = _currentTool == tool;
    return GestureDetector(
      onTap: () => setState(() => _currentTool = tool),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive
              ? Colors.white.withValues(alpha: 0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive
                ? Colors.white.withValues(alpha: 0.5)
                : Colors.transparent,
            width: 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Icon(
          icon,
          color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.6),
          size: 20,
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
    required this.screenshotNotifier,
  });

  final ValueNotifier<double> heightFraction;
  final VoidCallback onClose;
  final VoidCallback onPinToHud;
  final ValueNotifier<List<int>?> screenshotNotifier;

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
              // ── Semi-transparent backdrop with radial glow ──
              Positioned.fill(
                child: GestureDetector(
                  onTap: onClose,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, 1.2),
                        radius: 1.8,
                        colors: [
                          theme.accentColor.withValues(alpha: 0.08 * fraction),
                          theme.backdropColor
                              .withValues(alpha: fraction * 0.55),
                          theme.backdropColor
                              .withValues(alpha: fraction * 0.65),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
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
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragUpdate: (details) {
                          final delta = -details.delta.dy / screenHeight;
                          final newFraction =
                              (fraction + delta).clamp(0.3, 1.0);
                          heightFraction.value = newFraction;
                        },
                        onVerticalDragEnd: (details) {
                          if (details.primaryVelocity != null) {
                            if (details.primaryVelocity! < -500) {
                              heightFraction.value = 0.95; // Flick up
                            } else if (details.primaryVelocity! > 500) {
                              heightFraction.value = 0.4; // Flick down
                            }
                          }
                        },
                        onDoubleTap: () {
                          heightFraction.value = fraction < 0.75 ? 0.95 : 0.4;
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 20),
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
          screenshotNotifier: screenshotNotifier,
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
    required this.screenshotNotifier,
  });

  final VoidCallback onClose;
  final VoidCallback onPinToHud;
  final ValueNotifier<List<int>?> screenshotNotifier;

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
        view: () => QaPanel(screenshotNotifier: widget.screenshotNotifier)
      ),
      (
        icon: Icons.qr_code_scanner,
        label: 'Link',
        view: () => const CompanionPanel()
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
    final headerButtonStyle = IconButton.styleFrom(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: const Size(26, 26),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: theme.headerBackground.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: theme.accentColor.withValues(alpha: 0.1),
                blurRadius: 30,
                spreadRadius: -5,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      theme.accentColor.withValues(alpha: 0.3),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(child: _BlackBoxBadge(theme: theme)),
                          const SizedBox(width: 6),
                          ValueListenableBuilder<bool>(
                            valueListenable:
                                BlackBox.instance.captureStateListenable,
                            builder: (context, capturing, _) => Tooltip(
                              message: capturing
                                  ? 'Capture active'
                                  : 'Capture paused',
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: (capturing
                                          ? BlackBoxColors.success
                                          : BlackBoxColors.warning)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  capturing ? 'REC' : 'PAUSED',
                                  style: TextStyle(
                                    fontSize: 7,
                                    fontWeight: FontWeight.w800,
                                    color: capturing
                                        ? BlackBoxColors.success
                                        : BlackBoxColors.warning,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    ValueListenableBuilder<bool>(
                      valueListenable: BlackBox.instance.captureStateListenable,
                      builder: (context, capturing, _) => IconButton(
                        tooltip: capturing ? 'Pause capture' : 'Resume capture',
                        style: headerButtonStyle,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          capturing ? Icons.pause : Icons.play_arrow,
                          color: capturing
                              ? theme.textSecondary
                              : BlackBoxColors.warning,
                          size: 18,
                        ),
                        onPressed: capturing
                            ? BlackBox.pauseCapture
                            : BlackBox.resumeCapture,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    PopupMenuButton<String>(
                      tooltip: 'Capture actions',
                      style: headerButtonStyle,
                      color: theme.cardBackground,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(Icons.more_vert,
                          color: theme.textSecondary, size: 18),
                      onSelected: (value) async {
                        if (value == 'clear') {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('Clear captured data?'),
                              content: const Text(
                                'This removes the current BlackBox session. '
                                'Capture will keep its current paused or '
                                'recording state.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, true),
                                  child: const Text('Clear'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) BlackBox.clearCapturedData();
                        } else if (value == 'link') {
                          final linkTabIndex =
                              tabs.indexWhere((tab) => tab.label == 'Link');
                          if (linkTabIndex != -1) {
                            tabController.animateTo(linkTabIndex);
                          }
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem<String>(
                          value: 'link',
                          child: Row(
                            children: [
                              Icon(Icons.qr_code_scanner,
                                  size: 18, color: Colors.white70),
                              SizedBox(width: 8),
                              Text('Open companion link'),
                            ],
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'clear',
                          child: Row(
                            children: [
                              Icon(Icons.delete_sweep_outlined,
                                  size: 18, color: Colors.white70),
                              SizedBox(width: 8),
                              Text('Clear captured data'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: isSearching ? 'Close search' : 'Search',
                      style: headerButtonStyle,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        isSearching ? Icons.search_off : Icons.search,
                        color: isSearching
                            ? theme.accentColor
                            : theme.textSecondary,
                        size: 18,
                      ),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        onSearchToggle();
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Pin to HUD',
                      style: headerButtonStyle,
                      visualDensity: VisualDensity.compact,
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
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Close',
                      style: headerButtonStyle,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.close,
                          color: theme.textSecondary, size: 18),
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
                        theme.accentColor.withValues(alpha: 0.30),
                        theme.accentColor.withValues(alpha: 0.15),
                      ],
                    ),
                    border: Border.all(
                      color: theme.accentColor.withValues(alpha: 0.35),
                      width: 0.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: theme.accentColor.withValues(alpha: 0.25),
                        blurRadius: 12,
                        spreadRadius: -2,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  indicatorPadding:
                      const EdgeInsets.symmetric(horizontal: -8, vertical: 6),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                  labelColor: theme.textPrimary,
                  unselectedLabelColor: theme.textMuted,
                  labelStyle: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700),
                  unselectedLabelStyle: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600),
                  tabAlignment: TabAlignment.start,
                  dividerColor: Colors.transparent,
                  tabs: tabs.map((t) {
                    final isQa = t.label == 'QA';
                    return StreamBuilder<List<dynamic>>(
                      stream: isQa
                          ? BlackBox.instance.crashStore.stream
                          : const Stream<List<dynamic>>.empty(),
                      initialData: isQa
                          ? BlackBox.instance.crashStore.entries
                          : <dynamic>[],
                      builder: (context, snapshot) {
                        final hasCrash =
                            isQa && ((snapshot.data ?? []).isNotEmpty);
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
        ),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: theme.cardBackground.withValues(alpha: 0.80),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: theme.accentColor.withValues(alpha: 0.08),
                blurRadius: 40,
                spreadRadius: -5,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      theme.accentColor.withValues(alpha: 0.4),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
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
      child: const FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          'BlackBox',
          maxLines: 1,
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: .6,
          ),
        ),
      ),
    );
  }
}

class _DraggableFloatingButton extends StatefulWidget {
  const _DraggableFloatingButton({
    super.key,
    required this.onTap,
    required this.accentColor,
    this.forceHudMode = false,
    this.isAnnotationMode = false,
    this.annotationControls,
    this.onCloseHud,
  });

  final VoidCallback onTap;
  final Color accentColor;
  final bool forceHudMode;
  final bool isAnnotationMode;
  final Widget? annotationControls;
  final VoidCallback? onCloseHud;

  @override
  State<_DraggableFloatingButton> createState() =>
      _DraggableFloatingButtonState();
}

class _HudStats {
  const _HudStats({
    this.fps = 0,
    this.pingMs = 0,
    this.crashCount = 0,
    this.errorBadge = 0,
  });

  final double fps;
  final int pingMs;
  final int crashCount;
  final int errorBadge;

  _HudStats copyWith({
    double? fps,
    int? pingMs,
    int? crashCount,
    int? errorBadge,
  }) {
    return _HudStats(
      fps: fps ?? this.fps,
      pingMs: pingMs ?? this.pingMs,
      crashCount: crashCount ?? this.crashCount,
      errorBadge: errorBadge ?? this.errorBadge,
    );
  }
}

class _DraggableFloatingButtonState extends State<_DraggableFloatingButton> {
  // Position stored as offsets from bottom-right corner.
  final ValueNotifier<Offset> _positionNotifier =
      ValueNotifier<Offset>(const Offset(16, 80));
  bool _isDragging = false;
  bool _isHudMode = false;

  // Live HUD data isolated in a ValueNotifier
  String? _lastSeenRequestId;
  final ValueNotifier<_HudStats> _hudStatsNotifier =
      ValueNotifier<_HudStats>(const _HudStats());

  StreamSubscription<List<NetworkEntry>>? _networkSub;
  StreamSubscription<List<CrashEntry>>? _crashSub;
  StreamSubscription<FpsSnapshot>? _fpsSub;

  @override
  void initState() {
    super.initState();
    _isHudMode = widget.forceHudMode;
    if (_isHudMode) _subscribeHud();
  }

  @override
  void dispose() {
    _unsubscribeHud();
    _hudStatsNotifier.dispose();
    _positionNotifier.dispose();
    super.dispose();
  }

  void clearBadge() {
    if (_hudStatsNotifier.value.errorBadge > 0) {
      _hudStatsNotifier.value = _hudStatsNotifier.value.copyWith(errorBadge: 0);
    }
  }

  @override
  void didUpdateWidget(covariant _DraggableFloatingButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.forceHudMode != oldWidget.forceHudMode) {
      _isHudMode = widget.forceHudMode;
      if (_isHudMode) {
        _subscribeHud();
      } else {
        _unsubscribeHud();
      }
    }
  }

  void _subscribeHud() {
    if (_networkSub != null) return;

    // The streams are wake-up signals; read the current store snapshot so a
    // throttled emission cannot make the HUD lag behind the latest entry.
    _networkSub = BlackBox.instance.networkStore.stream.listen((_) {
      _refreshNetworkHud();
    });
    _crashSub = BlackBox.instance.crashStore.stream.listen((crashes) {
      if (mounted) {
        _hudStatsNotifier.value =
            _hudStatsNotifier.value.copyWith(crashCount: crashes.length);
      }
    });
    _fpsSub = BlackBox.instance.fpsMonitor.stream.listen((snapshot) {
      if (mounted) {
        _hudStatsNotifier.value =
            _hudStatsNotifier.value.copyWith(fps: snapshot.fps);
      }
    });

    _hudStatsNotifier.value = _hudStatsNotifier.value
        .copyWith(crashCount: BlackBox.instance.crashStore.entries.length);
    _refreshNetworkHud();
  }

  void _unsubscribeHud() {
    final networkSub = _networkSub;
    final crashSub = _crashSub;
    final fpsSub = _fpsSub;
    _networkSub = null;
    _crashSub = null;
    _fpsSub = null;
    if (networkSub != null) unawaited(networkSub.cancel());
    if (crashSub != null) unawaited(crashSub.cancel());
    if (fpsSub != null) unawaited(fpsSub.cancel());
  }

  /// Reads the freshest data directly from the store (bypassing the throttled
  /// stream snapshot) and updates the HUD if a newer completed request exists.
  void _refreshNetworkHud() {
    if (!mounted) return;
    final entries = BlackBox.instance.networkStore.entries;
    if (entries.isEmpty) {
      if (_lastSeenRequestId != null ||
          _hudStatsNotifier.value.pingMs != 0 ||
          _hudStatsNotifier.value.errorBadge != 0) {
        _lastSeenRequestId = null;
        _hudStatsNotifier.value =
            _hudStatsNotifier.value.copyWith(pingMs: 0, errorBadge: 0);
      }
      return;
    }

    // Walk backwards to find the most recent entry with a completed response.
    for (int i = entries.length - 1; i >= 0; i--) {
      final entry = entries[i];
      if (entry.response != null) {
        // Only update if it's a different request than what we already show.
        if (entry.request.id != _lastSeenRequestId) {
          _lastSeenRequestId = entry.request.id;
          final isError =
              entry.response!.isClientError || entry.response!.isServerError;
          _hudStatsNotifier.value = _hudStatsNotifier.value.copyWith(
            pingMs: entry.durationMs,
            errorBadge: isError
                ? _hudStatsNotifier.value.errorBadge + 1
                : _hudStatsNotifier.value.errorBadge,
          );
        }
        return;
      }
    }
  }

  Color _pingColor(int pingMs) {
    if (pingMs == 0) return Colors.white38;
    if (pingMs < 200) return const Color(0xFF4ADE80);
    if (pingMs < 500) return const Color(0xFFFBBF24);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    const buttonSize = 40.0;
    const hudHeight = 36.0;
    const hudWidth = 200.0;

    final isAnnotation = widget.isAnnotationMode;
    final currentWidth =
        isAnnotation ? 336.0 : (_isHudMode ? hudWidth : buttonSize);
    final currentHeight =
        isAnnotation ? 44.0 : (_isHudMode ? hudHeight : buttonSize);

    final maxRight = (screenSize.width - currentWidth - 4.0) > 4.0
        ? (screenSize.width - currentWidth - 4.0)
        : 4.0;
    final maxBottom = (screenSize.height - currentHeight - 4.0) > 4.0
        ? (screenSize.height - currentHeight - 4.0)
        : 4.0;

    return ValueListenableBuilder<Offset>(
      valueListenable: _positionNotifier,
      builder: (context, pos, child) {
        return AnimatedPositioned(
          duration:
              _isDragging ? Duration.zero : const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          right: pos.dx.clamp(4.0, maxRight),
          bottom: pos.dy.clamp(4.0, maxBottom),
          child: child!,
        );
      },
      child: GestureDetector(
        onPanStart: (_) {
          if (!_isDragging) {
            setState(() => _isDragging = true);
          }
        },
        onPanUpdate: (details) {
          _positionNotifier.value = Offset(
            _positionNotifier.value.dx - details.delta.dx,
            _positionNotifier.value.dy - details.delta.dy,
          );
        },
        onPanEnd: (_) {
          final maxRight = (screenSize.width - currentWidth - 4.0) > 4.0
              ? (screenSize.width - currentWidth - 4.0)
              : 4.0;
          final center =
              screenSize.width - _positionNotifier.value.dx - currentWidth / 2;
          final snapRight = center < screenSize.width / 2 ? maxRight : 4.0;
          setState(() => _isDragging = false);
          _positionNotifier.value =
              Offset(snapRight, _positionNotifier.value.dy);
        },
        onPanCancel: () {
          if (_isDragging) {
            setState(() => _isDragging = false);
          }
        },
        onTap: () {
          if (!_isDragging) widget.onTap();
          _isDragging = false;
        },
        child: RepaintBoundary(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            width: currentWidth,
            height: currentHeight,
            decoration: BoxDecoration(
              gradient: _isHudMode
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        widget.accentColor.withValues(alpha: 0.95),
                        widget.accentColor.withValues(alpha: 0.80),
                      ],
                    )
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        widget.accentColor,
                        Color.lerp(
                            widget.accentColor, const Color(0xFF38BDF8), 0.4)!,
                      ],
                    ),
              borderRadius: BorderRadius.circular(currentHeight / 2),
              boxShadow: [
                BoxShadow(
                  color: widget.accentColor.withValues(alpha: 0.45),
                  blurRadius: (_isHudMode || isAnnotation) ? 16 : 14,
                  spreadRadius: (_isHudMode || isAnnotation) ? 0 : 1,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: widget.accentColor.withValues(alpha: 0.15),
                  blurRadius: 30,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: isAnnotation
                ? (widget.annotationControls ?? const SizedBox.shrink())
                : (_isHudMode ? _buildHudContent() : _buildButtonContent()),
          ),
        ),
      ),
    );
  }

  Widget _buildButtonContent() {
    final isDesktop = _isDesktopPlatform();
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        const Center(
          child: Icon(Icons.bug_report, color: Colors.white, size: 20),
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
        ValueListenableBuilder<_HudStats>(
          valueListenable: _hudStatsNotifier,
          builder: (context, stats, _) {
            if (stats.errorBadge <= 0) return const SizedBox.shrink();
            return Positioned(
              top: 2,
              right: 2,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.5),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  stats.errorBadge > 9 ? '9+' : '${stats.errorBadge}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          },
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
    return ValueListenableBuilder<_HudStats>(
      valueListenable: _hudStatsNotifier,
      builder: (context, stats, _) {
        final fps = stats.fps;
        final fpsColor = fps >= 55
            ? const Color(0xFF4ADE80)
            : fps >= 30
                ? const Color(0xFFFBBF24)
                : const Color(0xFFEF4444);

        final pingMs = stats.pingMs;
        final pingColor = _pingColor(pingMs);
        final crashCount = stats.crashCount;

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
                '${fps.round()}',
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
              Icon(Icons.wifi, color: pingColor, size: 13),
              const SizedBox(width: 3),
              Text(
                pingMs > 0 ? '${pingMs}ms' : '---',
                style: TextStyle(
                  color: pingColor,
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
                color:
                    crashCount > 0 ? const Color(0xFFEF4444) : Colors.white38,
                size: 13,
              ),
              const SizedBox(width: 3),
              Text(
                '$crashCount',
                style: TextStyle(
                  color:
                      crashCount > 0 ? const Color(0xFFEF4444) : Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              // Unpin button
              GestureDetector(
                onTap: () {
                  _unsubscribeHud();
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
                  child:
                      const Icon(Icons.close, color: Colors.white54, size: 12),
                ),
              ),
              const SizedBox(width: 6),
            ],
          ),
        );
      },
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
      _warmedUp.removeWhere((i) => i >= widget.children.length);
    }
    _buildAndWarmUp(widget.index);
  }

  void _buildAndWarmUp(int index) {
    if (index < 0 || index >= widget.children.length) return;
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
