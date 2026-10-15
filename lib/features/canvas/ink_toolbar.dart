import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/skins/notely_skin.dart';
import 'ink_tools.dart';
import 'page_items.dart';
import 'stickers.dart';

/// Pen, highlighter, eraser, select, text, photos, stickers, colors,
/// sizes, hand mode, undo and redo.
class InkToolbar extends ConsumerWidget {
  const InkToolbar({required this.pageId, this.inkEnabled = true, super.key});

  final String pageId;

  /// False on the web: only text, photos, stickers, undo and redo.
  final bool inkEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tool = ref.watch(inkToolProvider);
    final tools = ref.read(inkToolProvider.notifier);
    final history = ref.watch(inkHistoryProvider(pageId));
    final historyActions = ref.read(inkHistoryProvider(pageId).notifier);
    final skin = NotelySkin.of(context);
    final scheme = Theme.of(context).colorScheme;

    Widget toolButton(InkToolKind kind, IconData icon, String label) {
      final selected = tool.drawMode && tool.kind == kind;
      return IconButton(
        tooltip: label,
        isSelected: selected,
        style: IconButton.styleFrom(
          backgroundColor: selected
              ? scheme.primary.withValues(alpha: 0.15)
              : null,
        ),
        icon: Icon(icon, color: selected ? scheme.primary : null),
        onPressed: () => tools.selectTool(kind),
      );
    }

    return Material(
      color: scheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            if (inkEnabled) ...[
              IconButton(
                tooltip: tool.drawMode
                    ? 'Hand (scroll with one finger)'
                    : 'Hand',
                isSelected: !tool.drawMode,
                style: IconButton.styleFrom(
                  backgroundColor: tool.drawMode
                      ? null
                      : scheme.primary.withValues(alpha: 0.15),
                ),
                icon: Icon(
                  Icons.pan_tool_outlined,
                  color: tool.drawMode ? null : scheme.primary,
                ),
                onPressed: () => tools.setDrawMode(!tool.drawMode),
              ),
              toolButton(InkToolKind.pen, Icons.edit, 'Pen'),
              toolButton(
                InkToolKind.highlighter,
                Icons.highlight,
                'Highlighter',
              ),
              toolButton(InkToolKind.eraser, Icons.auto_fix_normal, 'Eraser'),
              toolButton(InkToolKind.select, Icons.near_me_outlined, 'Select'),
            ],
            IconButton(
              tooltip: 'Text',
              icon: const Icon(Icons.text_fields),
              onPressed: () => addTextBox(context, ref, pageId),
            ),
            IconButton(
              tooltip: 'Photo',
              icon: const Icon(Icons.add_photo_alternate_outlined),
              onPressed: () => addPhoto(context, ref, pageId),
            ),
            IconButton(
              tooltip: 'Stickers',
              icon: const Icon(Icons.emoji_emotions_outlined),
              onPressed: () => showStickerTray(context, pageId),
            ),
            if (inkEnabled) ...[
              const _Divider(),
              for (final (i, color) in skin.inkColors.indexed)
                _ColorDot(
                  color: color,
                  selected: i == tool.colorIndex,
                  onTap: () => tools.selectColor(i),
                  label: 'Ink color ${i + 1}',
                ),
              const _Divider(),
              for (var i = 0; i < 3; i++)
                IconButton(
                  tooltip: const ['Thin', 'Medium', 'Thick'][i],
                  isSelected: i == tool.sizeIndex,
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
            ],
            const _Divider(),
            IconButton(
              tooltip: 'Undo',
              icon: const Icon(Icons.undo),
              onPressed: history.canUndo ? historyActions.undo : null,
            ),
            IconButton(
              tooltip: 'Redo',
              icon: const Icon(Icons.redo),
              onPressed: history.canRedo ? historyActions.redo : null,
            ),
          ],
        ),
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
