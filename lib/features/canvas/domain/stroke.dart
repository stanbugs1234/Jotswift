import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// The size of every page, in page units. Ink is stored in page units so it
/// looks the same on every screen size and zoom level.
const pageSize = Size(1404, 1872);

enum InkTool { pen, highlighter }

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
