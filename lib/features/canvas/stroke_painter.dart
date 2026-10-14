import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

import 'domain/stroke.dart';

/// Turns strokes into filled outlines with perfect_freehand. Outlines are
/// cached per stroke, since saved strokes never change.
abstract final class StrokeRenderer {
  static final _cache = Expando<Path>('strokePath');

  static Path pathFor(Stroke stroke) =>
      _cache[stroke] ??= buildPath(stroke, complete: true);

  static Path buildPath(Stroke stroke, {required bool complete}) {
    final points = [
      for (final p in stroke.points)
        PointVector(p.x, p.y, stroke.pressureSensitive ? p.pressure : null),
    ];
    final highlighter = stroke.tool == InkTool.highlighter;
    final outline = getStroke(
      points,
      options: StrokeOptions(
        size: stroke.width,
        // Real pressure gets the full effect. Simulated pressure (fingers,
        // mouse) thins lines a lot on fast moves, so keep it subtle.
        thinning: highlighter
            ? 0
            : stroke.pressureSensitive
            ? 0.6
            : 0.25,
        smoothing: 0.5,
        streamline: highlighter ? 0.6 : 0.4,
        simulatePressure: !highlighter && !stroke.pressureSensitive,
        isComplete: complete,
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

  static Paint paintFor(Stroke stroke) => Paint()
    ..color = Color(stroke.color)
    ..isAntiAlias = true;
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

/// The stroke being drawn right now. Repaints on every pointer move without
/// rebuilding any widgets.
class LiveStrokePainter extends CustomPainter {
  LiveStrokePainter(this.live) : super(repaint: live);

  final ValueNotifier<Stroke?> live;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = live.value;
    if (stroke == null || stroke.points.isEmpty) return;
    canvas.drawPath(
      StrokeRenderer.buildPath(stroke, complete: false),
      StrokeRenderer.paintFor(stroke),
    );
  }

  @override
  bool shouldRepaint(LiveStrokePainter old) => old.live != live;
}
