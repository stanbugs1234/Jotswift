import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/input/finger_drawing.dart';
import '../../core/skins/notely_skin.dart';
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
  // The full toolbar is about 1020 wide (1070 with Paste), so an upright
  // iPad (820) folds too.
  static const compactWidth = 1110.0;

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

/// The ink colors and the three sizes.
class _PenOptions extends ConsumerWidget {
  const _PenOptions({this.wrap = false});

  /// Lay out in rows (in the pop-up) instead of one line.
  final bool wrap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tool = ref.watch(inkToolProvider);
    final tools = ref.read(inkToolProvider.notifier);
    final skin = NotelySkin.of(context);
    final scheme = Theme.of(context).colorScheme;
    final colors = [
      for (final (i, color) in skin.inkColors.indexed)
        _ColorDot(
          color: color,
          selected: i == tool.colorIndex,
          onTap: () => tools.selectColor(i),
          label: 'Ink color ${i + 1}',
        ),
    ];
    final sizes = [
      for (var i = 0; i < 3; i++)
        IconButton(
          tooltip: const ['Thin', 'Medium', 'Thick'][i],
          isSelected: i == tool.sizeIndex,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          icon: Container(
            width: 6.0 + i * 5,
            height: 6.0 + i * 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i == tool.sizeIndex
                  ? scheme.primary
                  : scheme.onSurface.withValues(alpha: 0.45),
            ),
          ),
          onPressed: () => tools.selectSize(i),
        ),
    ];
    if (wrap) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(children: colors),
          Row(mainAxisSize: MainAxisSize.min, children: sizes),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [...colors, const _Divider(), ...sizes],
    );
  }
}

/// One button showing the current color, opening colors and sizes.
class _PenOptionsButton extends ConsumerWidget {
  const _PenOptionsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tool = ref.watch(inkToolProvider);
    final colors = NotelySkin.of(context).inkColors;
    final color = colors[tool.colorIndex.clamp(0, colors.length - 1)];
    return MenuAnchor(
      menuChildren: const [
        Padding(padding: EdgeInsets.all(8), child: _PenOptions(wrap: true)),
      ],
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
