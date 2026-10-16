import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'motion.dart';
import 'transition_frames.dart';

/// Ways to move from one month (or year) to the next.
enum PeriodAnimation {
  /// Lifts and flips up over the top edge, like a hanging wall calendar.
  wallFlip('Wall flip'),

  /// Turns around the left edge, like a book page.
  pageTurn('Page turn'),

  /// The two periods are faces of a cube that rotates.
  cube('Cube'),

  /// Cards swing past in depth, like a carousel.
  carousel('Carousel'),

  /// Slides in from the side.
  slide('Slide'),

  /// Crossfades.
  fade('Fade'),

  /// The next one slides up over the current one like a stacked card.
  stack('Stack');

  const PeriodAnimation(this.label);

  final String label;
}

/// Shows [child] and, when [period] changes, animates from the old view to
/// the new one with [animation]. Going forward or back is decided by
/// [period]'s order. Reduced animations crossfade; Off swaps at once. A
/// change during a transition finishes the old one at once.
class PeriodTransition<T extends Comparable<T>> extends StatefulWidget {
  const PeriodTransition({
    required this.animation,
    required this.period,
    required this.child,
    super.key,
  });

  final PeriodAnimation animation;
  final T period;
  final Widget child;

  @override
  State<PeriodTransition<T>> createState() => _PeriodTransitionState<T>();
}

class _PeriodTransitionState<T extends Comparable<T>>
    extends State<PeriodTransition<T>>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this);
  Widget? _leaving;
  var _forward = true;

  @override
  void didUpdateWidget(PeriodTransition<T> old) {
    super.didUpdateWidget(old);
    if (old.period.compareTo(widget.period) == 0) return;
    final motion = Motion.of(context);
    if (motion.off) {
      _leaving = null;
      return;
    }
    _leaving = KeyedSubtree(key: ValueKey(old.period), child: old.child);
    _forward = widget.period.compareTo(old.period) > 0;
    final long = switch (widget.animation) {
      PeriodAnimation.slide || PeriodAnimation.fade => MotionTokens.standard,
      _ => MotionTokens.emphasized,
    };
    _controller
      ..duration = motion.duration(long)
      ..forward(from: 0).whenCompleteOrCancel(() {
        if (mounted && _controller.isCompleted) {
          setState(() => _leaving = null);
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = KeyedSubtree(
      key: ValueKey(widget.period),
      child: widget.child,
    );
    final leaving = _leaving;
    if (leaving == null) return current;
    final reduced = !Motion.of(context).full;
    final old = IgnorePointer(child: leaving);
    return LayoutBuilder(
      builder: (context, constraints) {
        final animation = reduced ? PeriodAnimation.fade : widget.animation;
        final frames = AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => _frame(
            animation,
            _controller.value,
            constraints.biggest,
            old,
            current,
          ),
        );
        // Flat moves stay inside the view; 3D turns may lean out of it.
        return switch (animation) {
          PeriodAnimation.slide ||
          PeriodAnimation.stack => ClipRect(child: frames),
          _ => frames,
        };
      },
    );
  }

  Widget _frame(
    PeriodAnimation animation,
    double raw,
    Size size,
    Widget old,
    Widget current,
  ) {
    final f = _forward;
    final t = MotionTokens.move.transform(raw);
    Widget stack(List<Widget> children) =>
        Stack(fit: StackFit.expand, children: children);
    switch (animation) {
      case PeriodAnimation.fade:
        return fadeFrame(t, old, current);
      case PeriodAnimation.slide:
        return slideFrame(t, size, old, current, forward: f);
      case PeriodAnimation.pageTurn:
        // Forward: the old page swings away around its left edge. Back: the
        // new page swings back in over the old one.
        final swing = f
            ? MotionTokens.exit.transform(raw)
            : 1 - MotionTokens.enter.transform(raw);
        return stack([
          shade(f ? current : old, 0.18 * (1 - swing)),
          hinged(
            f ? old : current,
            swing,
            alignment: Alignment.centerLeft,
            rotate: (m, a) => m..rotateY(-a),
          ),
        ]);
      case PeriodAnimation.wallFlip:
        // Forward: the old month lifts up over the top edge. Back: the
        // previous month swings down over the current one.
        final swing = f
            ? MotionTokens.exit.transform(raw)
            : 1 - MotionTokens.enter.transform(raw);
        return stack([
          shade(f ? current : old, 0.22 * (1 - swing)),
          hinged(
            f ? old : current,
            swing,
            alignment: Alignment.topCenter,
            // Toward the viewer, like lifting a hanging page.
            rotate: (m, a) => m..rotateX(-a),
          ),
        ]);
      case PeriodAnimation.cube:
        // The shared edge travels across; each face folds around it.
        final s = f ? 1.0 : -1.0;
        final angle = math.pi / 2;
        Widget face(Widget child, double turn, Alignment hinge, double shift) =>
            Transform.translate(
              offset: Offset(shift, 0),
              child: Transform(
                alignment: hinge,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0011)
                  ..rotateY(turn),
                child: shade(child, 0.4 * (turn.abs() / angle)),
              ),
            );
        return stack([
          face(
            old,
            s * t * angle,
            f ? Alignment.centerRight : Alignment.centerLeft,
            -s * size.width * t,
          ),
          face(
            current,
            -s * (1 - t) * angle,
            f ? Alignment.centerLeft : Alignment.centerRight,
            s * size.width * (1 - t),
          ),
        ]);
      case PeriodAnimation.carousel:
        final s = f ? 1.0 : -1.0;
        Widget card(Widget child, double p) => Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..translateByDouble(-s * size.width * 0.62 * p, 0, 0, 1)
            ..scaleByDouble(1 - 0.22 * p.abs(), 1 - 0.22 * p.abs(), 1, 1)
            ..rotateY(s * 0.7 * p),
          child: Opacity(
            opacity: (1 - p.abs() * 0.7).clamp(0, 1),
            child: child,
          ),
        );
        // The card further back is drawn first.
        final oldFirst = t > 0.5;
        final a = card(old, t);
        final b = card(current, t - 1);
        return stack(oldFirst ? [a, b] : [b, a]);
      case PeriodAnimation.stack:
        // Forward: the new card slides up on top while the old one sinks.
        // Back: the top card slides down off the stack.
        return stackFrame(t, size, old, current, forward: f);
    }
  }
}
