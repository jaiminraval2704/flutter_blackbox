import 'dart:math';

import 'package:flutter/widgets.dart';

/// Wraps a child widget with a lightweight fade-in animation.
///
/// Only the first [_maxAnimated] items animate (to avoid hundreds of
/// timers in long lists). Items beyond the cap render instantly.
class StaggeredListItem extends StatefulWidget {
  const StaggeredListItem({
    super.key,
    required this.index,
    required this.child,
  });

  /// Position in the list — controls the stagger delay.
  final int index;

  /// The content to animate in.
  final Widget child;

  @override
  State<StaggeredListItem> createState() => _StaggeredListItemState();
}

class _StaggeredListItemState extends State<StaggeredListItem> {
  static const _maxAnimated = 8;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    if (widget.index >= _maxAnimated) {
      // Skip animation for items beyond the cap — render instantly.
      _visible = true;
      return;
    }
    final delay = Duration(milliseconds: min(widget.index * 30, 210));
    Future.delayed(delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      opacity: _visible ? 1.0 : 0.0,
      child: widget.child,
    );
  }
}
