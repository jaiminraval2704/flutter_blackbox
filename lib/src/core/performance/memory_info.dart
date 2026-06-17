// Platform-safe memory info.
//
// Uses conditional imports to call dart:io on native and return 0 on web.
export 'memory_info_web.dart' if (dart.library.io) 'memory_info_native.dart';
