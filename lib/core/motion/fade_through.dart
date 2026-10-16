import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'motion.dart';

/// A route page that fades in while settling from slightly large, as the
/// screen beneath fades away. It has no swipe-back from the left edge, which
/// on a notebook page turns back a page instead.
///
/// Reduced animations just fade; Off shows the screen at once.
CustomTransitionPage<void> fadeThroughPage({
  required BuildContext context,
  required LocalKey key,
  required Widget child,
}) {
  final motion = Motion.of(context);
  final duration = motion.duration(MotionTokens.standard);
  return CustomTransitionPage<void>(
    key: key,
    child: child,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (!motion.full) {
        return FadeTransition(opacity: animation, child: child);
      }
      final enter = CurvedAnimation(
        parent: animation,
        curve: const Interval(0.3, 1, curve: MotionTokens.enter),
        reverseCurve: const Interval(0.3, 1, curve: MotionTokens.exit),
      );
      return FadeTransition(
        opacity: enter,
        child: ScaleTransition(
          scale: Tween(begin: 1.04, end: 1.0).animate(enter),
          child: child,
        ),
      );
    },
  );
}
