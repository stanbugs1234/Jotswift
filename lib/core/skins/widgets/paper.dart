import 'package:flutter/material.dart';

import '../notely_skin.dart';
import '../skin_manifest.dart';

/// A sheet of paper in the active skin's style, with [child] on top.
class Paper extends StatelessWidget {
  const Paper({
    super.key,
    this.child,
    this.pattern,
    this.padding,
    this.showMargin = true,
  });

  final Widget? child;

  /// Overrides the skin's default ruling (e.g. a planner page may be blank).
  final PaperPattern? pattern;
  final EdgeInsetsGeometry? padding;

  /// Whether to draw the skin's left margin line (lined paper only).
  final bool showMargin;

  @override
  Widget build(BuildContext context) {
    final skin = NotelySkin.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(skin.cornerRadius),
      child: CustomPaint(
        painter: PaperPainter(
          color: skin.paperColor,
          lineColor: skin.lineColor,
          marginColor: showMargin ? skin.marginColor : null,
          pattern: pattern ?? skin.pattern,
          spacing: skin.spacing,
        ),
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          // Without a child, fill the space so the paper is still drawn.
          child: child ?? const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// Paints a page background: blank, lined, grid or dot.
class PaperPainter extends CustomPainter {
  const PaperPainter({
    required this.color,
    required this.lineColor,
    required this.pattern,
    required this.spacing,
    this.marginColor,
  });

  final Color color;
  final Color lineColor;
  final Color? marginColor;
  final PaperPattern pattern;
  final double spacing;

  /// Space above the first line, so headers sit on a clean band.
  static const topMargin = 48.0;
  static const leftMargin = 40.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 1;

    switch (pattern) {
      case PaperPattern.blank:
        break;
      case PaperPattern.lined:
        for (var y = topMargin; y < size.height; y += spacing) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
      case PaperPattern.grid:
        for (var y = spacing; y < size.height; y += spacing) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
        for (var x = spacing; x < size.width; x += spacing) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
        }
      case PaperPattern.dot:
        final dot = Paint()..color = lineColor;
        for (var y = spacing; y < size.height; y += spacing) {
          for (var x = spacing; x < size.width; x += spacing) {
            canvas.drawCircle(Offset(x, y), 1.4, dot);
          }
        }
    }

    final margin = marginColor;
    if (margin != null && pattern == PaperPattern.lined) {
      canvas.drawLine(
        const Offset(leftMargin, 0),
        Offset(leftMargin, size.height),
        Paint()
          ..color = margin
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(PaperPainter old) =>
      old.color != color ||
      old.lineColor != lineColor ||
      old.marginColor != marginColor ||
      old.pattern != pattern ||
      old.spacing != spacing;
}
