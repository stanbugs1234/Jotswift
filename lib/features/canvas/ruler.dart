import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A straight edge on the page, in page units. Fingers move and turn it;
/// the pen, started against one of its long edges, draws straight along
/// it.
@immutable
class Ruler {
  const Ruler({required this.center, this.angle = 0});

  final Offset center;

  /// Radians, clockwise from level.
  final double angle;

  static const length = 1100.0;
  static const thickness = 110.0;

  /// How close to an edge (page units) a stroke must start to follow it.
  static const snap = 36.0;

  Offset get _along => Offset(math.cos(angle), math.sin(angle));
  Offset get _across => Offset(-math.sin(angle), math.cos(angle));

  /// [p] in the ruler's own coordinates: x along it, y across, from its
  /// middle.
  Offset toLocal(Offset p) {
    final d = p - center;
    return Offset(
      d.dx * _along.dx + d.dy * _along.dy,
      d.dx * _across.dx + d.dy * _across.dy,
    );
  }

  Offset toPage(Offset local) =>
      center + _along * local.dx + _across * local.dy;

  bool contains(Offset p) {
    final l = toLocal(p);
    return l.dx.abs() <= length / 2 && l.dy.abs() <= thickness / 2;
  }

  /// The long edge [p] is next to (just outside it, or just inside it),
  /// as -1 (top) or 1 (bottom); null when it's not near either.
  int? edgeNear(Offset p) {
    final l = toLocal(p);
    if (l.dx.abs() > length / 2 + snap) return null;
    for (final side in const [-1, 1]) {
      final edge = side * thickness / 2;
      if ((l.dy - edge).abs() <= snap) return side;
    }
    return null;
  }

  /// [p] moved onto the line a pen of [width] draws along on [side]: just
  /// outside the edge, so the ink touches it.
  Offset project(Offset p, int side, double width) {
    final l = toLocal(p);
    return toPage(Offset(l.dx, side * (thickness / 2 + width / 2 + 2)));
  }

  Ruler copyWith({Offset? center, double? angle}) =>
      Ruler(center: center ?? this.center, angle: angle ?? this.angle);

  /// The angle in whole degrees, 0-179, as the ruler shows it.
  int get degrees {
    final d = (angle * 180 / math.pi).round() % 180;
    return d < 0 ? d + 180 : d;
  }

  @override
  bool operator ==(Object other) =>
      other is Ruler && other.center == center && other.angle == angle;

  @override
  int get hashCode => Object.hash(center, angle);
}

/// Snaps [angle] to every 45 degrees when within 3 degrees.
double snapRulerAngle(double angle) {
  const step = math.pi / 4;
  final nearest = (angle / step).roundToDouble() * step;
  return (angle - nearest).abs() < 3 * math.pi / 180 ? nearest : angle;
}

/// Whether the ruler is out. Shared by every page.
class RulerVisible extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final rulerVisibleProvider = NotifierProvider<RulerVisible, bool>(
  RulerVisible.new,
);

/// The ruler: see-through, with marks along both edges and its angle in
/// the middle.
class RulerPainter extends CustomPainter {
  RulerPainter(this.ruler, this.color);

  final Ruler ruler;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..translate(ruler.center.dx, ruler.center.dy)
      ..rotate(ruler.angle);
    const w = Ruler.length / 2, h = Ruler.thickness / 2;
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTRB(-w, -h, w, h),
      const Radius.circular(10),
    );
    canvas
      ..drawRRect(
        body,
        Paint()..color = const Color(0xFFF4F6F8).withValues(alpha: 0.82),
      )
      ..drawRRect(
        body,
        Paint()
          ..color = color.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    final tick = Paint()
      ..color = const Color(0xFF37474F)
      ..strokeWidth = 1.5;
    for (var x = -w + 20; x <= w - 20; x += 20) {
      final major = ((x + w - 20) / 20).round() % 5 == 0;
      final len = major ? 22.0 : 12.0;
      canvas
        ..drawLine(Offset(x, -h), Offset(x, -h + len), tick)
        ..drawLine(Offset(x, h), Offset(x, h - len), tick);
    }
    final label = TextPainter(
      text: TextSpan(
        text: '${ruler.degrees}°',
        style: const TextStyle(
          color: Color(0xFF263238),
          fontSize: 30,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(-label.width / 2, -label.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(RulerPainter old) =>
      old.ruler != ruler || old.color != color;
}
