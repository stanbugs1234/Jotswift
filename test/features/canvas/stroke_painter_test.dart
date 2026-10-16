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

  test('pressure: ordinary writing reaches mid weight, firm is full', () {
    expect(inkWeight(0), 0);
    expect(inkWeight(0.05), inInclusiveRange(0.2, 0.3));
    expect(inkWeight(0.2), inInclusiveRange(0.55, 0.65));
    expect(inkWeight(0.45), 1);
    expect(inkWeight(0.9), 1);

    final evened = inkPressures(const [
      InkPoint(0, 0, 0.01),
      InkPoint(1, 0, 0.2),
      InkPoint(2, 0, 0.05),
      InkPoint(3, 0, 0.2),
    ]);
    // The first touch takes the next one's weight; a dip is softened.
    expect(evened.first.pressure, greaterThan(inkWeight(0.05)));
    expect(evened[2].pressure, greaterThan(inkWeight(0.05)));
  });

  test('sparse points are filled in along a smooth curve through them', () {
    const corners = [
      InkPoint(0, 0, 0.2),
      InkPoint(40, 0, 0.4),
      InkPoint(40, 40, 0.6),
      InkPoint(0, 40, 0.8),
    ];
    final smooth = smoothInkPoints(corners, spacing: 4);
    // Every real point is kept, in order.
    var at = 0;
    for (final p in smooth) {
      if (at < corners.length && p.offset == corners[at].offset) at++;
    }
    expect(at, corners.length);
    // No two points further apart than the spacing (and a little).
    for (var i = 1; i < smooth.length; i++) {
      expect(
        (smooth[i].offset - smooth[i - 1].offset).distance,
        lessThan(4 * 1.6),
      );
    }
    // Rounding a right angle bulges a little past it (here 4.2), never far.
    for (final p in smooth) {
      expect(p.x, inInclusiveRange(-6, 46));
      expect(p.y, inInclusiveRange(-6, 46));
    }
  });

  test('ink edges are curves, not straight cuts', () {
    final path = StrokeRenderer.curvedOutline(const [
      Offset(0, 0),
      Offset(10, 0),
      Offset(10, 10),
      Offset(0, 10),
    ]);
    // A curve through midpoints keeps inside the corners.
    expect(path.contains(const Offset(5, 5)), isTrue);
    expect(path.contains(const Offset(0.5, 0.5)), isFalse);
  });

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
  });

  test('a brush tapers its end only once the pen lifts', () {
    final s = scribble(followsPen: true, style: PenStyle.brush);
    final drawing = StrokeRenderer.buildPath(s, complete: false).getBounds();
    final saved = StrokeRenderer.buildPath(s, complete: true).getBounds();
    expect(drawing.left, closeTo(saved.left, 4));
    expect(drawing.right, closeTo(saved.right, 4));
  });
}
