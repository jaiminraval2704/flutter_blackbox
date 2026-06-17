import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../blackbox.dart';
import '../../companion/firebase_streamer.dart';
import '../widgets/blackbox_theme.dart';

class CompanionPanel extends StatefulWidget {
  const CompanionPanel({super.key});

  @override
  State<CompanionPanel> createState() => _CompanionPanelState();
}

class _CompanionPanelState extends State<CompanionPanel> {
  bool _isLinkCopied = false;

  @override
  void initState() {
    super.initState();
    FirebaseStreamer.instance.onConnectionLost = () {
      if (mounted) setState(() {});
    };
  }

  void _showErrorDialog(BuildContext context, String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.red[900],
        title: const Text('Error', style: TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showManualEntryDialog(BuildContext context, BlackBoxThemeData theme) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 350),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.15),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: FadeTransition(
            opacity: curvedAnimation,
            child: child,
          ),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        return _ConnectionCodeDialog(
          theme: theme,
          onError: (msg) => _showErrorDialog(context, msg),
          onConnected: () {
            if (mounted) setState(() {});
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = BlackBoxTheme.of(context);
    final isStreaming = FirebaseStreamer.instance.isStreaming;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: theme.cardBackground,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isStreaming
                        ? Icons.cloud_done_rounded
                        : Icons.cloud_off_rounded,
                    color: isStreaming ? Colors.green : theme.textPrimary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Desktop Companion',
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (isStreaming)
                    IconButton(
                      icon: const Icon(Icons.stop_rounded, color: Colors.red),
                      onPressed: () {
                        setState(() {
                          FirebaseStreamer.instance.stop();
                        });
                      },
                    ),
                ],
              ),
              if (!isStreaming) ...[
                const SizedBox(height: 16),
                const Text(
                  '1. Open the companion website on your Mac:',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          'flutter-blackbox-companion.web.app',
                          style:
                              TextStyle(color: theme.accentColor, fontSize: 13),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(const ClipboardData(
                              text:
                                  'https://flutter-blackbox-companion.web.app'));
                          setState(() {
                            _isLinkCopied = true;
                          });
                          Future.delayed(const Duration(seconds: 2), () {
                            if (mounted) {
                              setState(() {
                                _isLinkCopied = false;
                              });
                            }
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Icon(
                            _isLinkCopied
                                ? Icons.check_circle_rounded
                                : Icons.copy_rounded,
                            size: 16,
                            color: _isLinkCopied ? Colors.green : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '2. Enter the 6-digit code shown on the website:',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _showManualEntryDialog(context, theme),
                    icon: const Icon(Icons.keyboard_alt_outlined, size: 18),
                    label: const Text('Enter Code'),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 8),
                Text(
                  'Connected to session: ${FirebaseStreamer.instance.sessionId}',
                  style: TextStyle(color: theme.textSecondary, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Text(
              isStreaming
                  ? 'Streaming data to your Mac in real-time.\nLogs, network, crashes, and navigation are all being sent.'
                  : 'Stream your logs and network requests to your Mac in real-time.\nOpen the website and enter the connection code to begin.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.textSecondary),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Modern Connection Code Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _ConnectionCodeDialog extends StatefulWidget {
  const _ConnectionCodeDialog({
    required this.theme,
    required this.onError,
    required this.onConnected,
  });

  final BlackBoxThemeData theme;
  final void Function(String message) onError;
  final VoidCallback onConnected;

  @override
  State<_ConnectionCodeDialog> createState() => _ConnectionCodeDialogState();
}

class _ConnectionCodeDialogState extends State<_ConnectionCodeDialog>
    with TickerProviderStateMixin {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isConnecting = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    // Auto-focus the first field after the dialog animation settles.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _shimmerController.dispose();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _code => _controllers.map((c) => c.text).join();

  bool get _isCodeComplete => _code.length == 6;

  Future<void> _connect() async {
    if (_isConnecting || !_isCodeComplete) return;
    setState(() => _isConnecting = true);

    try {
      await FirebaseStreamer.instance.start(_code);
      BlackBox.broadcastDeviceInfo();
      if (!mounted) return;
      widget.onConnected();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isConnecting = false);
      widget.onError('Connection failed: $e');
    }
  }

  void _onDigitChanged(int index, String value) {
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    // Handle paste — if user pastes a full code into the first field.
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      for (int i = 0; i < 6 && i < digits.length; i++) {
        _controllers[i].text = digits[i];
      }
      final lastIdx = (digits.length - 1).clamp(0, 5);
      _focusNodes[lastIdx].requestFocus();
    }
    setState(() {}); // Refresh button state.
    if (_isCodeComplete) {
      _connect();
    }
  }

  void _onKeyEvent(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _controllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: theme.cardBackground.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: theme.accentColor.withValues(alpha: 0.2),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: theme.accentColor.withValues(alpha: 0.08),
                    blurRadius: 40,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Animated icon ────────────────────────────
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  theme.accentColor.withValues(
                                      alpha: 0.15 * _pulseAnimation.value),
                                  theme.accentColor.withValues(alpha: 0),
                                ],
                              ),
                            ),
                            child: Icon(
                              Icons.link_rounded,
                              color: theme.accentColor,
                              size: 28,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // ── Title ────────────────────────────────────
                      Text(
                        'Connect to Companion',
                        style: TextStyle(
                          color: theme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter the 6-digit code from the website',
                        style: TextStyle(
                          color: theme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 28),

                      // ── Digit input boxes ───────────────────────
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(6, (i) {
                            // Small gap after the 3rd digit for visual grouping.
                            final hasGap = i == 3;
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (hasGap) const SizedBox(width: 12),
                                _DigitBox(
                                  controller: _controllers[i],
                                  focusNode: _focusNodes[i],
                                  theme: theme,
                                  enabled: !_isConnecting,
                                  onChanged: (v) => _onDigitChanged(i, v),
                                  onKeyEvent: (e) => _onKeyEvent(i, e),
                                ),
                                if (i < 5) const SizedBox(width: 8),
                              ],
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // ── Connect button ──────────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: AnimatedBuilder(
                          animation: _shimmerController,
                          builder: (context, child) {
                            return DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: _isCodeComplete && !_isConnecting
                                    ? LinearGradient(
                                        colors: [
                                          theme.accentColor,
                                          HSLColor.fromColor(theme.accentColor)
                                              .withHue((HSLColor.fromColor(
                                                              theme.accentColor)
                                                          .hue +
                                                      30) %
                                                  360)
                                              .toColor(),
                                        ],
                                      )
                                    : null,
                                boxShadow: _isCodeComplete && !_isConnecting
                                    ? [
                                        BoxShadow(
                                          color: theme.accentColor
                                              .withValues(alpha: 0.35),
                                          blurRadius: 16,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: child,
                            );
                          },
                          child: ElevatedButton(
                            onPressed: _isCodeComplete && !_isConnecting
                                ? _connect
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              disabledBackgroundColor:
                                  theme.textMuted.withValues(alpha: 0.15),
                              foregroundColor: Colors.white,
                              disabledForegroundColor: theme.textMuted,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: EdgeInsets.zero,
                            ),
                            child: _isConnecting
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  Colors.white
                                                      .withValues(alpha: 0.9)),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Text(
                                        'Connecting…',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  )
                                : const Text(
                                    'Connect',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Cancel link ─────────────────────────────
                      TextButton(
                        onPressed:
                            _isConnecting ? null : () => Navigator.pop(context),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: _isConnecting
                                ? theme.textMuted
                                : theme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual Digit Input Box
// ─────────────────────────────────────────────────────────────────────────────

class _DigitBox extends StatefulWidget {
  const _DigitBox({
    required this.controller,
    required this.focusNode,
    required this.theme,
    required this.enabled,
    required this.onChanged,
    required this.onKeyEvent,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final BlackBoxThemeData theme;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final void Function(KeyEvent) onKeyEvent;

  @override
  State<_DigitBox> createState() => _DigitBoxState();
}

class _DigitBoxState extends State<_DigitBox> {
  late final FocusNode _wrapperFocusNode;

  @override
  void initState() {
    super.initState();
    _wrapperFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _wrapperFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 52,
      child: KeyboardListener(
        focusNode: _wrapperFocusNode,
        onKeyEvent: widget.onKeyEvent,
        child: AnimatedBuilder(
          animation: widget.focusNode,
          builder: (context, _) {
            final hasFocus = widget.focusNode.hasFocus;
            final hasValue = widget.controller.text.isNotEmpty;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: hasFocus
                    ? widget.theme.accentColor.withValues(alpha: 0.08)
                    : widget.theme.searchBarFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasFocus
                      ? widget.theme.accentColor
                      : hasValue
                          ? widget.theme.accentColor.withValues(alpha: 0.3)
                          : widget.theme.borderColor,
                  width: hasFocus ? 2.0 : 1.0,
                ),
                boxShadow: hasFocus
                    ? [
                        BoxShadow(
                          color:
                              widget.theme.accentColor.withValues(alpha: 0.15),
                          blurRadius: 8,
                          spreadRadius: 0,
                        ),
                      ]
                    : null,
              ),
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                enabled: widget.enabled,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 1,
                style: TextStyle(
                  color: widget.theme.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  counterText: '',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: widget.onChanged,
              ),
            );
          },
        ),
      ),
    );
  }
}
