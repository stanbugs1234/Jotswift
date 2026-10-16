import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Single frames of transitions between two views, shared by page turns
/// and calendar month changes. Each takes the view leaving ([old]), the
/// view arriving ([current]) and how far along the move is (0–1, already
/// eased).

Widget _stack(List<Widget> children) =>
    Stack(fit: StackFit.expand, children: children);

/// [old] fades out as [current] fades in.
Widget fadeFrame(double t, Widget old, Widget current) => _stack([
  Opacity(opacity: 1 - t, child: old),
  Opacity(opacity: t, child: current),
]);

/// [current] slides in from the side as [old] slides out the other way:
/// the full width, like pages side by side ([full]), or a short way with a
/// crossfade.
Widget slideFrame(
  double t,
  Size size,
  Widget old,
  Widget current, {
  required bool forward,
  bool full = false,
}) {
  final dx = size.width * (full ? 1.0 : 0.35) * (forward ? 1 : -1);
  Widget fade(double o, Widget child) =>
      full ? child : Opacity(opacity: o, child: child);
  return _stack([
    fade(1 - t, Transform.translate(offset: Offset(-dx * t, 0), child: old)),
    fade(
      t,
      Transform.translate(offset: Offset(dx * (1 - t), 0), child: current),
    ),
  ]);
}

/// Forward: [current] slides over [old] like a card dealt on top, from
/// [from] (below, or from the right). Back: the top card slides away again.
Widget stackFrame(
  double t,
  Size size,
  Widget old,
  Widget current, {
  required bool forward,
  AxisDirection from = AxisDirection.up,
}) {
  final top = forward ? current : old;
  final under = forward ? old : current;
  final p = forward ? t : 1 - t; // how far the top card is in place
  final away = switch (from) {
    AxisDirection.up => Offset(0, size.height),
    AxisDirection.left => Offset(size.width, 0),
    AxisDirection.down => Offset(0, -size.height),
    AxisDirection.right => Offset(-size.width, 0),
  };
  return _stack([
    Transform.scale(scale: 1 - 0.06 * p, child: shade(under, 0.25 * p)),
    Transform.translate(
      offset: away * (1 - p),
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18 * p),
              blurRadius: 24,
              offset: from == AxisDirection.up
                  ? const Offset(0, -6)
                  : const Offset(-6, 0),
            ),
          ],
        ),
        child: top,
      ),
    ),
  ]);
}

/// [child] turned by [swing] (0 flat, 1 edge-on) around [alignment],
/// darkening as it turns.
Widget hinged(
  Widget child,
  double swing, {
  required Alignment alignment,
  required Matrix4 Function(Matrix4, double) rotate,
}) {
  if (swing >= 0.999) return const SizedBox.shrink();
  return Transform(
    alignment: alignment,
    transform: rotate(
      Matrix4.identity()..setEntry(3, 2, 0.0012),
      swing * math.pi / 2,
    ),
    child: shade(child, 0.35 * swing),
  );
}

/// [child] darkened by [amount] (0–1).
Widget shade(Widget child, double amount) {
  if (amount <= 0.001) return child;
  return _stack([
    child,
    IgnorePointer(
      child: ColoredBox(color: Colors.black.withValues(alpha: amount)),
    ),
  ]);
}
