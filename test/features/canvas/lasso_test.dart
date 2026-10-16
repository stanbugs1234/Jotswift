import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/features/canvas/domain/page_element.dart';
import 'package:notely/features/canvas/domain/stroke.dart';
import 'package:notely/features/canvas/lasso.dart';

Stroke _stroke(List<Offset> points, {double width = 4}) => Stroke(
  id: 's',
  tool: InkTool.pen,
  color: 0xFF000000,
  width: width,
  points: [for (final p in points) InkPoint(p.dx, p.dy, 0.7)],
  createdAt: 5,
);

void main() {
  const square = [
    Offset(0, 0),
    Offset(100, 0),
    Offset(100, 100),
    Offset(0, 100),
  ];

  test('polygonContains', () {
    expect(polygonContains(square, const Offset(50, 50)), isTrue);
    expect(polygonContains(square, const Offset(150, 50)), isFalse);
    expect(polygonContains(square, const Offset(-1, 50)), isFalse);
  });

  test('a stroke is taken when most of its points are inside', () {
    final mostlyIn = _stroke([
      for (var x = 10.0; x <= 130; x += 10) Offset(x, 50),
    ]);
    final mostlyOut = _stroke([
      for (var x = 60.0; x <= 200; x += 10) Offset(x, 50),
    ]);
    expect(lassoTakesStroke(square, mostlyIn), isTrue);
    expect(lassoTakesStroke(square, mostlyOut), isFalse);
  });

  test('an element is taken when its middle is inside', () {
    PageElement at(Offset center) => PageElement(
      id: 'e',
      content: const TextContent(text: 'a', fontSize: 10, color: 0),
      frame: ElementFrame(center: center, width: 300, height: 300),
      z: 0,
      createdAt: 0,
    );
    expect(lassoTakesElement(square, at(const Offset(50, 50))), isTrue);
    expect(lassoTakesElement(square, at(const Offset(150, 50))), isFalse);
  });

  group('LassoTransform', () {
    const t = LassoTransform(
      pivot: Offset(10, 10),
      translate: Offset(5, -3),
      scale: 2,
      rotation: math.pi / 2,
    );

    test('turns clockwise about the pivot, scales, then moves', () {
      final p = t.apply(const Offset(20, 10));
      expect(p.dx, closeTo(15, 1e-9));
      expect(p.dy, closeTo(27, 1e-9));
    });

    test('invert undoes apply', () {
      const p = Offset(37, -12);
      final back = t.invert(t.apply(p));
      expect(back.dx, closeTo(p.dx, 1e-9));
      expect(back.dy, closeTo(p.dy, 1e-9));
    });

    test('strokes keep their look, scaled, with a new id', () {
      final s = _stroke([const Offset(20, 10), const Offset(30, 10)]);
      final moved = t.applyToStroke(s, 'new');
      expect(moved.id, 'new');
      expect(moved.width, 8);
      expect(moved.createdAt, 5);
      expect(moved.points.first.pressure, 0.7);
      expect(moved.points.first.x, closeTo(15, 1e-9));
      expect(moved.deleted, isFalse);
    });

    test('frames move, grow and turn', () {
      final f = t.applyToFrame(
        const ElementFrame(center: Offset(20, 10), width: 10, height: 4),
      );
      expect(f.center.dx, closeTo(15, 1e-9));
      expect(f.width, 20);
      expect(f.height, 8);
      expect(f.rotation, closeTo(math.pi / 2, 1e-9));
    });
  });

  test('selectionBounds covers strokes (with their width) and items', () {
    final bounds = selectionBounds(
      [
        _stroke([const Offset(0, 0), const Offset(10, 0)], width: 4),
      ],
      [
        const PageElement(
          id: 'e',
          content: TextContent(text: 'a', fontSize: 10, color: 0),
          frame: ElementFrame(center: Offset(50, 50), width: 20, height: 10),
          z: 0,
          createdAt: 0,
        ),
      ],
    );
    expect(bounds, const Rect.fromLTRB(-2, -2, 60, 55));
  });
}
