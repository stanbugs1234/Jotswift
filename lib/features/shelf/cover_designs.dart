import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Patterned covers drawn in code, in any cover color. Designed cover art
/// from the catalog arrives in milestone 5; these give the picker some
/// variety until then.
enum CoverDesign {
  stripes('Stripes'),
  dots('Dots'),
  grid('Grid'),
  chevron('Chevron'),
  waves('Waves'),
  nameplate('Label');

  const CoverDesign(this.label);

  final String label;

  /// The id saved in `NotebookCover.coverId`.
  String get id => 'design_$name';

  /// The design for a saved id, or null for ids this version doesn't know.
  static CoverDesign? byId(String? id) =>
      values.where((d) => d.id == id).firstOrNull;
}

/// Paints [design] over a cover of [color].
class CoverDesignPainter extends CustomPainter {
  const CoverDesignPainter(this.design, this.color);

  final CoverDesign design;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final dark = ThemeData.estimateBrightnessForColor(color) == Brightness.dark;
    final ink = (dark ? Colors.white : Colors.black).withValues(alpha: 0.16);
    final unit = size.width / 10;
    final line = Paint()
      ..color = ink
      ..strokeWidth = unit * 0.35
      ..style = PaintingStyle.stroke;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    switch (design) {
      case CoverDesign.stripes:
        for (var x = -size.height; x < size.width; x += unit * 1.6) {
          canvas.drawLine(
            Offset(x, size.height),
            Offset(x + size.height, 0),
            line,
          );
        }
      case CoverDesign.dots:
        final dot = Paint()..color = ink;
        for (var row = 0; row * unit < size.height + unit; row++) {
          final shift = row.isOdd ? unit : 0.0;
          for (var x = shift; x < size.width + unit; x += unit * 2) {
            canvas.drawCircle(Offset(x, row * unit), unit * 0.28, dot);
          }
        }
      case CoverDesign.grid:
        line.strokeWidth = unit * 0.08;
        for (var x = unit; x < size.width; x += unit) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
        }
        for (var y = unit; y < size.height; y += unit) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
      case CoverDesign.chevron:
        line.strokeWidth = unit * 0.25;
        for (var y = 0.0; y < size.height + unit; y += unit * 1.4) {
          final path = Path()..moveTo(0, y);
          for (var x = 0.0; x < size.width + unit; x += unit) {
            path.lineTo(x + unit / 2, y - unit / 2);
            path.lineTo(x + unit, y);
          }
          canvas.drawPath(path, line);
        }
      case CoverDesign.waves:
        line.strokeWidth = unit * 0.18;
        for (var y = 0.0; y < size.height + unit; y += unit * 1.2) {
          final path = Path()..moveTo(0, y);
          for (var x = 0.0; x <= size.width; x += unit / 4) {
            path.lineTo(x, y + math.sin(x / unit * math.pi) * unit * 0.3);
          }
          canvas.drawPath(path, line);
        }
      case CoverDesign.nameplate:
        // A plain label, like a school exercise book.
        final rect = Rect.fromLTWH(
          size.width * 0.2,
          size.height * 0.16,
          size.width * 0.66,
          size.height * 0.2,
        );
        final radius = Radius.circular(unit * 0.6);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, radius),
          Paint()..color = Colors.white.withValues(alpha: 0.92),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.deflate(unit * 0.25), radius),
          Paint()
            ..color = color.withValues(alpha: 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = unit * 0.08,
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(CoverDesignPainter old) =>
      old.design != design || old.color != color;
}
