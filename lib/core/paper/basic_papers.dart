import 'dart:ui';

import 'paper_style.dart';

/// The paper colors every user can pick, each with ruling that suits it.
enum BasicPaperColor {
  white(Color(0xFFFFFFFF), Color(0xFFC9D6EA), Color(0xFFE8A0A0)),
  cream(Color(0xFFFBF6E9), Color(0xFFDCD3BC), Color(0xFFE3A99A)),
  gray(Color(0xFFEDEEF0), Color(0xFFC4C8CF), Color(0xFFD9A0A0)),
  dark(Color(0xFF26282C), Color(0xFF474B52), Color(0xFF8A5A5A));

  const BasicPaperColor(this.color, this.lineColor, this.marginColor);

  final Color color;
  final Color lineColor;
  final Color marginColor;
}

/// The usual spacing for each pattern, in page units.
double defaultSpacing(PaperPattern pattern) => switch (pattern) {
  PaperPattern.narrowLined => 24,
  PaperPattern.grid => 28,
  PaperPattern.dot => 26,
  PaperPattern.music => 12,
  PaperPattern.blank || PaperPattern.lined || PaperPattern.cornell => 32,
};

/// A free paper: [pattern] on [color].
PaperStyle basicPaper(PaperPattern pattern, BasicPaperColor color) {
  final hasMargin =
      pattern == PaperPattern.lined || pattern == PaperPattern.narrowLined;
  return PaperStyle(
    color: color.color,
    lineColor: color.lineColor,
    marginColor: hasMargin ? color.marginColor : null,
    pattern: pattern,
    spacing: defaultSpacing(pattern),
  );
}

/// Every free paper, grouped by pattern.
final basicPapers = [
  for (final pattern in PaperPattern.values)
    for (final color in BasicPaperColor.values) basicPaper(pattern, color),
];
