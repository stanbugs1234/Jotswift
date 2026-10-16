import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'domain/page_element.dart';

/// A strip of tape: solid, or printed with [TapeContent.pattern]. Peeled
/// back ([TapeContent.revealed]), only a faint outline is left, so what's
/// under it can be read and the tape found again.
class TapeView extends StatelessWidget {
  const TapeView({required this.content, super.key});

  final TapeContent content;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: TapePainter(
      color: Color(content.color),
      pattern: content.pattern,
      revealed: content.revealed,
    ),
    child: const SizedBox.expand(),
  );
}

class TapePainter extends CustomPainter {
  TapePainter({
    required this.color,
    required this.pattern,
    this.revealed = false,
  });

  final Color color;
  final TapePattern pattern;
  final bool revealed;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(
      rect,
      Radius.circular(math.min(size.shortestSide * 0.08, 6)),
    );
    if (revealed) {
      canvas
        ..drawRRect(shape, Paint()..color = color.withValues(alpha: 0.12))
        ..drawRRect(
          shape.deflate(1),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = color.withValues(alpha: 0.7),
        );
      return;
    }
    canvas
      ..drawRRect(
        shape.shift(const Offset(0, 2)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      )
      ..drawRRect(shape, Paint()..color = color)
      ..save()
      ..clipRRect(shape);
    final print = Paint()..color = Colors.white.withValues(alpha: 0.35);
    final unit = math.max(size.shortestSide / 4, 8.0);
    switch (pattern) {
      case TapePattern.solid:
        break;
      case TapePattern.stripes:
        print
          ..style = PaintingStyle.stroke
          ..strokeWidth = unit / 2.5;
        for (var x = -size.height; x < size.width; x += unit) {
          canvas.drawLine(
            Offset(x, size.height),
            Offset(x + size.height, 0),
            print,
          );
        }
      case TapePattern.dots:
        for (var y = unit / 2; y < size.height; y += unit) {
          for (var x = unit / 2; x < size.width; x += unit) {
            canvas.drawCircle(Offset(x, y), unit / 5, print);
          }
        }
      case TapePattern.grid:
        print
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(unit / 10, 1);
        for (var x = unit / 2; x < size.width; x += unit) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), print);
        }
        for (var y = unit / 2; y < size.height; y += unit) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), print);
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(TapePainter old) =>
      old.color != color || old.pattern != pattern || old.revealed != revealed;
}
