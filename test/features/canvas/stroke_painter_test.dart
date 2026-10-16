import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:notely/features/canvas/domain/stroke.dart';
import 'package:notely/features/canvas/stroke_painter.dart';

void main() {
  Stroke scribble({
    required bool followsPen,
    PenStyle style = PenStyle.fountain,
    InkTool tool = InkTool.pen,
  }) => Stroke(
    id: 's',
    tool: tool,
    color: 0xFF000000,
    width: 4,
    points: [
      for (var i = 0; i < 80; i++)
        InkPoint(100 + i * 4.0, 200 + 40 * math.sin(i / 6), 0.3 + i / 200),
    ],
    createdAt: 0,
    pressureSensitive: true,
    style: style,
    followsPen: followsPen,
  );

  test('dashed and dotted lines are broken into pieces', () {
    int pieces(LineDash dash) => StrokeRenderer.buildPath(
      Stroke(
        id: dash.name,
        tool: InkTool.pen,
        color: 0xFF000000,
        width: 4,
        points: [for (var x = 0.0; x <= 200; x += 5) InkPoint(x, 0)],
        createdAt: 0,
        style: PenStyle.ballpoint,
        dash: dash,
      ),
      complete: true,
    ).computeMetrics().length;

    expect(pieces(LineDash.solid), 1);
    // 200 long, 4 wide: a dash and gap every 20.8, a dot every 8.8.
    expect(pieces(LineDash.dashed), inInclusiveRange(9, 11));
    expect(pieces(LineDash.dotted), inInclusiveRange(22, 24));
  });

  test('pen ink looks the same while drawn as once saved', () {
    for (final style in [
      PenStyle.ballpoint,
      PenStyle.fountain,
      PenStyle.pencil,
    ]) {
      final s = scribble(followsPen: true, style: style);
      expect(
        StrokeRenderer.buildPath(s, complete: false).getBounds(),
        StrokeRenderer.buildPath(s, complete: true).getBounds(),
        reason: '$style',
      );
    }
    final h = scribble(followsPen: true, tool: InkTool.highlighter);
    expect(
      StrokeRenderer.buildPath(h, complete: false).getBounds(),
      StrokeRenderer.buildPath(h, complete: true).getBounds(),
    );
  });

  test('while drawing, pen ink reaches the tip', () {
    final s = scribble(followsPen: true);
    final tip = s.points.last.offset;
    final drawn = StrokeRenderer.buildPath(s, complete: false).getBounds();
    expect(drawn.right, greaterThanOrEqualTo(tip.dx));

    // Older (and finger) strokes are smoothed more, so they trail behind.
    final smoothed = scribble(followsPen: false);
    final trailing = StrokeRenderer.buildPath(
      smoothed,
      complete: false,
    ).getBounds();
    expect(trailing.right, lessThan(drawn.right - 1));
  });

  test('a brush tapers its end only once the pen lifts', () {
    final s = scribble(followsPen: true, style: PenStyle.brush);
    final drawing = StrokeRenderer.buildPath(s, complete: false).getBounds();
    final saved = StrokeRenderer.buildPath(s, complete: true).getBounds();
    expect(drawing.left, closeTo(saved.left, 4));
    expect(drawing.right, closeTo(saved.right, 4));
  });
}
