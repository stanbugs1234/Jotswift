import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A page peeling away from its right edge, folding back over itself, with
/// [under] showing where it has lifted. [peel] is 0 (flat) to 1 (gone).
///
/// The fold is a straight line that sweeps from right to left, leaning so
/// the bottom corner leads mid-turn. The folded flap shows the back of the
/// paper.
class PageCurl extends StatelessWidget {
  const PageCurl({
    required this.peel,
    required this.page,
    required this.under,
    super.key,
  });

  final double peel;
  final Widget page;
  final Widget under;

  @override
  Widget build(BuildContext context) {
    if (peel <= 0.0005) return page;
    if (peel >= 0.9995) return under;
    return LayoutBuilder(
      builder: (context, constraints) {
        final fold = CurlFold.at(peel, constraints.biggest);
        return Stack(
          fit: StackFit.expand,
          children: [
            under,
            // The lifted page's shadow on the one underneath.
            IgnorePointer(child: CustomPaint(painter: _FoldShadow(fold))),
            ClipPath(clipper: _Side(fold, flat: true), child: page),
            // The flap: the peeled part, mirrored over the fold.
            IgnorePointer(
              child: Transform(
                transform: fold.reflection,
                child: ClipPath(
                  clipper: _Side(fold, flat: false),
                  // The back of the sheet: plain paper. (The page itself
                  // can't be shown twice.)
                  child: CustomPaint(
                    painter: _FlapShading(fold, _paperBack),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The back of a sheet: off-white, whatever the theme.
const _paperBack = Color(0xFFF3F1EC);

/// Where the fold lies on a page of [size]: points p with
/// `(p - point) · normal > 0` have peeled away.
@immutable
class CurlFold {
  const CurlFold(this.point, this.normal, this.size);

  /// The fold for [peel] (0–1) on a page of [size].
  factory CurlFold.at(double peel, Size size) {
    // Leaning most mid-turn, so the bottom corner lifts first.
    final lean = 0.32 * math.sin(math.pi * peel);
    final normal = Offset(1, lean) / math.sqrt(1 + lean * lean);
    // From just past the right edge (nothing peeled) to just past the left
    // (all of it), measured across the middle of the page.
    final reach = lean * size.height / 2;
    final from = size.width + reach + 1;
    final to = -reach - 1;
    final x = from + (to - from) * peel;
    return CurlFold(Offset(x, size.height / 2), normal, size);
  }

  final Offset point;
  final Offset normal;
  final Size size;

  double distance(Offset p) =>
      (p.dx - point.dx) * normal.dx + (p.dy - point.dy) * normal.dy;

  /// Mirrors points across the fold.
  Matrix4 get reflection {
    final nx = normal.dx, ny = normal.dy;
    final c = point.dx * nx + point.dy * ny;
    return Matrix4(
      1 - 2 * nx * nx,
      -2 * nx * ny,
      0,
      0, //
      -2 * nx * ny,
      1 - 2 * ny * ny,
      0,
      0, //
      0,
      0,
      1,
      0, //
      2 * c * nx,
      2 * c * ny,
      0,
      1,
    );
  }

  /// The page's part on one side of the fold.
  Path side({required bool flat}) {
    final corners = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(size.width, size.height),
      Offset(0, size.height),
    ];
    bool keep(Offset p) => flat ? distance(p) <= 0 : distance(p) >= 0;
    final points = <Offset>[];
    for (var i = 0; i < 4; i++) {
      final a = corners[i], b = corners[(i + 1) % 4];
      if (keep(a)) points.add(a);
      final da = distance(a), db = distance(b);
      if ((da < 0) != (db < 0) && da != db) {
        points.add(Offset.lerp(a, b, da / (da - db))!);
      }
    }
    final path = Path();
    if (points.isEmpty) return path;
    return path..addPolygon(points, true);
  }

  /// The furthest any of the page lies past the fold.
  double get depth => [
    Offset.zero,
    Offset(size.width, 0),
    Offset(size.width, size.height),
    Offset(0, size.height),
  ].map(distance).reduce(math.max);
}

class _Side extends CustomClipper<Path> {
  _Side(this.fold, {required this.flat});

  final CurlFold fold;
  final bool flat;

  @override
  Path getClip(Size size) => fold.side(flat: flat);

  @override
  bool shouldReclip(_Side old) =>
      old.fold.point != fold.point || old.flat != flat;
}

/// The flap's shading, in the page's own (unmirrored) coordinates: bright
/// along the fold where the paper bends towards the light, dimmer at its
/// edge.
class _FlapShading extends CustomPainter {
  _FlapShading(this.fold, this.paper);

  final CurlFold fold;
  final Color paper;

  @override
  void paint(Canvas canvas, Size size) {
    final depth = math.max(fold.depth, 1.0);
    canvas.drawRect(Offset.zero & size, Paint()..color = paper);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          fold.point,
          fold.point + fold.normal * depth,
          [
            Colors.black.withValues(alpha: 0.16),
            Colors.white.withValues(alpha: 0.10),
            Colors.black.withValues(alpha: 0.06),
          ],
          const [0, 0.18, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_FlapShading old) =>
      old.fold.point != fold.point || old.paper != paper;
}

/// A soft shadow cast on the page underneath, just past the fold.
class _FoldShadow extends CustomPainter {
  _FoldShadow(this.fold);

  final CurlFold fold;

  @override
  void paint(Canvas canvas, Size size) {
    final shader = ui.Gradient.linear(
      fold.point,
      fold.point + fold.normal * 36,
      [Colors.black.withValues(alpha: 0.28), Colors.black.withValues(alpha: 0)],
    );
    canvas
      ..save()
      ..clipPath(fold.side(flat: false))
      ..drawRect(Offset.zero & size, Paint()..shader = shader)
      ..restore();
  }

  @override
  bool shouldRepaint(_FoldShadow old) => old.fold.point != fold.point;
}
