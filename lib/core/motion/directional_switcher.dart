import 'package:flutter/material.dart';

import 'motion.dart';

/// Swaps [child] whenever [position] changes, sliding the new one in from
/// the side it lies on: from the right when [position] grows (next month),
/// from the left when it shrinks (previous month).
///
/// Reduced animations crossfade; Off swaps at once.
class DirectionalSwitcher<T extends Comparable<T>> extends StatefulWidget {
  const DirectionalSwitcher({
    required this.position,
    required this.child,
    super.key,
  });

  final T position;
  final Widget child;

  @override
  State<DirectionalSwitcher<T>> createState() => _DirectionalSwitcherState<T>();
}

class _DirectionalSwitcherState<T extends Comparable<T>>
    extends State<DirectionalSwitcher<T>> {
  /// 1 when moving forward, -1 when moving back.
  double _direction = 1;

  @override
  void didUpdateWidget(DirectionalSwitcher<T> old) {
    super.didUpdateWidget(old);
    final c = widget.position.compareTo(old.position);
    if (c != 0) _direction = c > 0 ? 1 : -1;
  }

  @override
  Widget build(BuildContext context) {
    final motion = Motion.of(context);
    final currentKey = ValueKey<T>(widget.position);
    return AnimatedSwitcher(
      duration: motion.duration(MotionTokens.standard),
      switchInCurve: MotionTokens.enter,
      switchOutCurve: MotionTokens.exit,
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      transitionBuilder: (child, animation) {
        if (!motion.full) {
          return FadeTransition(opacity: animation, child: child);
        }
        final incoming = child.key == currentKey;
        // Incoming starts on the far side; outgoing leaves the other way.
        // (The outgoing animation runs from 1 down to 0.)
        final from = Offset((incoming ? 1 : -1) * _direction * 0.35, 0);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(begin: from, end: Offset.zero).animate(animation),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(key: currentKey, child: widget.child),
    );
  }
}
