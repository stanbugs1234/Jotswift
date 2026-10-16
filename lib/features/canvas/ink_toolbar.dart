import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/input/finger_drawing.dart';
import '../../core/skins/notely_skin.dart';
import 'domain/stroke.dart';
import 'ink_tools.dart';
import 'lasso.dart';
import 'page_items.dart';
import 'stickers.dart';

/// The page tools: a finger toggle, pen, highlighter, eraser, select, lasso,
/// paste (after copying), text, photos, stickers, colors, sizes, undo and
/// redo. On narrow screens the
/// colors and sizes fold into one "Pen options" button.
class InkToolbar extends ConsumerWidget {
  const InkToolbar({required this.pageId, this.inkEnabled = true, super.key});

  final String pageId;

  /// False on the web: only text, photos, stickers, undo and redo.
  final bool inkEnabled;

  /// Below this width, colors and sizes go into a pop-up.
  // The full toolbar is about 1150 wide before saved pens (which scroll),
  // so an upright iPad (820) folds too.
  static const compactWidth = 1170.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tool = ref.watch(inkToolProvider);
    final tools = ref.read(inkToolProvider.notifier);
    final history = ref.watch(inkHistoryProvider(pageId));
    final historyActions = ref.read(inkHistoryProvider(pageId).notifier);
    final scheme = Theme.of(context).colorScheme;
    final canPaste = ref.watch(inkClipboardProvider) != null;

    Widget toolButton(InkToolKind kind, IconData icon, String label) {
      final selected = tool.kind == kind;
      return _ToolButton(
        tooltip: label,
        icon: icon,
        selected: selected,
        onPressed: () => tools.selectTool(kind),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < compactWidth;
        return Material(
          color: scheme.surface,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                if (inkEnabled) ...[
                  const FingerToggle(),
                  const _Divider(),
                  toolButton(InkToolKind.pen, Icons.edit, 'Pen'),
                  toolButton(
                    InkToolKind.highlighter,
                    Icons.highlight,
                    'Highlighter',
                  ),
                  toolButton(
                    InkToolKind.eraser,
                    Icons.auto_fix_normal,
                    'Eraser',
                  ),
                  toolButton(
                    InkToolKind.select,
                    Icons.near_me_outlined,
                    'Select',
                  ),
                  toolButton(InkToolKind.lasso, Icons.highlight_alt, 'Lasso'),
                  if (canPaste)
                    _ToolButton(
                      tooltip: 'Paste',
                      icon: Icons.content_paste,
                      selected: false,
                      onPressed: () => ref
                          .read(pasteRequestProvider(pageId).notifier)
                          .request(),
                    ),
                ],
                _ToolButton(
                  tooltip: 'Text',
                  icon: Icons.text_fields,
                  selected: false,
                  onPressed: () => addTextBox(context, ref, pageId),
                ),
                _ToolButton(
                  tooltip: 'Photo',
                  icon: Icons.add_photo_alternate_outlined,
                  selected: false,
                  onPressed: () => addPhoto(context, ref, pageId),
                ),
                _ToolButton(
                  tooltip: 'Stickers',
                  icon: Icons.emoji_emotions_outlined,
                  selected: false,
                  onPressed: () => showStickerTray(context, pageId),
                ),
                if (inkEnabled) ...[
                  const _Divider(),
                  if (compact)
                    const _PenOptionsButton()
                  else
                    const _PenOptions(),
                ],
                const _Divider(),
                _ToolButton(
                  tooltip: 'Undo',
                  icon: Icons.undo,
                  selected: false,
                  onPressed: history.canUndo ? historyActions.undo : null,
                ),
                _ToolButton(
                  tooltip: 'Redo',
                  icon: Icons.redo,
                  selected: false,
                  onPressed: history.canRedo ? historyActions.redo : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Whether fingers draw or scroll. Tapping it overrides the device's
/// setting on this device; Settings can return to following the device.
class FingerToggle extends ConsumerWidget {
  const FingerToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draws = ref.watch(fingersDrawProvider);
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: draws
          ? 'Fingers draw · tap so fingers scroll'
          : 'Fingers scroll · tap to draw with a finger',
      child: Semantics(
        button: true,
        toggled: draws,
        label: 'Draw with finger',
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => ref
              .read(fingerDrawingProvider.notifier)
              .set(draws ? FingerDrawing.off : FingerDrawing.on),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: draws ? scheme.primary.withValues(alpha: 0.15) : null,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: scheme.outline.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  draws ? Icons.draw_outlined : Icons.pan_tool_outlined,
                  size: 20,
                  color: draws ? scheme.primary : scheme.onSurface,
                ),
                const SizedBox(width: 6),
                Text(
                  draws ? 'Finger draws' : 'Finger scrolls',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: draws ? scheme.primary : scheme.onSurface,
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

/// A 44 pt tool button with a filled background when selected.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      isSelected: selected,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      style: IconButton.styleFrom(
        backgroundColor: selected ? scheme.primary : null,
      ),
      icon: Icon(icon, color: selected ? scheme.onPrimary : null),
      onPressed: onPressed,
    );
  }
}

/// The ink colors and the three sizes, then the pen settings and saved
/// pens. In the pop-up ([wrap]), everything in one panel.
class _PenOptions extends ConsumerWidget {
  const _PenOptions({this.wrap = false});

  /// Lay out as one panel (in the pop-up) instead of one line.
  final bool wrap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (wrap) return const _PenPanel(withSizes: true);
    final favorites = ref.watch(penFavoritesProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Palette(),
        const _Divider(),
        const _SizePresets(),
        MenuAnchor(
          menuChildren: const [_PenPanel(withSizes: false)],
          builder: (context, controller, _) => IconButton(
            tooltip: 'Pen settings',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: const Icon(Icons.tune),
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
          ),
        ),
        if (favorites.isNotEmpty) ...[
          const _Divider(),
          for (final (i, pen) in favorites.indexed)
            _FavoriteDot(pen: pen, index: i),
        ],
      ],
    );
  }
}

/// The skin's ink colors, the custom color if one is chosen, and a button
/// for every other color.
class _Palette extends ConsumerWidget {
  const _Palette({this.wrap = false});

  final bool wrap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tool = ref.watch(inkToolProvider);
    final tools = ref.read(inkToolProvider.notifier);
    final skin = NotelySkin.of(context);
    final custom = tool.customColor;
    final children = [
      for (final (i, color) in skin.inkColors.indexed)
        _ColorDot(
          color: color,
          selected: custom == null && i == tool.colorIndex,
          onTap: () => tools.selectColor(i),
          label: 'Ink color ${i + 1}',
        ),
      if (custom != null)
        _ColorDot(
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
            tool.colorFrom(skin.inkColors),
          );
          if (picked != null) tools.selectCustomColor(picked);
        },
      ),
    ];
    return wrap
        ? Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: children,
          )
        : Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

class _SizePresets extends ConsumerWidget {
  const _SizePresets();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tool = ref.watch(inkToolProvider);
    final tools = ref.read(inkToolProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final custom = switch (tool.kind) {
      InkToolKind.highlighter => tool.highlighterWidth,
      InkToolKind.eraser => null,
      _ => tool.penWidth,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          IconButton(
            tooltip: const ['Thin', 'Medium', 'Thick'][i],
            isSelected: custom == null && i == tool.sizeIndex,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: Container(
              width: 6.0 + i * 5,
              height: 6.0 + i * 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: custom == null && i == tool.sizeIndex
                    ? scheme.primary
                    : scheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
            onPressed: () => tools.selectSize(i),
          ),
      ],
    );
  }
}

/// Pen type, width, colors (with [withSizes], also the presets) and saved
/// pens.
class _PenPanel extends ConsumerWidget {
  const _PenPanel({required this.withSizes});

  final bool withSizes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tool = ref.watch(inkToolProvider);
    final tools = ref.read(inkToolProvider.notifier);
    final skin = NotelySkin.of(context);
    final favorites = ref.watch(penFavoritesProvider);
    final text = Theme.of(context).textTheme;
    final highlighter = tool.kind == InkToolKind.highlighter;
    final range = highlighter
        ? InkToolState.highlighterRange
        : InkToolState.penRange;
    final width = tool.kind == InkToolKind.eraser
        ? null
        : tool.size.clamp(range.min, range.max);
    final current = PenFavorite(
      tool: highlighter ? InkTool.highlighter : InkTool.pen,
      style: highlighter ? PenStyle.fountain : tool.penStyle,
      color: tool.colorFrom(skin.inkColors).toARGB32(),
      width: tool.kind == InkToolKind.eraser
          ? InkToolState.penSizes[1]
          : tool.size,
    );

    Widget heading(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
      child: Text(label, style: text.labelMedium),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!highlighter && tool.kind != InkToolKind.eraser) ...[
              heading('Pen type'),
              SegmentedButton<PenStyle>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: PenStyle.ballpoint, label: Text('Ball')),
                  ButtonSegment(
                    value: PenStyle.fountain,
                    label: Text('Fountain'),
                  ),
                  ButtonSegment(value: PenStyle.brush, label: Text('Brush')),
                  ButtonSegment(value: PenStyle.pencil, label: Text('Pencil')),
                ],
                selected: {tool.penStyle},
                onSelectionChanged: (s) => tools.selectPenStyle(s.single),
              ),
            ],
            if (tool.kind == InkToolKind.eraser) ...[
              heading('Eraser'),
              SegmentedButton<EraserMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: EraserMode.stroke,
                    label: Text('Whole strokes'),
                  ),
                  ButtonSegment(
                    value: EraserMode.partial,
                    label: Text('Partial'),
                  ),
                ],
                selected: {tool.eraserMode},
                onSelectionChanged: (s) => tools.setEraserMode(s.single),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Highlighter only'),
                value: tool.eraseHighlighterOnly,
                onChanged: tools.setEraseHighlighterOnly,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Back to the pen after erasing'),
                value: tool.eraserReturns,
                onChanged: tools.setEraserReturns,
              ),
            ] else ...[
              heading('Color'),
              const _Palette(wrap: true),
            ],
            if (withSizes) ...[heading('Size'), const _SizePresets()],
            if (width != null) ...[
              heading('Width  ${width.toStringAsFixed(1)}'),
              Slider(
                min: range.min,
                max: range.max,
                value: width,
                label: width.toStringAsFixed(1),
                onChanged: tools.setWidth,
              ),
            ],
            if (tool.kind != InkToolKind.eraser) heading('Saved pens'),
            if (tool.kind != InkToolKind.eraser)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final (i, pen) in favorites.indexed)
                    InputChip(
                      avatar: _PenSwatch(pen: pen, size: 18),
                      label: Text(_penName(pen)),
                      tooltip: 'Use saved pen ${i + 1}',
                      onPressed: () => tools.useFavorite(pen),
                      onDeleted: () => ref
                          .read(penFavoritesSettingProvider.notifier)
                          .remove(pen),
                      deleteButtonTooltipMessage: 'Remove saved pen',
                    ),
                  if (tool.kind != InkToolKind.eraser &&
                      !favorites.contains(current))
                    ActionChip(
                      avatar: const Icon(Icons.star_outline, size: 18),
                      label: const Text('Save this pen'),
                      onPressed: () => ref
                          .read(penFavoritesSettingProvider.notifier)
                          .add(current),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

String _penName(PenFavorite pen) => pen.tool == InkTool.highlighter
    ? 'Highlighter'
    : switch (pen.style) {
        PenStyle.ballpoint => 'Ball',
        PenStyle.fountain => 'Fountain',
        PenStyle.brush => 'Brush',
        PenStyle.pencil => 'Pencil',
      };

/// A saved pen's color, with its width as the dot's size.
class _PenSwatch extends StatelessWidget {
  const _PenSwatch({required this.pen, required this.size});

  final PenFavorite pen;
  final double size;

  @override
  Widget build(BuildContext context) {
    final range = pen.tool == InkTool.highlighter
        ? InkToolState.highlighterRange
        : InkToolState.penRange;
    final share = ((pen.width - range.min) / (range.max - range.min)).clamp(
      0.0,
      1.0,
    );
    final dot = size * (0.45 + 0.55 * share);
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Container(
          width: dot,
          height: dot,
          decoration: BoxDecoration(
            color: Color(pen.color)
                .withValues(alpha: pen.tool == InkTool.highlighter ? 0.5 : 1),
            shape: pen.tool == InkTool.highlighter
                ? BoxShape.rectangle
                : BoxShape.circle,
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
        ),
      ),
    );
  }
}

/// A saved pen in the toolbar: tap to use it.
class _FavoriteDot extends ConsumerWidget {
  const _FavoriteDot({required this.pen, required this.index});

  final PenFavorite pen;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tool = ref.watch(inkToolProvider);
    final skin = NotelySkin.of(context);
    final active =
        (tool.kind == InkToolKind.highlighter) ==
            (pen.tool == InkTool.highlighter) &&
        tool.kind != InkToolKind.eraser &&
        tool.colorFrom(skin.inkColors).toARGB32() == pen.color &&
        (tool.size - pen.width).abs() < 0.05 &&
        (pen.tool == InkTool.highlighter || tool.penStyle == pen.style);
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: 'Saved pen ${index + 1}: ${_penName(pen)}',
      isSelected: active,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
      style: IconButton.styleFrom(
        backgroundColor: active ? scheme.primary.withValues(alpha: 0.15) : null,
      ),
      icon: _PenSwatch(pen: pen, size: 24),
      onPressed: () => ref.read(inkToolProvider.notifier).useFavorite(pen),
    );
  }
}

/// One button showing the current color, opening the pen panel.
class _PenOptionsButton extends ConsumerWidget {
  const _PenOptionsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tool = ref.watch(inkToolProvider);
    final color = tool.colorFrom(NotelySkin.of(context).inkColors);
    return MenuAnchor(
      menuChildren: const [_PenOptions(wrap: true)],
      builder: (context, controller, _) => IconButton(
        tooltip: 'Pen options',
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        icon: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// Every color: twelve hues in five shades, grays, and a hex code.
Future<Color?> showInkColorPicker(BuildContext context, Color initial) =>
    showDialog<Color>(
      context: context,
      builder: (context) => _ColorPickerDialog(initial: initial),
    );

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initial});

  final Color initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late final _hex = TextEditingController(text: _toHex(widget.initial));
  String? _error;

  static String _toHex(Color c) =>
      (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  static final palette = [
    for (final lightness in [0.82, 0.68, 0.52, 0.38, 0.24])
      for (var hue = 0.0; hue < 360; hue += 30)
        HSLColor.fromAHSL(1, hue, 0.75, lightness).toColor(),
    for (var i = 0; i < 12; i++)
      Color.lerp(const Color(0xFFFFFFFF), const Color(0xFF000000), i / 11)!,
  ];

  void _useHex() {
    final text = _hex.text.trim().replaceFirst('#', '');
    final value = int.tryParse(text, radix: 16);
    if (text.length != 6 || value == null) {
      setState(() => _error = 'Six digits, like 1E88E5');
      return;
    }
    Navigator.of(context).pop(Color(0xFF000000 | value));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Colors'),
      content: SizedBox(
        width: 12 * 30,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GridView.count(
              crossAxisCount: 12,
              shrinkWrap: true,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              children: [
                for (final c in palette)
                  Semantics(
                    button: true,
                    label: 'Color ${_toHex(c)}',
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(c),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: c,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: scheme.outline.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _hex,
              decoration: InputDecoration(
                labelText: 'Hex code',
                prefixText: '#',
                errorText: _error,
              ),
              onSubmitted: (_) => _useHex(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _useHex, child: const Text('Use hex')),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
    required this.label,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? scheme.primary : scheme.outline,
                width: selected ? 3 : 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: 28, child: VerticalDivider(width: 16));
}
