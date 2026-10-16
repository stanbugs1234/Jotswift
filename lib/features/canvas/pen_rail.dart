import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/synced_setting.dart';
import '../../core/skins/notely_skin.dart';
import 'domain/stroke.dart';
import 'ink_toolbar.dart';
import 'ink_tools.dart';
import 'stroke_painter.dart';

/// Where the pen's colors, sizes and types are: a panel at one side of the
/// page (on a tablet), or in the toolbar.
enum PenPanelSide { left, right, toolbar }

class PenPanelSideController extends Notifier<PenPanelSide> {
  static const _prefsKey = 'penPanelSide';

  @override
  PenPanelSide build() {
    final saved = ref.watch(sharedPreferencesProvider).getString(_prefsKey);
    return PenPanelSide.values.asNameMap()[saved] ?? PenPanelSide.left;
  }

  Future<void> set(PenPanelSide side) async {
    state = side;
    await ref.read(sharedPreferencesProvider).setString(_prefsKey, side.name);
  }
}

final penPanelSideProvider =
    NotifierProvider<PenPanelSideController, PenPanelSide>(
      PenPanelSideController.new,
    );

/// Whether pages show the [PenRail]: on a tablet, unless the user keeps
/// the pen options in the toolbar. Phones have no room beside the page.
bool showsPenRail(BuildContext context, WidgetRef ref) =>
    ref.watch(penPanelSideProvider) != PenPanelSide.toolbar &&
    MediaQuery.sizeOf(context).shortestSide >= PenRail.minShortestSide;

/// The pen's types, width, colors and saved pens in a slim panel floating
/// at the side of the page, like an art app's sidebar: one tap to change
/// any of them while writing. Shown for the pen, highlighter and eraser.
class PenRail extends ConsumerWidget {
  const PenRail({super.key});

  /// Screens narrower than this (phones) keep pen options in the toolbar.
  static const minShortestSide = 600.0;

  static const width = 60.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!showsPenRail(context, ref)) return const SizedBox.shrink();
    final left = ref.watch(penPanelSideProvider) == PenPanelSide.left;
    final kind = ref.watch(inkToolProvider.select((t) => t.kind));
    final shown = switch (kind) {
      InkToolKind.pen || InkToolKind.highlighter || InkToolKind.eraser => true,
      _ => false,
    };
    return Align(
      alignment: left ? Alignment.centerLeft : Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.all(10),
        // Slides away for tools without pen options (select, lasso, laser).
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: Offset(left ? -0.4 : 0.4, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: shown
              ? _RailBody(key: ValueKey(kind), left: left)
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _RailBody extends ConsumerWidget {
  const _RailBody({required this.left, super.key});

  final bool left;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final tool = ref.watch(inkToolProvider);
    final eraser = tool.kind == InkToolKind.eraser;

    const divider = Divider(height: 17, indent: 12, endIndent: 12);
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 3,
      shadowColor: Colors.black45,
      borderRadius: BorderRadius.circular(PenRail.width / 2),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: PenRail.width,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tool.kind == InkToolKind.pen) ...[
                for (final style in PenStyle.values) _StyleButton(style: style),
                divider,
              ],
              if (eraser) const _EraserSizes() else const _WidthSlider(),
              if (!eraser) ...[divider, const _Colors(), const _SavedPens()],
              divider,
              PenMenu(
                // Opens beside the panel, not over it.
                alignmentOffset: Offset(left ? PenRail.width : -348, -52),
                menuChildren: const [PenPanel(withSizes: false)],
                builder: (context, onPressed) => IconButton(
                  tooltip: eraser ? 'Eraser settings' : 'Pen settings',
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  icon: const Icon(Icons.tune),
                  onPressed: onPressed,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A pen type, shown as a stroke written with it.
class _StyleButton extends ConsumerWidget {
  const _StyleButton({required this.style});

  final PenStyle style;

  static String label(PenStyle style) => switch (style) {
    PenStyle.ballpoint => 'Ballpoint',
    PenStyle.fountain => 'Fountain pen',
    PenStyle.brush => 'Brush pen',
    PenStyle.pencil => 'Pencil',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final tool = ref.watch(inkToolProvider);
    final selected = tool.penStyle == style;
    return Tooltip(
      message: label(style),
      child: Semantics(
        button: true,
        selected: selected,
        label: label(style),
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () =>
                ref.read(inkToolProvider.notifier).selectPenStyle(style),
            child: Ink(
              width: 48,
              height: 36,
              decoration: BoxDecoration(
                color: selected ? scheme.primary.withValues(alpha: 0.14) : null,
                borderRadius: BorderRadius.circular(12),
                border: selected
                    ? Border.all(color: scheme.primary, width: 1.5)
                    : null,
              ),
              // In the panel's text color, not the ink's: dark ink would vanish
              // on a dark panel, and the color has its own place below.
              child: CustomPaint(
                painter: _StyleSample(
                  style,
                  selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A short wave written with [style], pressure rising then falling, so
/// each type's character (even, thick-thin, tapered, grainy) shows.
class _StyleSample extends CustomPainter {
  _StyleSample(this.style, this.color);

  final PenStyle style;
  final Color color;

  /// Drawn at this size, then scaled to fit, so the pencil's grain and the
  /// brush's taper look as they do on a page.
  static const _box = Size(120, 80);

  static final _points = [
    for (var i = 0; i <= 40; i++)
      () {
        final t = i / 40;
        return InkPoint(
          14 + t * 92,
          40 - math.sin(t * 2 * math.pi) * 18,
          0.25 + 0.7 * math.sin(t * math.pi),
        );
      }(),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / _box.width, size.height / _box.height);
    canvas
      ..save()
      ..translate(
        (size.width - _box.width * scale) / 2,
        (size.height - _box.height * scale) / 2,
      )
      ..scale(scale);
    final stroke = Stroke(
      id: 'sample',
      tool: InkTool.pen,
      color: color.toARGB32(),
      width: 9,
      points: _points,
      createdAt: 0,
      pressureSensitive: true,
      style: style,
    );
    canvas
      ..drawPath(
        StrokeRenderer.buildPath(stroke, complete: true),
        StrokeRenderer.paintFor(stroke),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_StyleSample old) =>
      old.style != style || old.color != color;
}

/// The pen's (or highlighter's) width: an upright slider under a dot as
/// wide as the line.
class _WidthSlider extends ConsumerWidget {
  const _WidthSlider();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final tool = ref.watch(inkToolProvider);
    final highlighter = tool.kind == InkToolKind.highlighter;
    final range = highlighter
        ? InkToolState.highlighterRange
        : InkToolState.penRange;
    final width = tool.size.clamp(range.min, range.max);
    final share = (width - range.min) / (range.max - range.min);
    final ink = tool.colorFrom(NotelySkin.of(context).inkColors);
    final dot = 4 + share * 24;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 32,
          child: Center(
            child: Container(
              width: highlighter ? dot * 0.7 : dot,
              height: dot,
              decoration: BoxDecoration(
                color: highlighter ? ink.withValues(alpha: 0.45) : ink,
                // An outline so dark ink shows on a dark panel.
                border: Border.all(color: scheme.outline),
                shape: highlighter ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: highlighter ? BorderRadius.circular(2) : null,
              ),
            ),
          ),
        ),
        Semantics(
          label: highlighter ? 'Highlighter width' : 'Pen width',
          child: SizedBox(
            height: 150,
            width: PenRail.width,
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  activeTrackColor: scheme.primary,
                  inactiveTrackColor: scheme.outlineVariant,
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  min: range.min,
                  max: range.max,
                  value: width,
                  onChanged: ref.read(inkToolProvider.notifier).setWidth,
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            width.toStringAsFixed(width < 10 ? 1 : 0),
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// The eraser's three sizes.
class _EraserSizes extends ConsumerWidget {
  const _EraserSizes();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final tool = ref.watch(inkToolProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          IconButton(
            tooltip: const ['Small eraser', 'Medium eraser', 'Large eraser'][i],
            isSelected: i == tool.sizeIndex,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            style: IconButton.styleFrom(
              backgroundColor: i == tool.sizeIndex
                  ? scheme.primary.withValues(alpha: 0.14)
                  : null,
            ),
            icon: Container(
              width: 8.0 + i * 7,
              height: 8.0 + i * 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: i == tool.sizeIndex
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                  width: 1.5,
                ),
              ),
            ),
            onPressed: () => ref.read(inkToolProvider.notifier).selectSize(i),
          ),
      ],
    );
  }
}

/// The skin's ink colors in a column, the chosen color if it's another,
/// and every other color.
class _Colors extends ConsumerWidget {
  const _Colors();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tool = ref.watch(inkToolProvider);
    final tools = ref.read(inkToolProvider.notifier);
    final inkColors = NotelySkin.of(context).inkColors;
    final custom = tool.customColor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, color) in inkColors.indexed)
          InkColorDot(
            color: color,
            selected: custom == null && i == tool.colorIndex,
            onTap: () => tools.selectColor(i),
            label: 'Ink color ${i + 1}',
          ),
        if (custom != null)
          InkColorDot(
            color: Color(custom),
            selected: true,
            onTap: () {},
            label: 'Chosen color',
          ),
        IconButton(
          tooltip: 'More colors',
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          icon: const Icon(Icons.palette_outlined),
          onPressed: () async {
            final picked = await showInkColorPicker(
              context,
              tool.colorFrom(inkColors),
            );
            if (picked != null) tools.selectCustomColor(picked);
          },
        ),
      ],
    );
  }
}

/// Saved pens for this tool, and a star to save the current one.
class _SavedPens extends ConsumerWidget {
  const _SavedPens();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final tool = ref.watch(inkToolProvider);
    final inkColors = NotelySkin.of(context).inkColors;
    final highlighter = tool.kind == InkToolKind.highlighter;
    final current = PenFavorite(
      tool: highlighter ? InkTool.highlighter : InkTool.pen,
      style: highlighter ? PenStyle.fountain : tool.penStyle,
      color: tool.colorFrom(inkColors).toARGB32(),
      width: tool.size,
    );
    final favorites = ref.watch(penFavoritesProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (favorites.isNotEmpty)
          const Divider(height: 17, indent: 12, endIndent: 12),
        for (final (i, pen) in favorites.indexed)
          IconButton(
            tooltip: 'Saved pen ${i + 1}: ${penName(pen)}',
            isSelected: pen == current,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            style: IconButton.styleFrom(
              backgroundColor: pen == current
                  ? scheme.primary.withValues(alpha: 0.14)
                  : null,
            ),
            icon: PenSwatch(pen: pen, size: 26),
            onPressed: () =>
                ref.read(inkToolProvider.notifier).useFavorite(pen),
          ),
        if (!favorites.contains(current))
          IconButton(
            tooltip: 'Save this pen',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: const Icon(Icons.star_outline),
            onPressed: () =>
                ref.read(penFavoritesSettingProvider.notifier).add(current),
          ),
      ],
    );
  }
}
