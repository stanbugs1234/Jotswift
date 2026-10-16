import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:notely/features/canvas/domain/stroke.dart';

Stroke line({List<InkPoint>? points, double width = 4}) => Stroke(
  id: 's1',
  tool: InkTool.pen,
  color: 0xFF112233,
  width: width,
  points:
      points ??
      const [InkPoint(10, 10, 0.25), InkPoint(110, 10, 0.5), InkPoint(110, 60)],
  createdAt: 1000,
  pressureSensitive: true,
);

void main() {
  test('round-trips through a Firestore map', () {
    final stroke = line();
    final copy = Stroke.fromMap('s1', stroke.toMap());

    expect(copy.tool, InkTool.pen);
    expect(copy.color, 0xFF112233);
    expect(copy.width, 4);
    expect(copy.createdAt, 1000);
    expect(copy.pressureSensitive, isTrue);
    expect(copy.deleted, isFalse);
    expect(copy.points.map((p) => [p.x, p.y, p.pressure]), [
      [10, 10, 0.25],
      [110, 10, 0.5],
      [110, 60, 0.5],
    ]);
  });

  test('remembers strokes that follow the pen; older ones did not', () {
    final drawn = Stroke.fromMap('s1', {...line().toMap(), 'followsPen': true});
    expect(drawn.followsPen, isTrue);
    expect(Stroke.fromMap('s1', drawn.toMap()).followsPen, isTrue);
    expect(drawn.copyWith(deleted: true).followsPen, isTrue);
    expect(drawn.withPoints(drawn.points).followsPen, isTrue);
    expect(Stroke.fromMap('s1', line().toMap()).followsPen, isFalse);
    expect(line().toMap(), isNot(contains('followsPen')));
  });

  test('packs points flat and rounds them to keep documents small', () {
    final stroke = line(points: const [InkPoint(1.23456, 7.891011, 0.123456)]);

    expect(stroke.toMap()['points'], [1.2, 7.9, 0.12]);
  });

  test('reads highlighter strokes and erased strokes', () {
    final map = line().toMap()
      ..['tool'] = 'highlighter'
      ..['deleted'] = true;
    final stroke = Stroke.fromMap('s1', map);

    expect(stroke.tool, InkTool.highlighter);
    expect(stroke.deleted, isTrue);
  });

  test('bounds cover every point', () {
    expect(line().bounds, const Rect.fromLTRB(10, 10, 110, 60));
  });

  group('hitTest', () {
    final stroke = line(); // An "L": right along y=10, then down x=110.

    test('hits points on or near the line', () {
      expect(stroke.hitTest(const Offset(60, 10), 1), isTrue);
      expect(stroke.hitTest(const Offset(60, 15), 4), isTrue); // 5 ≤ 4 + 2
      expect(stroke.hitTest(const Offset(112, 40), 1), isTrue);
    });

    test('misses points away from the line, even inside its bounds', () {
      expect(stroke.hitTest(const Offset(60, 40), 5), isFalse);
      expect(stroke.hitTest(const Offset(300, 300), 5), isFalse);
    });

    test('hits a single-point stroke (a dot)', () {
      final dot = line(points: const [InkPoint(50, 50)]);
      expect(dot.hitTest(const Offset(52, 50), 1), isTrue);
      expect(dot.hitTest(const Offset(60, 50), 1), isFalse);
    });
  });
}
