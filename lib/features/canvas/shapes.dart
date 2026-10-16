import 'dart:math' as math;
import 'dart:ui';

/// What a hand-drawn stroke was recognized as.
enum ShapeKind { line, circle, ellipse, triangle, rectangle, polygon }

/// A recognized shape: what it is and its outline, in page units. Closed
/// shapes end where they start.
class Shape {
  const Shape(this.kind, this.outline);

  final ShapeKind kind;
  final List<Offset> outline;
}

/// Recognizes a hand-drawn stroke as a straight line, a circle or ellipse,
/// or a triangle, rectangle or other polygon. Returns null when it doesn't
/// look like any of them (a scribble or a word).
Shape? recognizeShape(List<Offset> points) {
  if (points.length < 4) return null;
  final length = _pathLength(points);
  final box = _bounds(points);
  final size = math.max(box.width, box.height);
  if (length < 20 || size < 12) return null;

  final gap = (points.last - points.first).distance;
  final closed = gap < math.max(0.22 * length, 0) && gap < 0.4 * size;
  if (!closed) {
    // Straight enough to be a line.
    if (gap / length < 0.92) return null;
    return Shape(ShapeKind.line, [
      points.first,
      snapLine(points.first, points.last),
    ]);
  }

  // Closed: compare an ellipse fit with a polygon fit.
  final ring = [...points, points.first];
  final ellipseError = _ellipseError(points, box);
  final corners = _corners(ring, 0.08 * size);
  Shape? polygon;
  double polygonError = double.infinity;
  if (corners.length >= 3 && corners.length <= 8) {
    polygonError = _polygonError(points, corners) / size;
    polygon = _polygonShape(corners, box);
  }
  // Hand-drawn ellipses stray about 2% from a true one; polygons, 9% or
  // more (their corners stick out).
  if (ellipseError < 0.05) return _ellipseShape(box);
  if (polygon != null && polygonError < 0.035) return polygon;
  return null;
}

/// [end] moved so the line from [start] is level, upright or diagonal when
/// it's within 6 degrees of one.
Offset snapLine(Offset start, Offset end) {
  final d = end - start;
  final angle = math.atan2(d.dy, d.dx);
  const step = math.pi / 4;
  final nearest = (angle / step).roundToDouble() * step;
  if ((angle - nearest).abs() > 6 * math.pi / 180) return end;
  return start + Offset(math.cos(nearest), math.sin(nearest)) * d.distance;
}

double _pathLength(List<Offset> pts) {
  var sum = 0.0;
  for (var i = 0; i + 1 < pts.length; i++) {
    sum += (pts[i + 1] - pts[i]).distance;
  }
  return sum;
}

Rect _bounds(List<Offset> pts) {
  var l = pts.first.dx, r = l, t = pts.first.dy, b = t;
  for (final p in pts) {
    l = math.min(l, p.dx);
    r = math.max(r, p.dx);
    t = math.min(t, p.dy);
    b = math.max(b, p.dy);
  }
  return Rect.fromLTRB(l, t, r, b);
}

/// How far points stray from the ellipse filling [box], as a share of its
/// size (0 is perfect).
double _ellipseError(List<Offset> pts, Rect box) {
  final rx = box.width / 2, ry = box.height / 2;
  if (rx < 1 || ry < 1) return double.infinity;
  final c = box.center;
  var sum = 0.0;
  for (final p in pts) {
    final n = Offset((p.dx - c.dx) / rx, (p.dy - c.dy) / ry);
    sum += (n.distance - 1).abs();
  }
  // Also ask that the stroke goes all the way round.
  var turned = 0.0;
  for (var i = 0; i + 1 < pts.length; i++) {
    final a = math.atan2(pts[i].dy - c.dy, pts[i].dx - c.dx);
    final b = math.atan2(pts[i + 1].dy - c.dy, pts[i + 1].dx - c.dx);
    var d = b - a;
    if (d > math.pi) d -= 2 * math.pi;
    if (d < -math.pi) d += 2 * math.pi;
    turned += d;
  }
  if (turned.abs() < 1.6 * math.pi) return double.infinity;
  return sum / pts.length;
}

/// Corners of a closed [ring] (first point repeated at the end), found by
/// simplifying it (Ramer-Douglas-Peucker) and merging close points.
List<Offset> _corners(List<Offset> ring, double epsilon) {
  // Start from the point furthest from the start, so the start (rarely a
  // real corner) doesn't have to be kept.
  var far = 0;
  for (var i = 0; i < ring.length; i++) {
    if ((ring[i] - ring[0]).distance > (ring[far] - ring[0]).distance) far = i;
  }
  final a = _simplify(ring.sublist(0, far + 1), epsilon);
  final b = _simplify(ring.sublist(far), epsilon);
  var pts = [...a, ...b.skip(1)];
  pts.removeLast(); // the ring's repeated start
  // A corner the path doesn't turn at (it lies on the line between its
  // neighbours) isn't one; the start point usually isn't.
  var removed = true;
  while (removed && pts.length > 3) {
    removed = false;
    for (var k = 0; k < pts.length; k++) {
      final prev = pts[(k - 1 + pts.length) % pts.length];
      final next = pts[(k + 1) % pts.length];
      if (_distanceToSegment(pts[k], prev, next) < epsilon) {
        pts = [...pts]..removeAt(k);
        removed = true;
        break;
      }
    }
  }
  // Merge corners that are very close together.
  final merged = <Offset>[];
  for (final p in pts) {
    if (merged.isEmpty || (p - merged.last).distance > epsilon) merged.add(p);
  }
  if (merged.length > 2 && (merged.first - merged.last).distance <= epsilon) {
    merged.removeLast();
  }
  return merged;
}

List<Offset> _simplify(List<Offset> pts, double epsilon) {
  if (pts.length < 3) return pts;
  var index = 0;
  var maxDistance = 0.0;
  for (var i = 1; i < pts.length - 1; i++) {
    final d = _distanceToSegment(pts[i], pts.first, pts.last);
    if (d > maxDistance) {
      index = i;
      maxDistance = d;
    }
  }
  if (maxDistance <= epsilon) return [pts.first, pts.last];
  final left = _simplify(pts.sublist(0, index + 1), epsilon);
  final right = _simplify(pts.sublist(index), epsilon);
  return [...left, ...right.skip(1)];
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.distanceSquared;
  if (len2 == 0) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// The average distance from [pts] to the closed polygon [corners].
double _polygonError(List<Offset> pts, List<Offset> corners) {
  var sum = 0.0;
  for (final p in pts) {
    var best = double.infinity;
    for (var i = 0; i < corners.length; i++) {
      final d = _distanceToSegment(
        p,
        corners[i],
        corners[(i + 1) % corners.length],
      );
      best = math.min(best, d);
    }
    sum += best;
  }
  return sum / pts.length;
}

Shape _polygonShape(List<Offset> corners, Rect box) {
  if (corners.length == 3) {
    return Shape(ShapeKind.triangle, [...corners, corners.first]);
  }
  if (corners.length == 4 && _isLevelRectangle(corners, box)) {
    final r = box;
    return Shape(ShapeKind.rectangle, [
      r.topLeft,
      r.topRight,
      r.bottomRight,
      r.bottomLeft,
      r.topLeft,
    ]);
  }
  return Shape(corners.length == 4 ? ShapeKind.rectangle : ShapeKind.polygon, [
    ...corners,
    corners.first,
  ]);
}

/// Whether four corners sit near the corners of their bounding box: a
/// rectangle drawn level, which is squared up to the box.
bool _isLevelRectangle(List<Offset> corners, Rect box) {
  final tolerance = 0.18 * math.max(box.width, box.height);
  for (final target in [
    box.topLeft,
    box.topRight,
    box.bottomRight,
    box.bottomLeft,
  ]) {
    if (!corners.any((c) => (c - target).distance <= tolerance)) return false;
  }
  return true;
}

Shape _ellipseShape(Rect box) {
  var rx = box.width / 2, ry = box.height / 2;
  var kind = ShapeKind.ellipse;
  // Nearly round: make it a circle.
  if ((rx - ry).abs() / math.max(rx, ry) < 0.12) {
    rx = ry = (rx + ry) / 2;
    kind = ShapeKind.circle;
  }
  final c = box.center;
  const n = 72;
  return Shape(kind, [
    for (var i = 0; i <= n; i++)
      c +
          Offset(
            rx * math.cos(-math.pi / 2 + 2 * math.pi * i / n),
            ry * math.sin(-math.pi / 2 + 2 * math.pi * i / n),
          ),
  ]);
}

/// [outline] with points every [step] page units along each side, so the
/// pen draws it evenly.
List<Offset> densify(List<Offset> outline, {double step = 6}) {
  final out = <Offset>[];
  for (var i = 0; i + 1 < outline.length; i++) {
    final a = outline[i], b = outline[i + 1];
    final n = math.max(1, ((b - a).distance / step).ceil());
    for (var k = 0; k < n; k++) {
      out.add(Offset.lerp(a, b, k / n)!);
    }
  }
  out.add(outline.last);
  return out;
}

/// Whether [points] go hard back and forth, like scribbling something out:
/// at least five passes along one axis, packed into their own width.
/// Handwriting turns back too (an "m" goes up and down), so this alone
/// doesn't erase anything; see [scribbledOut].
bool isScribble(List<Offset> points) {
  if (points.length < 12) return false;
  final box = _bounds(points);
  if (box.longestSide < 20) return false;
  final length = _pathLength(points);
  int turns(double Function(Offset) axis, double extent) {
    // A turn counts once the pen has come back a third of the way, and
    // more than a wobble.
    final hysteresis = math.max(extent / 3, 8.0);
    var count = 0, direction = 0;
    var extreme = axis(points.first);
    for (final p in points.skip(1)) {
      final v = axis(p);
      if (direction >= 0 && v > extreme || direction <= 0 && v < extreme) {
        extreme = v;
        if (direction == 0 && (v - axis(points.first)).abs() > hysteresis) {
          direction = v > axis(points.first) ? 1 : -1;
        }
        continue;
      }
      if ((v - extreme).abs() > hysteresis) {
        count++;
        direction = v > extreme ? 1 : -1;
        extreme = v;
      }
    }
    return count;
  }

  for (final (axis, extent) in [
    ((Offset p) => p.dx, box.width),
    ((Offset p) => p.dy, box.height),
  ]) {
    if (extent < 20) continue;
    if (turns(axis, extent) >= 4 && length > 4 * extent) return true;
  }
  return false;
}

/// The strokes a scribble crosses out: those it runs over that lie mostly
/// within it. Empty when [scribble] isn't one or covers nothing, so it's
/// ink after all.
List<String> scribbledOut(
  List<Offset> scribble,
  double width,
  Iterable<({String id, Rect bounds, bool Function(Offset, double) hits})>
  strokes,
) {
  if (!isScribble(scribble)) return const [];
  final area = _bounds(scribble).inflate(width);
  return [
    for (final s in strokes)
      if (_shareInside(s.bounds, area) > 0.6 &&
          scribble.any((p) => s.hits(p, width / 2)))
        s.id,
  ];
}

/// How much of [r] lies inside [area].
double _shareInside(Rect r, Rect area) {
  final inside = r.intersect(area);
  if (inside.width <= 0 || inside.height <= 0) {
    // A level or upright line has no area: compare lengths.
    if (r.width == 0 || r.height == 0) {
      return area.overlaps(r.inflate(0.5)) ? 1 : 0;
    }
    return 0;
  }
  return inside.width * inside.height / (r.width * r.height);
}
