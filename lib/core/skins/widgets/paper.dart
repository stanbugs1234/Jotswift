import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../paper/paper_style.dart';
import '../notely_skin.dart';

/// A sheet of paper with [child] on top. Uses [style], or the active skin's
/// paper when [style] is null.
class Paper extends StatelessWidget {
  const Paper({
    super.key,
    this.child,
    this.style,
    this.pattern,
    this.padding,
    this.showMargin = true,
  });

  final Widget? child;
  final PaperStyle? style;

  /// Overrides the ruling (e.g. a planner page may be blank).
  final PaperPattern? pattern;
  final EdgeInsetsGeometry? padding;

  /// Whether to draw the left margin line (lined paper only).
  final bool showMargin;

  @override
  Widget build(BuildContext context) {
    final skin = NotelySkin.of(context);
    var paper = style ?? skin.paper;
    if (pattern != null) paper = paper.copyWith(pattern: pattern);
    if (!showMargin) {
      paper = PaperStyle(
        color: paper.color,
        lineColor: paper.lineColor,
        pattern: paper.pattern,
        spacing: paper.spacing,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(skin.cornerRadius),
      child: CustomPaint(
        painter: PaperPainter(paper),
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          // Without a child, fill the space so the paper is still drawn.
          child: child ?? const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// Paints a page background in [paper]'s color and ruling.
class PaperPainter extends CustomPainter {
  const PaperPainter(this.paper, {this.scale = 1});

  final PaperStyle paper;

  /// Multiplies spacing, margins and line widths. Full-size note pages use
  /// a larger scale than the small previews.
  final double scale;

  /// Space above the first line, so headers sit on a clean band.
  static const topMargin = 48.0;
  static const leftMargin = 40.0;

  /// Cornell paper: width of the cue column and height of the summary area,
  /// as fractions of the page.
  static const cornellCueWidth = 0.28;
  static const cornellSummaryHeight = 0.2;

  @override
  void paint(Canvas canvas, Size size) {
    final spacing = paper.spacing * scale;
    final topMargin = PaperPainter.topMargin * scale;
    final line = Paint()
      ..color = paper.lineColor
      ..strokeWidth = scale;

    void horizontalLines(double from, double to, double step) {
      for (var y = from; y < to; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      }
    }

    // Patterns run past the edges; keep them on the page.
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = paper.color);

    switch (paper.pattern) {
      case PaperPattern.blank:
        break;
      case PaperPattern.lined || PaperPattern.narrowLined:
        horizontalLines(topMargin, size.height, spacing);
        _drawMargin(canvas, size);
      case PaperPattern.grid:
        horizontalLines(spacing, size.height, spacing);
        for (var x = spacing; x < size.width; x += spacing) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
        }
      case PaperPattern.dot:
        final dot = Paint()..color = paper.lineColor;
        for (var y = spacing; y < size.height; y += spacing) {
          for (var x = spacing; x < size.width; x += spacing) {
            canvas.drawCircle(Offset(x, y), 1.4 * scale, dot);
          }
        }
      case PaperPattern.music:
        // Staves of five lines, with four line-gaps between staves.
        final staff = spacing * 4;
        for (var top = topMargin; top + staff < size.height;) {
          horizontalLines(top, top + staff + 1, spacing);
          top += staff + spacing * 4;
        }
      case PaperPattern.cornell:
        final summaryTop = size.height * (1 - cornellSummaryHeight);
        horizontalLines(topMargin, summaryTop, spacing);
        final divider = Paint()
          ..color = paper.lineColor
          ..strokeWidth = 2 * scale;
        final cueX = size.width * cornellCueWidth;
        canvas
          ..drawLine(Offset(cueX, 0), Offset(cueX, summaryTop), divider)
          ..drawLine(
            Offset(0, summaryTop),
            Offset(size.width, summaryTop),
            divider,
          );
      case PaperPattern.isometric:
        _isometric(canvas, size, spacing, line);
      case PaperPattern.hexagon:
        _hexagons(canvas, size, spacing, line);
      case PaperPattern.handwriting:
        _writingRows(canvas, size, spacing, line, slant: false);
      case PaperPattern.calligraphy:
        _writingRows(canvas, size, spacing, line, slant: true);
      case PaperPattern.legal:
        horizontalLines(topMargin * 2, size.height, spacing);
        _drawMargin(canvas, size, doubled: true);
      case PaperPattern.engineering:
        final major = Paint()
          ..color = paper.lineColor
          ..strokeWidth = 1.8 * scale;
        var i = 1;
        for (var y = spacing; y < size.height; y += spacing, i++) {
          canvas.drawLine(
            Offset(0, y),
            Offset(size.width, y),
            i % 5 == 0 ? major : line,
          );
        }
        i = 1;
        for (var x = spacing; x < size.width; x += spacing, i++) {
          canvas.drawLine(
            Offset(x, 0),
            Offset(x, size.height),
            i % 5 == 0 ? major : line,
          );
        }
    }
  }

  /// Horizontal rows of triangles: lines at 0°, 60° and 120°, [side] apart.
  void _isometric(Canvas canvas, Size size, double side, Paint line) {
    final rowHeight = side * math.sqrt(3) / 2;
    for (var y = 0.0; y <= size.height; y += rowHeight) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    // Each sloped line rises one row per half side; start them far enough
    // left that they also cover the bottom-left corner.
    final run = size.height / math.sqrt(3);
    for (var x = -run; x <= size.width + run; x += side) {
      canvas
        ..drawLine(Offset(x, 0), Offset(x + run, size.height), line)
        ..drawLine(Offset(x, 0), Offset(x - run, size.height), line);
    }
  }

  /// Flat-topped hexagons with sides [side] long.
  void _hexagons(Canvas canvas, Size size, double side, Paint line) {
    final stroke = Paint()
      ..color = line.color
      ..strokeWidth = line.strokeWidth
      ..style = PaintingStyle.stroke;
    final h = side * math.sqrt(3);
    final path = Path();
    var column = 0;
    for (var cx = 0.0; cx < size.width + side; cx += side * 1.5, column++) {
      final offset = column.isOdd ? h / 2 : 0.0;
      for (var cy = offset; cy < size.height + h; cy += h) {
        for (var k = 0; k <= 6; k++) {
          final a = math.pi / 3 * k;
          final p = Offset(cx + side * math.cos(a), cy + side * math.sin(a));
          k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
      }
    }
    canvas.drawPath(path, stroke);
  }

  /// Writing rows, each [unit] x 4 tall: an ascender line, a dashed
  /// x-height line, the baseline and a faint descender line. Calligraphy
  /// adds slant guides at 55°.
  void _writingRows(
    Canvas canvas,
    Size size,
    double unit,
    Paint line, {
    required bool slant,
  }) {
    final faint = Paint()
      ..color = paper.lineColor.withValues(alpha: paper.lineColor.a * 0.5)
      ..strokeWidth = scale;
    final base = Paint()
      ..color = paper.lineColor
      ..strokeWidth = 1.6 * scale;
    final row = unit * 4;
    final gap = unit * 1.5;
    for (
      var top = PaperPainter.topMargin * scale;
      top + row < size.height;
      top += row + gap
    ) {
      canvas
        ..drawLine(Offset(0, top), Offset(size.width, top), line)
        ..drawLine(
          Offset(0, top + unit * 3),
          Offset(size.width, top + unit * 3),
          base,
        )
        ..drawLine(Offset(0, top + row), Offset(size.width, top + row), faint);
      // Dashed x-height line.
      final y = top + unit * 1.5;
      final dash = 6 * scale;
      for (var x = 0.0; x < size.width; x += dash * 2) {
        canvas.drawLine(Offset(x, y), Offset(x + dash, y), line);
      }
      if (slant) {
        final dx = row / math.tan(55 * math.pi / 180);
        for (var x = 0.0; x < size.width + dx; x += unit * 2) {
          canvas.drawLine(Offset(x, top + row), Offset(x + dx, top), faint);
        }
      }
    }
  }

  void _drawMargin(Canvas canvas, Size size, {bool doubled = false}) {
    final margin = paper.marginColor;
    if (margin == null) return;
    final paint = Paint()
      ..color = margin
      ..strokeWidth = 1.5 * scale;
    final x = (doubled ? leftMargin * 1.6 : leftMargin) * scale;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    if (doubled) {
      final x2 = x + 4 * scale;
      canvas.drawLine(Offset(x2, 0), Offset(x2, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(PaperPainter old) =>
      old.paper != paper || old.scale != scale;
}
