import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'motion.dart';

/// A route page that opens like a book: [cover] fills the screen, then
/// swings open around its left edge to reveal [child]. Going back swings it
/// shut again.
///
/// Reduced animations fade instead; Off shows the screen at once.
CustomTransitionPage<void> bookOpenPage({
  required BuildContext context,
  required LocalKey key,
  required Widget cover,
  required Widget child,
}) {
  final motion = Motion.of(context);
  final duration = motion.duration(MotionTokens.emphasized);
  return CustomTransitionPage<void>(
    key: key,
    child: child,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (!motion.full) {
        return FadeTransition(opacity: animation, child: child);
      }
      return BookOpenTransition(
        animation: animation,
        cover: cover,
        child: child,
      );
    },
  );
}

class BookOpenTransition extends StatelessWidget {
  const BookOpenTransition({
    required this.animation,
    required this.cover,
    required this.child,
    super.key,
  });

  final Animation<double> animation;
  final Widget cover;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = animation.value;
        // The first fifth zooms the cover in; the rest swings it open.
        final zoom = MotionTokens.enter.transform((t / 0.2).clamp(0.0, 1.0));
        final open = MotionTokens.move.transform(
          ((t - 0.2) / 0.8).clamp(0.0, 1.0),
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            // The notebook underneath comes forward as the cover opens.
            Opacity(
              opacity: open,
              child: Transform.scale(scale: 0.94 + 0.06 * open, child: child),
            ),
            if (open < 1)
              IgnorePointer(
                child: Opacity(
                  opacity: zoom,
                  child: Transform(
                    alignment: Alignment.centerLeft,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..scaleByDouble(
                        0.85 + 0.15 * zoom,
                        0.85 + 0.15 * zoom,
                        1,
                        1,
                      )
                      ..rotateY(-open * math.pi / 2),
                    child: _CoverFace(open: open, cover: cover),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The cover stretched over the screen, shading as it turns away.
class _CoverFace extends StatelessWidget {
  const _CoverFace({required this.open, required this.cover});

  final double open;
  final Widget cover;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: FittedBox(fit: BoxFit.cover, child: cover),
        ),
        ColoredBox(color: Colors.black.withValues(alpha: 0.4 * open)),
      ],
    );
  }
}
