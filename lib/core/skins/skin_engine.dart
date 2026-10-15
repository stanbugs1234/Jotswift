import 'package:flutter/material.dart';

import 'font_resolver.dart';
import 'notely_skin.dart';
import 'skin_manifest.dart';

/// Builds a Flutter [ThemeData] (with a [NotelySkin] extension) from a skin.
class SkinEngine {
  const SkinEngine({this.fonts = const GoogleFontResolver()});

  final FontResolver fonts;

  ThemeData buildTheme(SkinManifest skin) {
    final c = skin.colors;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: c.primary,
          brightness: skin.brightness,
        ).copyWith(
          primary: c.primary,
          onPrimary: c.onPrimary,
          secondary: c.secondary,
          onSecondary: c.onSecondary,
          surface: c.surface,
          onSurface: c.onSurface,
          outline: c.outline,
          error: c.error,
        );

    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    // ThemeData.textTheme only has colors until Flutter adds sizes later, so
    // merge in the sizes now; styles copied below (e.g. the app bar title)
    // would otherwise lose them.
    final sized = Typography.englishLike2021.merge(base.textTheme);
    final bodyTheme = fonts.textTheme(skin.typography.body, sized);
    final textTheme = _withHeadingFont(bodyTheme, skin.typography.heading);
    final radius = BorderRadius.circular(skin.cornerRadius);
    final shape = RoundedRectangleBorder(borderRadius: radius);

    return base.copyWith(
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: c.onSurface),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        shape: shape,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.primary.withValues(alpha: 0.18),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.primary.withValues(alpha: 0.18),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: shape),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: shape),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: radius),
      ),
      dividerTheme: DividerThemeData(color: c.outline.withValues(alpha: 0.4)),
      extensions: [buildNotelySkin(skin)],
    );
  }

  /// The paper, ink palette and accent font of [skin], for pages drawn in
  /// it while the rest of the screen keeps the interface theme.
  NotelySkin buildNotelySkin(SkinManifest skin) => NotelySkin(
    id: skin.id,
    name: skin.name,
    paperColor: skin.paper.color,
    lineColor: skin.paper.lineColor,
    marginColor: skin.paper.marginColor,
    pattern: skin.paper.pattern,
    spacing: skin.paper.spacing,
    inkColors: skin.inkColors,
    accentTextStyle: fonts.style(
      skin.typography.accent,
      TextStyle(fontSize: 28, color: skin.colors.primary),
    ),
    cornerRadius: skin.cornerRadius,
  );

  /// Headings use the heading font; everything else keeps the body font.
  TextTheme _withHeadingFont(TextTheme theme, String family) {
    final headings = fonts.textTheme(family, theme);
    return theme.copyWith(
      displayLarge: headings.displayLarge,
      displayMedium: headings.displayMedium,
      displaySmall: headings.displaySmall,
      headlineLarge: headings.headlineLarge,
      headlineMedium: headings.headlineMedium,
      headlineSmall: headings.headlineSmall,
      titleLarge: headings.titleLarge,
    );
  }
}
