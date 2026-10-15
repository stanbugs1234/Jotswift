import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'motion.dart';

enum TurnDirection { forward, backward }

/// Shows [child] and, when [pageKey] changes, turns from the old page to the
/// new one like paper in a book.
///
/// - Forward (the new page comes later in [order]): the old page swings away
///   around its left edge, revealing the new page underneath.
/// - Backward: the new page swings back in over the old one.
///
/// Reduced animations crossfade instead, and Off swaps at once. The page
/// that's leaving ignores touches, so nothing can be drawn on it.
class PageTurnSwitcher extends StatefulWidget {
  const PageTurnSwitcher({
    required this.pageKey,
    required this.order,
    required this.child,
    super.key,
  });

  /// Identifies the page being shown; a new value starts a turn.
  final Object pageKey;

  /// Page keys in reading order, which decides the direction of a turn.
  /// Keys not in it turn forward.
  final List<Object> order;
  final Widget child;

  @override
  State<PageTurnSwitcher> createState() => _PageTurnSwitcherState();
}

class _PageTurnSwitcherState extends State<PageTurnSwitcher>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this);
  Widget? _leaving;
  TurnDirection _direction = TurnDirection.forward;

  @override
  void didUpdateWidget(PageTurnSwitcher old) {
    super.didUpdateWidget(old);
    if (old.pageKey == widget.pageKey) return;

    final motion = Motion.of(context);
    if (motion.off) {
      _finish();
      return;
    }
    _leaving = KeyedSubtree(key: ValueKey(old.pageKey), child: old.child);
    _direction = directionBetween(widget.order, old.pageKey, widget.pageKey);
    _controller
      ..duration = motion.duration(MotionTokens.emphasized)
      ..forward(from: 0).whenComplete(_finish);
  }

  void _finish() {
    if (!mounted || _leaving == null) return;
    setState(() => _leaving = null);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = KeyedSubtree(
      key: ValueKey(widget.pageKey),
      child: widget.child,
    );
    final leaving = _leaving;
    if (leaving == null || leaving.key == current.key) return current;

    final reduced = !Motion.of(context).full;
    final leavingPage = IgnorePointer(child: leaving);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        if (reduced) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Opacity(opacity: 1 - t, child: leavingPage),
              Opacity(opacity: t, child: current),
            ],
          );
        }
        final forward = _direction == TurnDirection.forward;
        // How far the turning page has swung: 0 = flat, 1 = edge-on.
        final swing = forward
            ? MotionTokens.exit.transform(t)
            : 1 - MotionTokens.enter.transform(t);
        final turning = forward ? leavingPage : current;
        final under = forward ? current : leavingPage;
        return Stack(
          fit: StackFit.expand,
          children: [
            // The page underneath darkens slightly while covered.
            _Shaded(amount: 0.18 * (1 - swing), child: under),
            _TurningPage(swing: swing, child: turning),
          ],
        );
      },
    );
  }
}

/// Backward when [to] comes before [from] in [order]; otherwise forward.
TurnDirection directionBetween(List<Object> order, Object from, Object to) {
  final a = order.indexOf(from);
  final b = order.indexOf(to);
  return a >= 0 && b >= 0 && b < a
      ? TurnDirection.backward
      : TurnDirection.forward;
}

/// A page rotated around its left edge by [swing] (0–1 of a quarter turn),
/// with perspective and a shadow that deepens as it turns.
class _TurningPage extends StatelessWidget {
  const _TurningPage({required this.swing, required this.child});

  final double swing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (swing >= 0.999) return const SizedBox.shrink();
    return Transform(
      alignment: Alignment.centerLeft,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0012) // perspective
        ..rotateY(-swing * math.pi / 2),
      child: _Shaded(amount: 0.35 * swing, fromRight: true, child: child),
    );
  }
}

/// [child] with a dark gradient over it, [amount] 0–1.
class _Shaded extends StatelessWidget {
  const _Shaded({
    required this.amount,
    required this.child,
    this.fromRight = false,
  });

  final double amount;
  final bool fromRight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (amount <= 0.001) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: fromRight ? Alignment.centerLeft : Alignment.centerRight,
                end: fromRight ? Alignment.centerRight : Alignment.centerLeft,
                colors: [
                  Colors.black.withValues(alpha: amount * 0.3),
                  Colors.black.withValues(alpha: amount),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
