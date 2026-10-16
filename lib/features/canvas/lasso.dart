import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/page_element.dart';
import 'domain/stroke.dart';

/// Whether [point] is inside the closed [polygon] (even-odd rule).
bool polygonContains(List<Offset> polygon, Offset point) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[i], b = polygon[j];
    if ((a.dy > point.dy) != (b.dy > point.dy) &&
        point.dx < (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

/// Whether a lasso drawn as [polygon] takes [stroke]: most of its points
/// are inside, so a loop that clips the edge of a word doesn't grab it.
bool lassoTakesStroke(List<Offset> polygon, Stroke stroke) {
  if (stroke.points.isEmpty) return false;
  final inside = stroke.points
      .where((p) => polygonContains(polygon, p.offset))
      .length;
  return inside * 2 >= stroke.points.length;
}

/// Whether a lasso drawn as [polygon] takes [element]: its middle is inside.
bool lassoTakesElement(List<Offset> polygon, PageElement element) =>
    polygonContains(polygon, element.frame.center);

/// A move, uniform scale and rotation about [pivot], in page units:
/// `p' = pivot + rotate(scale * (p - pivot)) + translate`.
@immutable
class LassoTransform {
  const LassoTransform({
    required this.pivot,
    this.translate = Offset.zero,
    this.scale = 1,
    this.rotation = 0,
  });

  final Offset pivot;
  final Offset translate;
  final double scale;

  /// Radians, clockwise.
  final double rotation;

  bool get isIdentity =>
      translate == Offset.zero && scale == 1 && rotation == 0;

  Offset apply(Offset p) {
    final d = (p - pivot) * scale;
    final c = math.cos(rotation), s = math.sin(rotation);
    return pivot + Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c) + translate;
  }

  /// The point that [apply] maps to [p].
  Offset invert(Offset p) {
    final d = p - translate - pivot;
    final c = math.cos(-rotation), s = math.sin(-rotation);
    return pivot + Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c) / scale;
  }

  LassoTransform copyWith({
    Offset? translate,
    double? scale,
    double? rotation,
  }) => LassoTransform(
    pivot: pivot,
    translate: translate ?? this.translate,
    scale: scale ?? this.scale,
    rotation: rotation ?? this.rotation,
  );

  /// The same transform for a canvas: draw with this, then the shapes.
  void applyToCanvas(Canvas canvas) {
    canvas
      ..translate(pivot.dx + translate.dx, pivot.dy + translate.dy)
      ..rotate(rotation)
      ..scale(scale)
      ..translate(-pivot.dx, -pivot.dy);
  }

  /// [stroke] moved by this transform, as a new stroke with [id]. Widths
  /// grow and shrink with the scale.
  Stroke applyToStroke(
    Stroke stroke,
    String id, {
    int? color,
    int? createdAt,
  }) => Stroke(
    id: id,
    tool: stroke.tool,
    color: color ?? stroke.color,
    width: stroke.width * scale,
    points: [
      for (final p in stroke.points)
        () {
          final q = apply(p.offset);
          return InkPoint(q.dx, q.dy, p.pressure);
        }(),
    ],
    createdAt: createdAt ?? stroke.createdAt,
    pressureSensitive: stroke.pressureSensitive,
    style: stroke.style,
    followsPen: stroke.followsPen,
    dash: stroke.dash,
    // Recolored, the fill takes the new color at its own strength.
    fill: switch ((stroke.fill, color)) {
      (final fill?, final color?) => Color(
        color,
      ).withValues(alpha: Color(fill).a).toARGB32(),
      (final fill, _) => fill,
    },
  );

  ElementFrame applyToFrame(ElementFrame frame) => frame.copyWith(
    center: apply(frame.center),
    width: frame.width * scale,
    height: frame.height * scale,
    rotation: _wrap(frame.rotation + rotation),
  );

  static double _wrap(double a) => math.atan2(math.sin(a), math.cos(a));
}

/// The bounds of [strokes] and [elements] together, in page units.
Rect selectionBounds(List<Stroke> strokes, List<PageElement> elements) {
  Rect? r;
  for (final s in strokes) {
    final b = s.bounds.inflate(s.width / 2);
    r = r == null ? b : r.expandToInclude(b);
  }
  for (final e in elements) {
    final f = e.frame;
    final corners = [
      for (final (x, y) in [(-1, -1), (1, -1), (1, 1), (-1, 1)])
        f.toPage(Offset(x * f.width / 2, y * f.height / 2)),
    ];
    for (final c in corners) {
      final b = Rect.fromCenter(center: c, width: 0, height: 0);
      r = r == null ? b : r.expandToInclude(b);
    }
  }
  return r ?? Rect.zero;
}

/// Copied or cut handwriting and items, ready to paste on any page.
@immutable
class InkClip {
  const InkClip({required this.strokes, required this.elements});

  final List<Stroke> strokes;
  final List<PageElement> elements;

  Rect get bounds => selectionBounds(strokes, elements);
  bool get isEmpty => strokes.isEmpty && elements.isEmpty;
}

class InkClipboard extends Notifier<InkClip?> {
  @override
  InkClip? build() => null;

  void copy(InkClip clip) => state = clip.isEmpty ? null : clip;
}

/// What was last copied with the lasso. Shared by every page, so it can be
/// pasted into another page or notebook.
final inkClipboardProvider = NotifierProvider<InkClipboard, InkClip?>(
  InkClipboard.new,
);

/// Asks a page's canvas to paste the clipboard in the middle of its view.
class PasteRequestController extends Notifier<int> {
  PasteRequestController(this.pageId);

  final String pageId;

  @override
  int build() => 0;

  void request() => state++;
}

final pasteRequestProvider = NotifierProvider.autoDispose
    .family<PasteRequestController, int, String>(PasteRequestController.new);

/// The loop being drawn with the lasso: a dashed line.
class LassoPathPainter extends CustomPainter {
  LassoPathPainter(this.points, this.color, this.unit) : super(repaint: points);

  final ValueNotifier<List<Offset>> points;
  final Color color;

  /// One screen pixel in page units.
  final double unit;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = points.value;
    if (pts.length < 2) return;
    final path = Path()..addPolygon(pts, false);
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill,
    );
    _drawDashed(canvas, pts, color, unit);
  }

  @override
  bool shouldRepaint(LassoPathPainter old) =>
      old.points != points || old.color != color || old.unit != unit;
}

void _drawDashed(Canvas canvas, List<Offset> pts, Color color, double unit) {
  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5 * unit
    ..strokeCap = StrokeCap.round;
  final dash = 6 * unit, gap = 5 * unit;
  var on = true, left = dash;
  for (var i = 0; i + 1 < pts.length; i++) {
    var a = pts[i];
    final b = pts[i + 1];
    var seg = (b - a).distance;
    while (seg > 0) {
      final step = math.min(seg, left);
      final next = a + (b - a) / (b - a).distance * step;
      if (on) canvas.drawLine(a, next, paint);
      a = next;
      seg -= step;
      left -= step;
      if (left <= 0) {
        on = !on;
        left = on ? dash : gap;
      }
    }
  }
}

/// Lassoed strokes, drawn moved, scaled and rotated while they're dragged,
/// with a dashed box and handles: resize (bottom right) and rotate (above).
class LassoSelectionPainter extends CustomPainter {
  LassoSelectionPainter({
    required this.paths,
    required this.box,
    required this.transform,
    required this.color,
    required this.unit,
  });

  /// The selected strokes' outlines and paints.
  final List<(Path, Paint)> paths;

  /// The selection's bounds before [transform].
  final Rect box;
  final LassoTransform transform;
  final Color color;

  /// One screen pixel in page units.
  final double unit;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    transform.applyToCanvas(canvas);
    for (final (path, paint) in paths) {
      canvas.drawPath(path, paint);
    }
    canvas.restore();

    final corners = [
      box.topLeft,
      box.topRight,
      box.bottomRight,
      box.bottomLeft,
      box.topLeft,
    ].map(transform.apply).toList();
    _drawDashed(canvas, corners, color, unit);

    final fill = Paint()..color = color;
    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 * unit
      ..strokeCap = StrokeCap.round;
    final r = handleRadius * unit;

    final resize = transform.apply(box.bottomRight);
    canvas
      ..drawCircle(resize, r, fill)
      ..drawLine(
        resize - Offset(r * 0.4, r * 0.4),
        resize + Offset(r * 0.4, r * 0.4),
        white,
      );

    final top = transform.apply(box.topCenter);
    final rotate = rotateHandle(box, transform, unit);
    canvas
      ..drawLine(
        top,
        rotate,
        Paint()
          ..color = color
          ..strokeWidth = 1.5 * unit,
      )
      ..drawCircle(rotate, r, fill)
      ..drawArc(
        Rect.fromCircle(center: rotate, radius: r / 2),
        -math.pi / 2,
        math.pi * 1.5,
        false,
        white,
      );
  }

  /// Handle radius in screen pixels.
  static const handleRadius = 14.0;

  /// Where the rotate handle sits: 40 screen pixels above the box's top.
  static Offset rotateHandle(Rect box, LassoTransform t, double unit) {
    final up = Offset(0, -40 * unit / t.scale);
    return t.apply(box.topCenter + up);
  }

  @override
  bool shouldRepaint(LassoSelectionPainter old) =>
      !identical(old.paths, paths) ||
      old.box != box ||
      old.transform != transform ||
      old.color != color ||
      old.unit != unit;
}

/// What can be done with a lasso selection.
enum LassoAction { color, cut, copy, duplicate, link, delete }

/// The bar over a lasso selection: color, cut, copy, duplicate, link,
/// delete.
class LassoActionBar extends StatelessWidget {
  const LassoActionBar({
    required this.colors,
    required this.canRecolor,
    required this.onAction,
    required this.onColor,
    super.key,
  });

  final List<Color> colors;

  /// Whether any handwriting is selected (only handwriting takes a color).
  final bool canRecolor;
  final ValueChanged<LassoAction> onAction;
  final ValueChanged<Color> onColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget button(LassoAction action, IconData icon, String label) =>
        IconButton(
          tooltip: label,
          icon: Icon(icon, size: 20),
          color: action == LassoAction.delete
              ? scheme.error
              : scheme.onInverseSurface,
          onPressed: () => onAction(action),
        );
    return Material(
      color: scheme.inverseSurface,
      elevation: 4,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canRecolor)
              PopupMenuButton<Color>(
                tooltip: 'Color',
                icon: Icon(
                  Icons.palette_outlined,
                  size: 20,
                  color: scheme.onInverseSurface,
                ),
                onSelected: onColor,
                itemBuilder: (context) => [
                  PopupMenuItem(
                    enabled: false,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in colors)
                          InkWell(
                            key: ValueKey('lasso-color-${c.toARGB32()}'),
                            customBorder: const CircleBorder(),
                            onTap: () => Navigator.of(context).pop(c),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(color: scheme.outline),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            button(LassoAction.cut, Icons.content_cut, 'Cut'),
            button(LassoAction.copy, Icons.content_copy, 'Copy'),
            button(
              LassoAction.duplicate,
              Icons.library_add_outlined,
              'Duplicate',
            ),
            button(LassoAction.link, Icons.link, 'Link to a page'),
            button(LassoAction.delete, Icons.delete_outline, 'Delete'),
          ],
        ),
      ),
    );
  }
}
