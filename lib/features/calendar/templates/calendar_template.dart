import 'package:flutter/material.dart';

import '../../../core/motion/period_transition.dart';
import '../../../core/skins/font_resolver.dart';

/// How the lines between days are drawn.
enum CalendarGridLines { none, thin, dashed, hand }

/// How today is marked.
enum TodayMarker { pill, circle, square, underline, ring, star }

/// How events are drawn in the month grid.
enum EventLook { filled, outline, bar, dot }

/// Illustrations drawn above or around the month (see calendar_art.dart).
enum CalendarArt { none, wall, botanical, chalk, seasons }

/// A complete look for the Calendar: colours, fonts, lines, how today and
/// events are marked, an optional illustration, and the month animation
/// it comes with.
@immutable
class CalendarTemplate {
  const CalendarTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.animation,
    required this.background,
    required this.cell,
    required this.text,
    required this.muted,
    required this.grid,
    required this.accent,
    required this.onAccent,
    this.dark = false,
    this.weekend,
    this.weekdayColors,
    this.headingFont,
    this.bodyFont,
    this.gridLines = CalendarGridLines.thin,
    this.today = TodayMarker.pill,
    this.events = EventLook.filled,
    this.art = CalendarArt.none,
    this.bigMonthNumber = false,
    this.cornerRadius = 0,
    this.productId,
  });

  final String id;
  final String name;
  final String description;

  /// The month animation used when the user leaves it to the template.
  final PeriodAnimation animation;

  final bool dark;
  final Color background;

  /// Day cells and cards.
  final Color cell;
  final Color text;
  final Color muted;
  final Color grid;
  final Color accent;
  final Color onAccent;

  /// Saturday and Sunday cells, if tinted.
  final Color? weekend;

  /// A colour per weekday heading, Monday first (Pastel's rainbow).
  final List<Color>? weekdayColors;

  /// Google Fonts families; null keeps the app's.
  final String? headingFont;
  final String? bodyFont;

  final CalendarGridLines gridLines;
  final TodayMarker today;
  final EventLook events;
  final CalendarArt art;

  /// Show the month as a big number beside its name.
  final bool bigMonthNumber;

  /// Rounding of day cells.
  final double cornerRadius;

  /// The store product that unlocks it; null when it's free.
  final String? productId;

  bool get free => productId == null;

  /// The app's [base] theme recoloured for this template, so every
  /// Calendar view picks the look up through `Theme.of`.
  ThemeData theme(ThemeData base, FontResolver fonts) {
    final scheme = base.colorScheme.copyWith(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: accent,
      onPrimary: onAccent,
      surface: background,
      onSurface: text,
      surfaceContainerHighest: cell,
      surfaceContainerHigh: cell,
      surfaceContainer: cell,
      surfaceContainerLow: background,
      // Selected buttons and the New event button, tinted with the accent.
      primaryContainer: Color.alphaBlend(
        accent.withValues(alpha: dark ? 0.35 : 0.18),
        background,
      ),
      onPrimaryContainer: text,
      secondaryContainer: Color.alphaBlend(
        accent.withValues(alpha: dark ? 0.3 : 0.16),
        background,
      ),
      onSecondaryContainer: text,
      outline: muted,
      outlineVariant: grid,
    );
    var textTheme = base.textTheme.apply(bodyColor: text, displayColor: text);
    if (bodyFont case final f?) textTheme = fonts.textTheme(f, textTheme);
    if (headingFont case final f?) {
      TextStyle? h(TextStyle? s) => s == null ? null : fonts.style(f, s);
      textTheme = textTheme.copyWith(
        headlineSmall: h(textTheme.headlineSmall),
        titleLarge: h(textTheme.titleLarge),
        titleMedium: h(textTheme.titleMedium),
      );
    }
    return base.copyWith(
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      textTheme: textTheme,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: background,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
      ),
      dividerColor: grid,
      iconTheme: base.iconTheme.copyWith(color: text),
    );
  }

  @override
  bool operator ==(Object other) => other is CalendarTemplate && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Unlocks every paid template at once.
const calendarTemplatesBundle = 'bundle_calendar_templates';

const classicCalendar = CalendarTemplate(
  id: 'classic',
  name: 'Classic',
  description: 'Clean lines and filled event chips.',
  animation: PeriodAnimation.slide,
  background: Color(0xFFFBFBFD),
  cell: Color(0xFFFFFFFF),
  text: Color(0xFF1C1F26),
  muted: Color(0xFF8A90A0),
  grid: Color(0xFFDCE0E8),
  accent: Color(0xFF2C4A7C),
  onAccent: Color(0xFFFFFFFF),
);

/// Every template, free first.
const calendarTemplates = [
  classicCalendar,
  CalendarTemplate(
    id: 'minimal',
    name: 'Minimal',
    description: 'No lines, lots of space, thin event bars.',
    animation: PeriodAnimation.fade,
    background: Color(0xFFFFFFFF),
    cell: Color(0xFFFFFFFF),
    text: Color(0xFF222222),
    muted: Color(0xFFA6A6A6),
    grid: Color(0xFFF0F0F0),
    accent: Color(0xFF222222),
    onAccent: Color(0xFFFFFFFF),
    gridLines: CalendarGridLines.none,
    today: TodayMarker.underline,
    events: EventLook.bar,
    bodyFont: 'Inter',
  ),
  CalendarTemplate(
    id: 'night',
    name: 'Night',
    description: 'Dark and soft, with glowing event dots.',
    animation: PeriodAnimation.fade,
    dark: true,
    background: Color(0xFF14171F),
    cell: Color(0xFF1B1F2A),
    text: Color(0xFFE6E8EF),
    muted: Color(0xFF7D8496),
    grid: Color(0xFF2A3040),
    accent: Color(0xFF8FA5E0),
    onAccent: Color(0xFF14171F),
    today: TodayMarker.circle,
    events: EventLook.dot,
  ),
  CalendarTemplate(
    id: 'paper',
    name: 'Paper Planner',
    description: 'Cream paper, faint ruling and a hand-drawn ring for today.',
    animation: PeriodAnimation.pageTurn,
    background: Color(0xFFF6F0E3),
    cell: Color(0xFFFBF7EE),
    text: Color(0xFF2E2620),
    muted: Color(0xFF9A8C7A),
    grid: Color(0xFFDCCFB8),
    accent: Color(0xFF8A4B32),
    onAccent: Color(0xFFFFFFFF),
    headingFont: 'Fraunces',
    gridLines: CalendarGridLines.hand,
    today: TodayMarker.ring,
    events: EventLook.outline,
    productId: 'pack_calendar_paper',
  ),
  CalendarTemplate(
    id: 'wall',
    name: 'Wall Calendar',
    description: 'A new illustration every month above the grid.',
    animation: PeriodAnimation.wallFlip,
    background: Color(0xFFF4F1EC),
    cell: Color(0xFFFFFFFF),
    text: Color(0xFF26262B),
    muted: Color(0xFF8E8C88),
    grid: Color(0xFFE2DED6),
    accent: Color(0xFFC8553D),
    onAccent: Color(0xFFFFFFFF),
    headingFont: 'Fraunces',
    today: TodayMarker.circle,
    art: CalendarArt.wall,
    productId: 'pack_calendar_wall',
  ),
  CalendarTemplate(
    id: 'botanical',
    name: 'Botanical',
    description: 'Sage and terracotta with leafy corners.',
    animation: PeriodAnimation.pageTurn,
    background: Color(0xFFF3F1E8),
    cell: Color(0xFFFBF8F1),
    text: Color(0xFF2B2B2B),
    muted: Color(0xFF7D8577),
    grid: Color(0xFFCFD8C8),
    accent: Color(0xFF4F7B5A),
    onAccent: Color(0xFFFFFFFF),
    weekend: Color(0xFFF1EBDF),
    headingFont: 'Cormorant Garamond',
    today: TodayMarker.circle,
    art: CalendarArt.botanical,
    cornerRadius: 10,
    productId: 'pack_calendar_botanical',
  ),
  CalendarTemplate(
    id: 'pastel',
    name: 'Pastel',
    description: 'Soft rainbow weekdays, rounded chips and a star for today.',
    animation: PeriodAnimation.stack,
    background: Color(0xFFFFFBFD),
    cell: Color(0xFFFFFFFF),
    text: Color(0xFF3B3045),
    muted: Color(0xFF9488A3),
    grid: Color(0xFFEFE6F5),
    accent: Color(0xFF8E5BB5),
    onAccent: Color(0xFFFFFFFF),
    weekdayColors: [
      Color(0xFFF4A6A6),
      Color(0xFFF6BE9A),
      Color(0xFFF5D58E),
      Color(0xFFA6DCC6),
      Color(0xFF9FD0E8),
      Color(0xFFAFB8EC),
      Color(0xFFE6A8DA),
    ],
    bodyFont: 'Nunito',
    today: TodayMarker.star,
    cornerRadius: 14,
    productId: 'pack_calendar_pastel',
  ),
  CalendarTemplate(
    id: 'bold',
    name: 'Bold Modern',
    description: 'A huge month number, black and one bright accent.',
    animation: PeriodAnimation.cube,
    background: Color(0xFFFFFFFF),
    cell: Color(0xFFFFFFFF),
    text: Color(0xFF0E0E10),
    muted: Color(0xFF8B8B90),
    grid: Color(0xFF0E0E10),
    accent: Color(0xFFFF4F2E),
    onAccent: Color(0xFFFFFFFF),
    headingFont: 'Space Grotesk',
    today: TodayMarker.square,
    bigMonthNumber: true,
    productId: 'pack_calendar_bold',
  ),
  CalendarTemplate(
    id: 'chalkboard',
    name: 'Chalkboard',
    description: 'A green board with chalk lines and doodles.',
    animation: PeriodAnimation.wallFlip,
    dark: true,
    background: Color(0xFF2E4A3E),
    cell: Color(0xFF34523F),
    text: Color(0xFFF1EFE6),
    muted: Color(0xFFB9C4B5),
    grid: Color(0xFF6E8A7A),
    accent: Color(0xFFF6E7A1),
    onAccent: Color(0xFF2E4A3E),
    headingFont: 'Caveat',
    bodyFont: 'Patrick Hand',
    gridLines: CalendarGridLines.dashed,
    today: TodayMarker.ring,
    events: EventLook.outline,
    art: CalendarArt.chalk,
    productId: 'pack_calendar_chalkboard',
  ),
  CalendarTemplate(
    id: 'seasons',
    name: 'Seasons',
    description: 'Colours and art follow the season of each month.',
    animation: PeriodAnimation.carousel,
    background: Color(0xFFF7F5EF),
    cell: Color(0xFFFFFFFF),
    text: Color(0xFF2A2A2A),
    muted: Color(0xFF8C8A84),
    grid: Color(0xFFE4E0D6),
    accent: Color(0xFF4F7B5A),
    onAccent: Color(0xFFFFFFFF),
    today: TodayMarker.circle,
    art: CalendarArt.seasons,
    cornerRadius: 8,
    productId: 'pack_calendar_seasons',
  ),
];

/// The template with [id], or Classic.
CalendarTemplate calendarTemplateById(String id) =>
    calendarTemplates.where((t) => t.id == id).firstOrNull ?? classicCalendar;
