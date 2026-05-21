import 'package:flutter/widgets.dart';

/// Color and style tokens for the BlackBox overlay UI.
///
/// Pass an instance to [BlackBox.setup] to customise the look of the
/// overlay.  Two convenience constructors are provided:
///
/// * [BlackBoxThemeData.dark] — the default dark theme (current look).
/// * [BlackBoxThemeData.light] — a clean light theme.
///
/// ```dart
/// BlackBox.setup(
///   theme: BlackBoxThemeData.light(),
/// );
/// ```
class BlackBoxThemeData {
  const BlackBoxThemeData({
    required this.panelBackground,
    required this.headerBackground,
    required this.cardBackground,
    required this.accentColor,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.borderColor,
    required this.searchBarFill,
    required this.badgeColor,
    required this.surfaceOverlay,
    required this.dragHandleColor,
    required this.backdropColor,
  });

  /// Default dark theme — matches the original hardcoded look.
  const BlackBoxThemeData.dark()
      : panelBackground = const Color(0xFF12121F),
        headerBackground = const Color(0xFF1A1A2E),
        cardBackground = const Color(0xFF12121F),
        accentColor = const Color(0xFF6C63FF),
        textPrimary = const Color(0xFFFFFFFF),
        textSecondary = const Color(0xB3FFFFFF), // white70
        textMuted = const Color(0x61FFFFFF), // white38
        borderColor = const Color(0x1AFFFFFF), // white10
        searchBarFill = const Color(0x0FFFFFFF), // white ~6%
        badgeColor = const Color(0xFF6C63FF),
        surfaceOverlay = const Color(0x08FFFFFF), // white ~3%
        dragHandleColor = const Color(0x4DFFFFFF), // white30
        backdropColor = const Color(0x80000000); // black50

  /// Clean light theme for apps that use a light design.
  const BlackBoxThemeData.light()
      : panelBackground = const Color(0xFFF5F5FA),
        headerBackground = const Color(0xFFFFFFFF),
        cardBackground = const Color(0xFFFFFFFF),
        accentColor = const Color(0xFF6C63FF),
        textPrimary = const Color(0xFF1A1A2E),
        textSecondary = const Color(0xFF4A4A5A),
        textMuted = const Color(0xFF9A9AAA),
        borderColor = const Color(0x1A000000), // black10
        searchBarFill = const Color(0x0A000000), // black ~4%
        badgeColor = const Color(0xFF6C63FF),
        surfaceOverlay = const Color(0x08000000), // black ~3%
        dragHandleColor = const Color(0x4D000000), // black30
        backdropColor = const Color(0x40000000); // black25

  /// Main background colour of the panel body / card area.
  final Color panelBackground;

  /// Background colour of the header bar (title + tabs).
  final Color headerBackground;

  /// Background colour of the content card.
  final Color cardBackground;

  /// Accent colour used for highlights, active indicators, badges.
  final Color accentColor;

  /// Primary text colour (titles, labels).
  final Color textPrimary;

  /// Secondary text colour (values, descriptions).
  final Color textSecondary;

  /// Muted text colour (hints, placeholders, timestamps).
  final Color textMuted;

  /// Border colour for cards, dividers.
  final Color borderColor;

  /// Fill colour for search bars and text fields.
  final Color searchBarFill;

  /// Badge background colour (e.g., "BlackBox" badge).
  final Color badgeColor;

  /// Very subtle overlay used on expanded detail areas.
  final Color surfaceOverlay;

  /// Colour of the drag handle on the resizable panel.
  final Color dragHandleColor;

  /// Backdrop colour shown behind the panel.
  final Color backdropColor;
}

/// Provides [BlackBoxThemeData] to the overlay widget tree.
///
/// Inserted by [BlackBoxOverlay]; panels read it via
/// `BlackBoxTheme.of(context)`.
class BlackBoxTheme extends InheritedWidget {
  const BlackBoxTheme({
    super.key,
    required this.data,
    required super.child,
  });

  final BlackBoxThemeData data;

  /// Retrieves the nearest [BlackBoxThemeData].
  ///
  /// Falls back to [BlackBoxThemeData.dark] when no ancestor is found
  /// (defensive — should never happen inside the overlay tree).
  static BlackBoxThemeData of(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<BlackBoxTheme>();
    return widget?.data ?? const BlackBoxThemeData.dark();
  }

  @override
  bool updateShouldNotify(BlackBoxTheme oldWidget) => data != oldWidget.data;
}
