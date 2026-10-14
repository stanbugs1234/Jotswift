import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Turns a font family name from a skin manifest into text styles.
abstract interface class FontResolver {
  TextStyle style(String family, [TextStyle? base]);
}

extension FontResolverTextTheme on FontResolver {
  /// Applies [family] to every style in [base].
  TextTheme textTheme(String family, TextTheme base) {
    TextStyle? f(TextStyle? s) => s == null ? null : style(family, s);
    return base.copyWith(
      displayLarge: f(base.displayLarge),
      displayMedium: f(base.displayMedium),
      displaySmall: f(base.displaySmall),
      headlineLarge: f(base.headlineLarge),
      headlineMedium: f(base.headlineMedium),
      headlineSmall: f(base.headlineSmall),
      titleLarge: f(base.titleLarge),
      titleMedium: f(base.titleMedium),
      titleSmall: f(base.titleSmall),
      bodyLarge: f(base.bodyLarge),
      bodyMedium: f(base.bodyMedium),
      bodySmall: f(base.bodySmall),
      labelLarge: f(base.labelLarge),
      labelMedium: f(base.labelMedium),
      labelSmall: f(base.labelSmall),
    );
  }
}

/// Loads fonts from Google Fonts. Unknown families fall back to the
/// platform font rather than crashing the app.
class GoogleFontResolver implements FontResolver {
  const GoogleFontResolver();

  @override
  TextStyle style(String family, [TextStyle? base]) {
    try {
      return GoogleFonts.getFont(family, textStyle: base);
    } on Object {
      // google_fonts throws an Exception or ArgumentError for unknown names.
      return base ?? const TextStyle();
    }
  }
}

/// Ignores the family and uses the platform font. Used in tests, where
/// fonts can't be downloaded.
class PlatformFontResolver implements FontResolver {
  const PlatformFontResolver();

  @override
  TextStyle style(String family, [TextStyle? base]) =>
      base ?? const TextStyle();
}
