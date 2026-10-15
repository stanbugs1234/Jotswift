import 'package:flutter/material.dart';

import '../paper/paper_style.dart';

/// Skin values that don't fit in [ThemeData]: paper, ink palette and the
/// accent font. Read it with `NotelySkin.of(context)`.
@immutable
class NotelySkin extends ThemeExtension<NotelySkin> {
  const NotelySkin({
    required this.id,
    required this.name,
    required this.paperColor,
    required this.lineColor,
    required this.marginColor,
    required this.pattern,
    required this.spacing,
    required this.inkColors,
    required this.accentTextStyle,
    required this.cornerRadius,
  });

  final String id;
  final String name;
  final Color paperColor;
  final Color lineColor;
  final Color? marginColor;
  final PaperPattern pattern;
  final double spacing;
  final List<Color> inkColors;

  /// Decorative style for planner and page headers.
  final TextStyle accentTextStyle;
  final double cornerRadius;

  /// This skin's paper, used by notebooks and pages that don't choose
  /// their own.
  PaperStyle get paper => PaperStyle(
    color: paperColor,
    lineColor: lineColor,
    marginColor: marginColor,
    pattern: pattern,
    spacing: spacing,
  );

  static NotelySkin of(BuildContext context) {
    final skin = Theme.of(context).extension<NotelySkin>();
    assert(
      skin != null,
      'No NotelySkin in the theme. Build it with SkinEngine.',
    );
    return skin!;
  }

  @override
  NotelySkin copyWith({
    String? id,
    String? name,
    Color? paperColor,
    Color? lineColor,
    Color? marginColor,
    PaperPattern? pattern,
    double? spacing,
    List<Color>? inkColors,
    TextStyle? accentTextStyle,
    double? cornerRadius,
  }) {
    return NotelySkin(
      id: id ?? this.id,
      name: name ?? this.name,
      paperColor: paperColor ?? this.paperColor,
      lineColor: lineColor ?? this.lineColor,
      marginColor: marginColor ?? this.marginColor,
      pattern: pattern ?? this.pattern,
      spacing: spacing ?? this.spacing,
      inkColors: inkColors ?? this.inkColors,
      accentTextStyle: accentTextStyle ?? this.accentTextStyle,
      cornerRadius: cornerRadius ?? this.cornerRadius,
    );
  }

  @override
  NotelySkin lerp(NotelySkin? other, double t) {
    if (other == null) return this;
    final end = t >= 0.5 ? other : this;
    return NotelySkin(
      id: end.id,
      name: end.name,
      paperColor: Color.lerp(paperColor, other.paperColor, t)!,
      lineColor: Color.lerp(lineColor, other.lineColor, t)!,
      marginColor: Color.lerp(marginColor, other.marginColor, t),
      pattern: end.pattern,
      spacing: end.spacing,
      inkColors: end.inkColors,
      accentTextStyle: TextStyle.lerp(
        accentTextStyle,
        other.accentTextStyle,
        t,
      )!,
      cornerRadius: end.cornerRadius,
    );
  }
}
