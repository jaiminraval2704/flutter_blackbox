import 'package:flutter/painting.dart';

import '../../core/log/log_level.dart';

/// Centralised color tokens for the BlackBox UI.
abstract final class BlackBoxColors {
  static const success = Color(0xFF1D9E75);
  static const warning = Color(0xFFBA7517);
  static const error = Color(0xFFE24B4A);
  static const info = Color(0xFF378ADD);

  static Color forLevel(LogLevel level) => switch (level) {
        LogLevel.verbose => const Color(0xFF888780),
        LogLevel.debug => const Color(0xFF378ADD),
        LogLevel.info => success,
        LogLevel.warning => warning,
        LogLevel.error => error,
      };

  static Color fpsColor(double fps) {
    if (fps >= 55) return success;
    if (fps >= 30) return warning;
    return error;
  }
}
