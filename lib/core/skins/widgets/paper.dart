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
    }
  }

  void _drawMargin(Canvas canvas, Size size) {
    final margin = paper.marginColor;
    if (margin == null) return;
    final x = leftMargin * scale;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = margin
        ..strokeWidth = 1.5 * scale,
    );
  }

  @override
  bool shouldRepaint(PaperPainter old) =>
      old.paper != paper || old.scale != scale;
}
