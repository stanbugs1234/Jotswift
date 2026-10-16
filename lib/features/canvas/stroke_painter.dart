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
    for (final stroke in strokes) {
      canvas.drawPath(
        StrokeRenderer.pathFor(stroke),
        StrokeRenderer.paintFor(stroke),
      );
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
    canvas.drawPath(
      StrokeRenderer.buildPath(stroke, complete: false),
      StrokeRenderer.paintFor(stroke),
    );
  }

  @override
  bool shouldRepaint(LiveStrokePainter old) =>
      old.live != live || old.predicted != predicted;
}
