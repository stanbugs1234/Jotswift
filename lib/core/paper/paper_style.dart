import 'dart:ui';

import 'package:flutter/foundation.dart';

/// The ruling printed on a page.
enum PaperPattern {
  blank,
  lined,

  /// Lined, with lines closer together.
  narrowLined,
  grid,
  dot,

  /// Groups of five lines for writing music.
  music,

  /// Lined, with a cue column on the left and a summary area at the bottom.
  cornell,
}

/// The size of a notebook's pages.
enum PaperSize { letter, a4, a5, phone }

enum PaperOrientation { portrait, landscape }

/// How a page's background looks: its color and ruling.
///
/// Saved on a notebook (its default paper) and on a page (when the page
/// differs from its notebook). Colors are stored as ARGB integers.
@immutable
class PaperStyle {
  const PaperStyle({
    required this.color,
    required this.lineColor,
    required this.pattern,
    required this.spacing,
    this.marginColor,
  });

  /// Reads a saved paper. Returns null if [map] isn't a valid paper, so a
  /// bad value falls back to the default paper instead of breaking the page.
  static PaperStyle? fromMap(Object? map) {
    if (map is! Map) return null;
    final color = map['color'];
    final lineColor = map['lineColor'];
    final spacing = map['spacing'];
    final pattern = PaperPattern.values
        .where((p) => p.name == map['pattern'])
        .firstOrNull;
    if (color is! int ||
        lineColor is! int ||
        spacing is! num ||
        pattern == null) {
      return null;
    }
    final margin = map['marginColor'];
    return PaperStyle(
      color: Color(color),
      lineColor: Color(lineColor),
      marginColor: margin is int ? Color(margin) : null,
      pattern: pattern,
      spacing: spacing.toDouble().clamp(minSpacing, maxSpacing),
    );
  }

  static const minSpacing = 8.0;
  static const maxSpacing = 200.0;

  final Color color;
  final Color lineColor;

  /// The left margin line (lined and narrow-lined paper only).
  final Color? marginColor;
  final PaperPattern pattern;

  /// Distance between lines, grid cells or dots, in page units.
  final double spacing;

  Map<String, Object?> toMap() => {
    'color': color.toARGB32(),
    'lineColor': lineColor.toARGB32(),
    'marginColor': marginColor?.toARGB32(),
    'pattern': pattern.name,
    'spacing': spacing,
  };

  PaperStyle copyWith({
    Color? color,
    Color? lineColor,
    Color? marginColor,
    PaperPattern? pattern,
    double? spacing,
  }) => PaperStyle(
    color: color ?? this.color,
    lineColor: lineColor ?? this.lineColor,
    marginColor: marginColor ?? this.marginColor,
    pattern: pattern ?? this.pattern,
    spacing: spacing ?? this.spacing,
  );

  @override
  bool operator ==(Object other) =>
      other is PaperStyle &&
      other.color == color &&
      other.lineColor == lineColor &&
      other.marginColor == marginColor &&
      other.pattern == pattern &&
      other.spacing == spacing;

  @override
  int get hashCode =>
      Object.hash(color, lineColor, marginColor, pattern, spacing);
}
