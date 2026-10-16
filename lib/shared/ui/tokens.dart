import 'package:flutter/widgets.dart';

/// The spacing scale. Gaps and padding use these steps, so screens line
/// up with each other.
abstract final class Insets {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;
}

/// Corner radii.
abstract final class Radii {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
}

/// The widest forms, settings and other reading-width content get.
const contentMaxWidth = 720.0;

/// The side margin of a screen's content: 16 on phones, 20 on tablets.
/// Titles, chips and content all start here.
double gutterOf(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 600 ? Insets.lg : 20;
