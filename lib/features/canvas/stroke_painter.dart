import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

import 'domain/stroke.dart';

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
    final points = [
      for (final p in stroke.points)
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
          PenStyle.fountain => real ? 0.6 : 0.25,
          PenStyle.brush => real ? 0.85 : 0.55,
          PenStyle.pencil => real ? 0.35 : 0.1,
        },
        smoothing: 0.5,
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
    return Path()..addPolygon(outline, true);
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

/// Saved strokes. Kept in its own layer so drawing a new stroke doesn't
/// repaint the whole page.
class StrokesPainter extends CustomPainter {
  StrokesPainter(this.strokes);

  final List<Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    // Highlighters go under the ink, as a highlighter on paper sits under
    // what it marks, so a highlight never dulls the writing.
    for (final stroke in [
      for (final s in strokes)
        if (s.tool == InkTool.highlighter) s,
      for (final s in strokes)
        if (s.tool != InkTool.highlighter) s,
    ]) {
      StrokeRenderer.paint(canvas, stroke);
    }
  }

  @override
  bool shouldRepaint(StrokesPainter old) => !identical(old.strokes, strokes);
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
    if (predicted.value.isNotEmpty) {
      stroke = stroke.withPoints([...stroke.points, ...predicted.value]);
    }
    StrokeRenderer.paint(
      canvas,
      stroke,
      path: StrokeRenderer.buildPath(stroke, complete: false),
    );
  }

  @override
  bool shouldRepaint(LiveStrokePainter old) =>
      old.live != live || old.predicted != predicted;
}
