import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// The size of a Letter portrait page (the default), in page units. Ink is
/// stored in page units so it looks the same on every screen size and zoom
/// level. Other notebooks use their own paper size (see `PaperSize`).
const pageSize = Size(1404, 1872);

enum InkTool { pen, highlighter }

/// How a pen stroke looks. Strokes saved before pen styles existed are
/// [fountain], which is how they were drawn.
enum PenStyle {
  /// Even width, like a ballpoint or gel pen.
  ballpoint,

  /// Thick and thin with pressure.
  fountain,

  /// Soft and tapered, very responsive to pressure.
  brush,

  /// Grainy graphite.
  pencil,
}

@immutable
class InkPoint {
  const InkPoint(this.x, this.y, [this.pressure = 0.5]);

  final double x;
  final double y;

  /// 0–1. Only meaningful when the stroke is [Stroke.pressureSensitive].
  final double pressure;

  Offset get offset => Offset(x, y);
}

/// One pen or highlighter stroke. Strokes are never edited after they are
/// saved; erasing sets [deleted] (a tombstone), so two devices writing to
/// the same page can't conflict.
@immutable
class Stroke {
  Stroke({
    required this.id,
    required this.tool,
    required this.color,
    required this.width,
    required this.points,
    required this.createdAt,
    this.pressureSensitive = false,
    this.deleted = false,
    this.style = PenStyle.fountain,
  });

  factory Stroke.fromMap(String id, Map<String, dynamic> map) {
    final packed = (map['points'] as List<dynamic>).cast<num>();
    final points = <InkPoint>[
      for (var i = 0; i + 2 < packed.length; i += 3)
        InkPoint(
          packed[i].toDouble(),
          packed[i + 1].toDouble(),
          packed[i + 2].toDouble(),
        ),
    ];
    return Stroke(
      id: id,
      tool: InkTool.values.asNameMap()[map['tool']] ?? InkTool.pen,
      color: map['color'] as int,
      width: (map['width'] as num).toDouble(),
      points: points,
      createdAt: map['createdAt'] as int? ?? 0,
      pressureSensitive: map['pressure'] as bool? ?? false,
      deleted: map['deleted'] as bool? ?? false,
      style: PenStyle.values.asNameMap()[map['style']] ?? PenStyle.fountain,
    );
  }

  final String id;
  final InkTool tool;

  /// ARGB.
  final int color;

  /// Nominal width in page units.
  final double width;
  final List<InkPoint> points;
  final int createdAt;

  /// True when drawn with a stylus that reports pressure.
  final bool pressureSensitive;
  final bool deleted;

  /// How the pen draws (only pen strokes; highlighters ignore it).
  final PenStyle style;

  /// Points are packed as a flat [x, y, pressure, ...] list, rounded to keep
  /// documents small.
  Map<String, dynamic> toMap() => {
    'tool': tool.name,
    'color': color,
    'width': width,
    'points': [
      for (final p in points) ...[
        _round(p.x, 10),
        _round(p.y, 10),
        _round(p.pressure, 100),
      ],
    ],
    'createdAt': createdAt,
    'pressure': pressureSensitive,
    'deleted': deleted,
    if (style != PenStyle.fountain) 'style': style.name,
  };

  static double _round(double v, int scale) => (v * scale).round() / scale;

  Stroke copyWith({bool? deleted}) => Stroke(
    id: id,
    tool: tool,
    color: color,
    width: width,
    points: points,
    createdAt: createdAt,
    pressureSensitive: pressureSensitive,
    deleted: deleted ?? this.deleted,
    style: style,
  );

  late final Rect bounds = _computeBounds();

  Rect _computeBounds() {
    if (points.isEmpty) return Rect.zero;
    var left = points.first.x, right = left;
    var top = points.first.y, bottom = top;
    for (final p in points) {
      left = math.min(left, p.x);
      right = math.max(right, p.x);
      top = math.min(top, p.y);
      bottom = math.max(bottom, p.y);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// Whether a circle at [point] with [radius] touches this stroke.
  bool hitTest(Offset point, double radius) {
    final reach = radius + width / 2;
    if (!bounds.inflate(reach).contains(point)) return false;
    if (points.length == 1) {
      return (points.first.offset - point).distance <= reach;
    }
    for (var i = 0; i + 1 < points.length; i++) {
      if (_distanceToSegment(point, points[i].offset, points[i + 1].offset) <=
          reach) {
        return true;
      }
    }
    return false;
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lengthSquared = ab.distanceSquared;
    if (lengthSquared == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / lengthSquared).clamp(
      0.0,
      1.0,
    );
    return (p - (a + ab * t)).distance;
  }
}

/// What's left of [stroke] after erasing a circle at [center] with
/// [radius]: the pieces either side, as new strokes, or null when the
/// circle doesn't touch it. Each piece keeps the stroke's look and its
/// place in the drawing order.
List<Stroke>? eraseFromStroke(
  Stroke stroke,
  Offset center,
  double radius,
  String Function() newId,
) {
  final reach = radius + stroke.width / 2;
  if (!stroke.bounds.inflate(reach).contains(center)) return null;
  // Fill in long gaps between points so a cut lands where the eraser is.
  final step = math.max(reach / 2, 0.5);
  final points = <InkPoint>[];
  for (var i = 0; i < stroke.points.length; i++) {
    final a = stroke.points[i];
    points.add(a);
    if (i + 1 == stroke.points.length) break;
    final b = stroke.points[i + 1];
    final n = ((b.offset - a.offset).distance / step).ceil();
    for (var k = 1; k < n; k++) {
      final t = k / n;
      points.add(
        InkPoint(
          a.x + (b.x - a.x) * t,
          a.y + (b.y - a.y) * t,
          a.pressure + (b.pressure - a.pressure) * t,
        ),
      );
    }
  }
  final kept = [for (final p in points) (p.offset - center).distance > reach];
  if (!kept.contains(false)) return null;
  final pieces = <Stroke>[];
  var run = <InkPoint>[];
  void flush() {
    if (run.length >= 2) {
      pieces.add(
        Stroke(
          id: newId(),
          tool: stroke.tool,
          color: stroke.color,
          width: stroke.width,
          points: run,
          createdAt: stroke.createdAt,
          pressureSensitive: stroke.pressureSensitive,
          style: stroke.style,
        ),
      );
    }
    run = [];
  }

  for (var i = 0; i < points.length; i++) {
    if (kept[i]) {
      run.add(points[i]);
    } else {
      flush();
    }
  }
  flush();
  return pieces;
}
