import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../blackbox.dart';

/// Wrap any widget to manually track its rebuild count.
///
/// ```dart
/// RebuildTracker(
///   label: 'ProductCard',
///   child: ProductCard(),
/// )
/// ```
///
/// ## Release-mode safety
///
/// In release builds (`kDebugMode == false`), this widget is a **zero-cost
/// pass-through** — the recording code is completely eliminated by Dart's
/// tree-shaker because `kDebugMode` is a compile-time constant. The widget
/// simply returns [child] with no extra widget layer and no runtime overhead.
///
/// **You can safely leave `RebuildTracker` wrappers in production code.**
///
/// For automatic tracking of ALL widgets (debug mode only),
/// call `BlackBox.startRebuildTracking()` instead — no wrapping needed.
class RebuildTracker extends StatelessWidget {
  const RebuildTracker({
    super.key,
    required this.label,
    required this.child,
  });

  /// A human-readable label for this widget (e.g. 'ProductCard', 'CartItem').
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // kDebugMode is a compile-time constant.
    // In release builds, the compiler removes this entire if-block
    // and RebuildTracker becomes a zero-cost wrapper.
    if (kDebugMode && BlackBox.instance.isEnabled) {
      BlackBox.instance.rebuildStore.record(label);
    }
    return child;
  }
}
