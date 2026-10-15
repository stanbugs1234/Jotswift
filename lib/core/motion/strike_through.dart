import 'package:flutter/material.dart';

/// [text] with a line drawn through it from left to right; [progress] 0–1
/// is how far the line has reached.
class StrikeThroughText extends StatelessWidget {
  const StrikeThroughText({
    required this.text,
    required this.progress,
    required this.color,
    this.style,
    super.key,
  });

  final String text;
  final double progress;

  /// The line's color.
  final Color color;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final label = Text(text, style: style);
    if (progress <= 0) return label;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: 1,
      child: Stack(
        children: [
          label,
          Positioned.fill(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: progress.clamp(0.0, 1.0),
                child: Container(height: 1.6, color: color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
