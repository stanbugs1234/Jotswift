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
/// Where the panel sits along its edge (-1 top to 1 bottom), and whether
/// it's tucked away to a small tab. Kept on the device.
class PenRailPlacementController extends Notifier<({double y, bool hidden})> {
  static const _yKey = 'penPanelY', _hiddenKey = 'penPanelHidden';

  @override
  ({double y, bool hidden}) build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return (
      y: (prefs.getDouble(_yKey) ?? 0).clamp(-1.0, 1.0),
      hidden: prefs.getBool(_hiddenKey) ?? false,
    );
  }

  /// Moves the panel while it's dragged; [save] keeps it there.
  void moveTo(double y) =>
      state = (y: y.clamp(-1.0, 1.0), hidden: state.hidden);

  void save() => ref.read(sharedPreferencesProvider).setDouble(_yKey, state.y);

  void setHidden(bool hidden) {
    state = (y: state.y, hidden: hidden);
    ref.read(sharedPreferencesProvider).setBool(_hiddenKey, hidden);
  }
}

final penRailPlacementProvider =
    NotifierProvider<PenRailPlacementController, ({double y, bool hidden})>(
      PenRailPlacementController.new,
    );

/// The pen's types, width, colors and saved pens in a slim panel floating
/// at the side of the page, like an art app's sidebar: one tap to change
/// any of them while writing. Shown for the pen, highlighter and eraser;
/// it can be dragged along its edge, or tucked away to a tab.
class PenRail extends ConsumerStatefulWidget {
  const PenRail({super.key});

  /// Screens narrower than this (phones) keep pen options in the toolbar.
  static const minShortestSide = 600.0;

  static const width = 60.0;

  @override
  ConsumerState<PenRail> createState() => _PenRailState();
}

class _PenRailState extends ConsumerState<PenRail> {
  final _panel = GlobalKey();

  static const _inset = 10.0;

  /// Moves the panel by [dy] pixels within [height].
  void _drag(double dy, double height) {
    final panel = _panel.currentContext?.size?.height ?? 0;
    final room = height - 2 * _inset - panel;
    if (room <= 0) return;
    final placement = ref.read(penRailPlacementProvider.notifier);
    placement.moveTo(ref.read(penRailPlacementProvider).y + dy * 2 / room);
  }

  @override
  Widget build(BuildContext context) {
    if (!showsPenRail(context, ref)) return const SizedBox.shrink();
    final left = ref.watch(penPanelSideProvider) == PenPanelSide.left;
    final placement = ref.watch(penRailPlacementProvider);
    final kind = ref.watch(inkToolProvider.select((t) => t.kind));
    final shown = switch (kind) {
      InkToolKind.pen || InkToolKind.highlighter || InkToolKind.eraser => true,
      _ => false,
    };
    final places = ref.read(penRailPlacementProvider.notifier);
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        void onDrag(DragUpdateDetails d) => _drag(d.delta.dy, height);
        void onDragEnd(DragEndDetails _) => places.save();
        return Align(
          alignment: Alignment(left ? -1 : 1, placement.y),
          child: Padding(
            padding: const EdgeInsets.all(_inset),
            // Slides away for tools without pen options (select, lasso,
            // laser).
            child: KeyedSubtree(
              key: _panel,
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
                child: !shown
                    ? const SizedBox.shrink()
                    : placement.hidden
                    ? _RailTab(
                        key: const ValueKey('tab'),
                        onShow: () => places.setHidden(false),
                        onDrag: onDrag,
                        onDragEnd: onDragEnd,
                      )
                    // One panel for every tool: its contents change in
                    // place, so a panel fading out never shows the new
                    // tool's.
                    : _RailBody(
                        key: const ValueKey('panel'),
                        left: left,
                        handle: _RailHandle(
                          onHide: () => places.setHidden(true),
                          onDrag: onDrag,
                          onDragEnd: onDragEnd,
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The grip at the top of the panel: drag to move it, tap to tuck it away.
class _RailHandle extends StatelessWidget {
  const _RailHandle({
    required this.onHide,
    required this.onDrag,
    required this.onDragEnd,
  });

  final VoidCallback onHide;
  final GestureDragUpdateCallback onDrag;
  final GestureDragEndCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Hide pen panel · drag to move it',
      child: Semantics(
        button: true,
        label: 'Hide pen panel',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onHide,
          onVerticalDragUpdate: onDrag,
          onVerticalDragEnd: onDragEnd,
          child: SizedBox(
            width: PenRail.width,
            height: 28,
            child: Center(
              child: Container(
                width: 24,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The panel tucked away: a small tab with the pen's color. Tap to bring
/// the panel back; drag to move it.
class _RailTab extends ConsumerWidget {
  const _RailTab({
    required this.onShow,
    required this.onDrag,
    required this.onDragEnd,
    super.key,
  });

  final VoidCallback onShow;
  final GestureDragUpdateCallback onDrag;
  final GestureDragEndCallback onDragEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final tool = ref.watch(inkToolProvider);
    final ink = tool.colorFrom(NotelySkin.of(context).inkColors);
    return Tooltip(
      message: 'Show pen panel',
      child: Semantics(
        button: true,
        label: 'Show pen panel',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onShow,
          onVerticalDragUpdate: onDrag,
          onVerticalDragEnd: onDragEnd,
          child: Material(
            color: scheme.surfaceContainerHigh,
            elevation: 3,
            shadowColor: Colors.black45,
            borderRadius: BorderRadius.circular(PenRail.width / 2),
            child: SizedBox(
              width: 44,
              height: 64,
              child: Center(
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: tool.kind == InkToolKind.eraser ? null : ink,
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.outline, width: 1.5),
                  ),
                  child: tool.kind == InkToolKind.eraser
                      ? Icon(
                          Icons.auto_fix_normal,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailBody extends ConsumerWidget {
  const _RailBody({required this.left, required this.handle, super.key});

  final bool left;

  /// The grip at the top.
  final Widget handle;

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
          padding: const EdgeInsets.only(bottom: 10),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                handle,
                if (tool.kind == InkToolKind.pen) ...[
                  for (final style in PenStyle.values)
                    _StyleButton(style: style),
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

/// The pen's (or highlighter's) width, and the pen's opacity: upright
/// sliders under a dot drawn as the line will be.
class _WidthSlider extends ConsumerWidget {
  const _WidthSlider();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final tool = ref.watch(inkToolProvider);
    final tools = ref.read(inkToolProvider.notifier);
    final highlighter = tool.kind == InkToolKind.highlighter;
    final range = highlighter
        ? InkToolState.highlighterRange
        : InkToolState.penRange;
    final width = tool.size.clamp(range.min, range.max);
    final share = (width - range.min) / (range.max - range.min);
    final ink = tool.colorFrom(NotelySkin.of(context).inkColors);
    final dot = 4 + share * 24;
    final small = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: scheme.onSurfaceVariant);
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
                color: ink.withValues(
                  alpha: highlighter ? 0.45 : tool.penOpacity,
                ),
                // An outline so dark ink shows on a dark panel.
                border: Border.all(color: scheme.outline),
                shape: highlighter ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: highlighter ? BorderRadius.circular(2) : null,
              ),
            ),
          ),
        ),
        _RailSlider(
          label: highlighter ? 'Highlighter width' : 'Pen width',
          height: highlighter ? 150 : 120,
          min: range.min,
          max: range.max,
          value: width,
          onChanged: tools.setWidth,
        ),
        Text(width.toStringAsFixed(width < 10 ? 1 : 0), style: small),
        if (highlighter)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: IconButton(
              tooltip: 'Straight lines',
              isSelected: tool.straightHighlighter,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              style: IconButton.styleFrom(
                backgroundColor: tool.straightHighlighter
                    ? scheme.primary.withValues(alpha: 0.14)
                    : null,
              ),
              icon: Icon(
                Icons.horizontal_rule,
                color: tool.straightHighlighter ? scheme.primary : null,
              ),
              onPressed: () =>
                  tools.setStraightHighlighter(!tool.straightHighlighter),
            ),
          )
        else ...[
          const SizedBox(height: 12),
          _RailSlider(
            label: 'Pen opacity',
            height: 90,
            min: InkToolState.minOpacity,
            max: 1,
            value: tool.penOpacity,
            onChanged: tools.setPenOpacity,
          ),
          Text('${(tool.penOpacity * 100).round()}%', style: small),
        ],
      ],
    );
  }
}

/// An upright slider, low at the bottom, as in an art app's sidebar.
class _RailSlider extends StatelessWidget {
  const _RailSlider({
    required this.label,
    required this.height,
    required this.min,
    required this.max,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double height;
  final double min;
  final double max;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      child: Tooltip(
        message: label,
        child: SizedBox(
          height: height,
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
                min: min,
                max: max,
                value: value.clamp(min, max),
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ),
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
        const EyedropperButton(),
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
      opacity: highlighter ? 1 : tool.penOpacity,
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
