import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

import 'domain/stroke.dart';
import 'ink_stats.dart';

/// Turns strokes into filled outlines with perfect_freehand. Outlines are
/// cached per stroke, since saved strokes never change.
abstract final class StrokeRenderer {
  static final _cache = Expando<Path>('strokePath');

  static Path pathFor(Stroke stroke) =>
      _cache[stroke] ??= buildPath(stroke, complete: true);

  /// [complete] is false while the stroke is being drawn. A stroke that
  /// [Stroke.followsPen] then looks just as it will once saved, ending
  /// right at the pen, so nothing moves when the pen lifts. Only a brush's
  /// tapered end waits for the lift.
  static Path buildPath(Stroke stroke, {required bool complete}) {
    if (stroke.dash != LineDash.solid && stroke.points.length >= 2) {
      return _dashedPath(stroke);
    }
    // Written points, filled in along a curve where they're far apart (a
    // quick stroke between samples), with real pressure as ink weight.
    final ink = smoothInkPoints(
      stroke.pressureSensitive ? inkPressures(stroke.points) : stroke.points,
      spacing: math.max(stroke.width * 0.5, 2.0),
    );
    final points = [
      for (final p in ink)
        PointVector(p.x, p.y, stroke.pressureSensitive ? p.pressure : null),
    ];
    final highlighter = stroke.tool == InkTool.highlighter;
    final real = stroke.pressureSensitive;
    final style = highlighter ? null : stroke.style;
    final outline = getStroke(
      points,
      options: StrokeOptions(
        size: style == PenStyle.pencil ? stroke.width * 0.85 : stroke.width,
        // Real pressure gets the full effect. Simulated pressure (fingers,
        // mouse) thins lines a lot on fast moves, so keep it subtle.
        thinning: switch (style) {
          null => 0,
          PenStyle.ballpoint => real ? 0.15 : 0.05,
          PenStyle.fountain => real ? 0.5 : 0.25,
          PenStyle.brush => real ? 0.75 : 0.55,
          PenStyle.pencil => real ? 0.35 : 0.1,
        },
        smoothing: 0.6,
        // Streamline evens out shaky input but trails behind it. A stylus
        // is already steady, so its ink keeps up with the tip.
        streamline: switch ((highlighter, stroke.followsPen)) {
          (true, false) => 0.6,
          (true, true) => 0.3,
          (false, false) => 0.4,
          (false, true) => 0.1,
        },
        simulatePressure: !highlighter && !real,
        start: style == PenStyle.brush
            ? StrokeEndOptions.start(
                taperEnabled: true,
                customTaper: stroke.width * 3,
              )
            : StrokeEndOptions.start(),
        end: style == PenStyle.brush && complete
            ? StrokeEndOptions.end(
                taperEnabled: true,
                customTaper: stroke.width * 3,
              )
            : StrokeEndOptions.end(),
        isComplete: complete || stroke.followsPen,
      ),
    );
    if (outline.length < 3) {
      // A tap: draw a dot.
      final at = stroke.points.isEmpty
          ? Offset.zero
          : stroke.points.first.offset;
      return Path()
        ..addOval(Rect.fromCircle(center: at, radius: stroke.width / 2));
    }
    return curvedOutline(outline);
  }

  /// [outline] as a closed path of curves: each point pulls the curve
  /// toward it on its way between the midpoints either side, so the edge
  /// of the ink is smooth rather than a chain of straight cuts.
  static Path curvedOutline(List<Offset> outline) {
    final n = outline.length;
    Offset mid(int i) => (outline[i % n] + outline[(i + 1) % n]) / 2;
    final start = mid(n - 1);
    final path = Path()..moveTo(start.dx, start.dy);
    for (var i = 0; i < n; i++) {
      final control = outline[i], end = mid(i);
      path.quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
    }
    return path..close();
  }

  static final _fillCache = Expando<Path>('strokeFill');

  /// The area a closed shape fills, or null when it isn't filled.
  static Path? fillPathFor(Stroke stroke) {
    if (stroke.fill == null || stroke.points.length < 3) return null;
    return _fillCache[stroke] ??= Path()
      ..addPolygon([for (final p in stroke.points) p.offset], true);
  }

  /// Draws [stroke]'s fill, if it has one, then its line.
  static void paint(Canvas canvas, Stroke stroke, {Path? path}) {
    if (fillPathFor(stroke) case final fill?) {
      canvas.drawPath(fill, Paint()..color = Color(stroke.fill!));
    }
    canvas.drawPath(path ?? pathFor(stroke), paintFor(stroke));
  }

  /// An even line broken into dashes, or a row of dots, along the stroke.
  static Path _dashedPath(Stroke stroke) {
    final w = stroke.width;
    final dotted = stroke.dash == LineDash.dotted;
    final dash = dotted ? 0.0 : w * 3;
    final gap = w * 2.2;
    final path = Path();
    final points = [for (final p in stroke.points) p.offset];
    var run = <Offset>[points.first];
    var drawing = true;
    // Dots start with one at the start; dashes start drawing.
    var left = dotted ? gap : dash;
    if (dotted) {
      path.addOval(Rect.fromCircle(center: points.first, radius: w / 2));
    }

    void flush() {
      if (run.length < 2) return;
      final outline = getStroke(
        [for (final p in run) PointVector(p.dx, p.dy)],
        options: StrokeOptions(
          size: w,
          thinning: 0,
          smoothing: 0.3,
          streamline: 0,
          simulatePressure: false,
          isComplete: true,
        ),
      );
      if (outline.length >= 3) path.addPolygon(outline, true);
    }

    for (var i = 0; i + 1 < points.length; i++) {
      var a = points[i];
      final b = points[i + 1];
      var segment = (b - a).distance;
      while (segment > 0) {
        final step = math.min(segment, left);
        final at = Offset.lerp(a, b, step / (b - a).distance)!;
        if (drawing && !dotted) run.add(at);
        segment -= step;
        left -= step;
        a = at;
        if (left <= 0) {
          if (dotted) {
            path.addOval(Rect.fromCircle(center: at, radius: w / 2));
            left = gap;
          } else if (drawing) {
            flush();
            drawing = false;
            left = gap;
          } else {
            drawing = true;
            run = [at];
            left = dash;
          }
        }
        if (step == 0) break;
      }
    }
    if (drawing && !dotted) flush();
    return path;
  }

  static Paint paintFor(Stroke stroke) {
    final paint = Paint()
      ..color = Color(stroke.color)
      ..isAntiAlias = true;
    if (stroke.tool == InkTool.pen && stroke.style == PenStyle.pencil) {
      // Graphite: the ink color, let through a grainy mask.
      final grain = _grain;
      if (grain != null) {
        paint
          ..shader = grain
          ..colorFilter = ColorFilter.mode(
            Color(stroke.color).withValues(alpha: 0.9),
            BlendMode.srcIn,
          );
      }
    }
    return paint;
  }

  /// A tile of speckled alpha for pencil strokes, made once.
  static final ui.Shader? _grain = () {
    try {
      const size = 64;
      final random = math.Random(7);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 64, 64),
        Paint()..color = const Color(0x99000000),
      );
      final dot = Paint();
      for (var i = 0; i < 1400; i++) {
        dot.color = Color.fromARGB(80 + random.nextInt(176), 0, 0, 0);
        canvas.drawRect(
          Rect.fromLTWH(
            random.nextDouble() * size,
            random.nextDouble() * size,
            1.2,
            1.2,
          ),
          dot,
        );
      }
      final image = recorder.endRecording().toImageSync(size, size);
      return ImageShader(
        image,
        TileMode.repeated,
        TileMode.repeated,
        // Page units: a grain fine enough to read as pencil.
        (Matrix4.identity()..scaleByDouble(0.6, 0.6, 1, 1)).storage,
      );
    } catch (_) {
      return null; // No GPU (tests): plain ink.
    }
  }();
}

/// Stylus pressure (0–1 of the Pencil's full force) as ink weight:
/// ordinary writing presses lightly, so it's lifted to the middle of the
/// range, firm pressing reaches full width, and light writing still shows.
double inkWeight(double pressure) =>
    math.pow((pressure / 0.45).clamp(0.0, 1.0), 0.65).toDouble();

/// [points] with pressure as [inkWeight], evened out between neighbours
/// so the width doesn't flicker, and the first point taking the second's
/// (a stroke's first touch barely presses).
List<InkPoint> inkPressures(List<InkPoint> points) {
  if (points.isEmpty) return points;
  final w = [for (final p in points) inkWeight(p.pressure)];
  if (w.length > 1) w[0] = w[1];
  // Twice over neighbours, a quarter each side.
  for (var pass = 0; pass < 2; pass++) {
    final prev = [...w];
    for (var i = 1; i + 1 < w.length; i++) {
      w[i] = prev[i - 1] * 0.25 + prev[i] * 0.5 + prev[i + 1] * 0.25;
    }
  }
  return [
    for (var i = 0; i < points.length; i++)
      InkPoint(points[i].x, points[i].y, w[i]),
  ];
}

/// [points] with more put in wherever two are over [spacing] apart, along
/// a centripetal Catmull-Rom curve through them: it passes through every
/// point, bends smoothly, and doesn't overshoot or loop. Pressure goes
/// evenly from one point to the next.
List<InkPoint> smoothInkPoints(
  List<InkPoint> points, {
  required double spacing,
}) {
  if (points.length < 3) return points;
  final out = <InkPoint>[points.first];
  for (var i = 0; i + 1 < points.length; i++) {
    final p1 = points[i], p2 = points[i + 1];
    final gap = (p2.offset - p1.offset).distance;
    final steps = (gap / spacing).ceil();
    if (steps > 1) {
      final p0 = i == 0 ? p1 : points[i - 1];
      final p3 = i + 2 < points.length ? points[i + 2] : p2;
      for (var k = 1; k < steps; k++) {
        final t = k / steps;
        final at = _centripetal(p0.offset, p1.offset, p2.offset, p3.offset, t);
        out.add(
          InkPoint(at.dx, at.dy, p1.pressure + (p2.pressure - p1.pressure) * t),
        );
      }
    }
    out.add(p2);
  }
  return out;
}

/// The point [t] (0–1) of the way from [p1] to [p2] on the centripetal
/// Catmull-Rom curve through [p0], [p1], [p2], [p3].
Offset _centripetal(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
  double knot(Offset a, Offset b) =>
      math.max(math.sqrt((b - a).distance), 1e-4);
  const t0 = 0.0;
  final t1 = t0 + knot(p0, p1);
  final t2 = t1 + knot(p1, p2);
  final t3 = t2 + knot(p2, p3);
  final u = t1 + (t2 - t1) * t;
  Offset lerp(Offset a, Offset b, double ta, double tb) =>
      a * ((tb - u) / (tb - ta)) + b * ((u - ta) / (tb - ta));
  final a1 = lerp(p0, p1, t0, t1);
  final a2 = lerp(p1, p2, t1, t2);
  final a3 = lerp(p2, p3, t2, t3);
  final b1 = lerp(a1, a2, t0, t2);
  final b2 = lerp(a2, a3, t1, t3);
  return lerp(b1, b2, t1, t2);
}

/// Saved strokes. Kept in its own layer so drawing a new stroke doesn't
/// repaint the whole page.
class StrokesPainter extends CustomPainter {
  StrokesPainter(this.strokes, {this.faded = const {}});

  final List<Stroke> strokes;

  /// Strokes drawn faint: written later in a recording than it's played.
  final Set<String> faded;

  @override
  void paint(Canvas canvas, Size size) {
    // Highlighters go under the ink, as a highlighter on paper sits under
    // what it marks, so a highlight never dulls the writing.
    List<Stroke> ordered(bool Function(Stroke) which) => [
      for (final s in strokes)
        if (s.tool == InkTool.highlighter && which(s)) s,
      for (final s in strokes)
        if (s.tool != InkTool.highlighter && which(s)) s,
    ];
    for (final stroke in ordered((s) => !faded.contains(s.id))) {
      StrokeRenderer.paint(canvas, stroke);
    }
    if (faded.isEmpty) return;
    // Faint, together in one layer.
    canvas.saveLayer(null, Paint()..color = const Color(0x33000000));
    for (final stroke in ordered((s) => faded.contains(s.id))) {
      StrokeRenderer.paint(canvas, stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(StrokesPainter old) =>
      !identical(old.strokes, strokes) || !setEquals(old.faded, faded);
}

/// The stroke being drawn right now, plus where the pen is [predicted] to
/// be. Repaints on every pointer move without rebuilding any widgets.
class LiveStrokePainter extends CustomPainter {
  LiveStrokePainter(this.live, this.predicted)
    : super(repaint: Listenable.merge([live, predicted]));

  final ValueNotifier<Stroke?> live;
  final ValueNotifier<List<InkPoint>> predicted;

  @override
  void paint(Canvas canvas, Size size) {
    var stroke = live.value;
    if (stroke == null || stroke.points.isEmpty) return;
    final timer = Stopwatch()..start();
    if (predicted.value.isNotEmpty) {
      stroke = stroke.withPoints([...stroke.points, ...predicted.value]);
    }
    StrokeRenderer.paint(
      canvas,
      stroke,
      path: StrokeRenderer.buildPath(stroke, complete: false),
    );
    InkStats.instance.drew(timer.elapsedMicroseconds / 1000);
  }

  @override
  bool shouldRepaint(LiveStrokePainter old) =>
      old.live != live || old.predicted != predicted;
}
