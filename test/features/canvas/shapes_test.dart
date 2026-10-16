import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:notely/features/canvas/ruler.dart';
import 'package:notely/features/canvas/shapes.dart';

/// [outline] traced by hand: evenly spaced points with a little wobble.
List<Offset> _hand(List<Offset> outline, {int seed = 1, double wobble = 3}) {
  final random = math.Random(seed);
  return [
    for (final p in densify(outline, step: 8))
      p +
          Offset(
            (random.nextDouble() - 0.5) * 2 * wobble,
            (random.nextDouble() - 0.5) * 2 * wobble,
          ),
  ];
}

List<Offset> _ellipse(Offset c, double rx, double ry, {double sweep = 1.0}) => [
  for (var i = 0; i <= 60; i++)
    c +
        Offset(
          rx * math.cos(2 * math.pi * sweep * i / 60),
          ry * math.sin(2 * math.pi * sweep * i / 60),
        ),
];

void main() {
  test('a straight stroke is a line, leveled when nearly level', () {
    final shape = recognizeShape(
      _hand([const Offset(0, 0), const Offset(300, 12)]),
    )!;
    expect(shape.kind, ShapeKind.line);
    expect(shape.outline.last.dy, closeTo(shape.outline.first.dy, 0.001));
  });

  test('a slanted line keeps its angle', () {
    final shape = recognizeShape(
      _hand([const Offset(0, 0), const Offset(300, 120)]),
    )!;
    expect(shape.kind, ShapeKind.line);
    final d = shape.outline.last - shape.outline.first;
    expect(d.dy / d.dx, closeTo(0.4, 0.05));
  });

  test('a round loop is a circle', () {
    for (var seed = 1; seed <= 5; seed++) {
      final shape = recognizeShape(
        _hand(_ellipse(const Offset(200, 200), 100, 104), seed: seed),
      );
      expect(shape?.kind, ShapeKind.circle, reason: 'seed $seed');
    }
  });

  test('a long loop is an ellipse', () {
    final shape = recognizeShape(
      _hand(_ellipse(const Offset(200, 200), 160, 80)),
    )!;
    expect(shape.kind, ShapeKind.ellipse);
  });

  test('a box is a rectangle, squared up', () {
    for (var seed = 1; seed <= 5; seed++) {
      final shape = recognizeShape(
        _hand([
          const Offset(10, 10),
          const Offset(310, 14),
          const Offset(306, 200),
          const Offset(8, 196),
          const Offset(10, 10),
        ], seed: seed),
      );
      expect(shape?.kind, ShapeKind.rectangle, reason: 'seed $seed');
      final o = shape!.outline;
      expect(o[0].dy, o[1].dy);
      expect(o[1].dx, o[2].dx);
    }
  });

  test('three corners make a triangle', () {
    for (var seed = 1; seed <= 5; seed++) {
      final shape = recognizeShape(
        _hand([
          const Offset(150, 0),
          const Offset(300, 250),
          const Offset(0, 250),
          const Offset(150, 0),
        ], seed: seed),
      );
      expect(shape?.kind, ShapeKind.triangle, reason: 'seed $seed');
      expect(shape!.outline, hasLength(4));
    }
  });

  test('a five-sided loop is a polygon', () {
    final pts = [
      for (var i = 0; i <= 5; i++)
        const Offset(200, 200) +
            Offset(
              150 * math.cos(-math.pi / 2 + 2 * math.pi * i / 5),
              150 * math.sin(-math.pi / 2 + 2 * math.pi * i / 5),
            ),
    ];
    final shape = recognizeShape(_hand(pts))!;
    expect(shape.kind, ShapeKind.polygon);
    expect(shape.outline, hasLength(6));
  });

  test('scribbles, words and half circles are left alone', () {
    final random = math.Random(4);
    final scribble = [
      for (var i = 0; i < 80; i++)
        Offset(random.nextDouble() * 200, random.nextDouble() * 200),
    ];
    expect(recognizeShape(scribble), isNull);
    // A wavy line, like handwriting.
    final wave = [
      for (var i = 0; i < 80; i++) Offset(i * 5.0, 40 * math.sin(i / 4)),
    ];
    expect(recognizeShape(wave), isNull);
    expect(
      recognizeShape(_hand(_ellipse(const Offset(0, 0), 100, 100, sweep: 0.5))),
      isNull,
    );
  });

  test('tiny strokes are left alone', () {
    expect(
      recognizeShape(
        _hand([const Offset(0, 0), const Offset(8, 0)], wobble: 0),
      ),
      isNull,
    );
  });

  group('Ruler', () {
    const ruler = Ruler(center: Offset(500, 500), angle: math.pi / 4);

    test('local and page coordinates round-trip', () {
      const p = Offset(530, 610);
      final back = ruler.toPage(ruler.toLocal(p));
      expect(back.dx, closeTo(p.dx, 1e-9));
      expect(back.dy, closeTo(p.dy, 1e-9));
    });

    test('a point by an edge follows it; others do not', () {
      final nearBottom = ruler.toPage(
        const Offset(100, Ruler.thickness / 2 + 10),
      );
      expect(ruler.edgeNear(nearBottom), 1);
      final farAway = ruler.toPage(const Offset(100, 300));
      expect(ruler.edgeNear(farAway), isNull);
      final projected = ruler.project(nearBottom, 1, 6);
      expect(
        ruler.toLocal(projected).dy,
        closeTo(Ruler.thickness / 2 + 3 + 2, 1e-9),
      );
    });

    test('shows its angle in degrees, and snaps to 45s', () {
      expect(ruler.degrees, 45);
      expect(snapRulerAngle(math.pi / 4 + 0.02), math.pi / 4);
      expect(snapRulerAngle(0.3), 0.3);
    });
  });

  group('scribbles', () {
    /// Back and forth [passes] times across [width], drifting down.
    List<Offset> zigzag({int passes = 7, double width = 160}) => _hand([
      for (var i = 0; i <= passes; i++)
        Offset(i.isEven ? 0 : width, 100 + i * 4.0),
    ]);

    ({String id, Rect bounds, bool Function(Offset, double) hits}) word(
      String id,
      Rect bounds,
    ) =>
        (id: id, bounds: bounds, hits: (p, r) => bounds.inflate(r).contains(p));

    test('hard back and forth is a scribble; writing and shapes are not', () {
      expect(isScribble(zigzag()), isTrue);
      expect(isScribble(zigzag(passes: 2)), isFalse);
      expect(
        isScribble(_hand([const Offset(0, 0), const Offset(200, 10)])),
        isFalse,
      );
      expect(
        isScribble(
          _hand([
            for (var i = 0; i <= 24; i++)
              Offset(
                80 * math.cos(i * math.pi / 12),
                80 * math.sin(i * math.pi / 12),
              ),
          ]),
        ),
        isFalse,
      );
    });

    test('a scribble takes the writing under it, and nothing else', () {
      final out = scribbledOut(zigzag(), 6, [
        word('under', const Rect.fromLTWH(20, 98, 120, 24)),
        word('beside', const Rect.fromLTWH(400, 100, 120, 24)),
        word('long line', const Rect.fromLTWH(-300, 110, 900, 2)),
      ]);
      expect(out, ['under']);
    });

    test('a scribble over nothing is just ink', () {
      expect(
        scribbledOut(zigzag(), 6, [
          word('far', const Rect.fromLTWH(400, 400, 50, 20)),
        ]),
        isEmpty,
      );
    });
  });
}
