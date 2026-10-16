import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/synced_setting.dart';
import 'ink_tools.dart';

/// The tools that can go in the page toolbar, in their usual order.
enum ToolbarTool {
  pen,
  highlighter,
  eraser,
  shapes,
  tape,
  select,
  lasso,
  laser,
  zoomWindow,
  ruler,
  record,
  recordings,
  text,
  photo,
  stickers;

  String get label => switch (this) {
    pen => 'Pen',
    highlighter => 'Highlighter',
    eraser => 'Eraser',
    shapes => 'Shapes',
    tape => 'Tape',
    select => 'Select',
    lasso => 'Lasso',
    laser => 'Laser pointer',
    zoomWindow => 'Zoom window',
    ruler => 'Ruler',
    record => 'Record audio',
    recordings => 'Recordings',
    text => 'Text',
    photo => 'Photo',
    stickers => 'Stickers',
  };

  IconData get icon => switch (this) {
    pen => Icons.edit,
    highlighter => Icons.highlight,
    eraser => Icons.auto_fix_normal,
    shapes => Icons.category_outlined,
    tape => Icons.crop_7_5,
    select => Icons.near_me_outlined,
    lasso => Icons.highlight_alt,
    laser => Icons.flare,
    zoomWindow => Icons.pageview_outlined,
    ruler => Icons.straighten,
    record => Icons.mic_none,
    recordings => Icons.headphones_outlined,
    text => Icons.text_fields,
    photo => Icons.add_photo_alternate_outlined,
    stickers => Icons.emoji_emotions_outlined,
  };

  /// The ink tool it picks up, if it's one.
  InkToolKind? get kind => switch (this) {
    pen => InkToolKind.pen,
    highlighter => InkToolKind.highlighter,
    eraser => InkToolKind.eraser,
    shapes => InkToolKind.shape,
    tape => InkToolKind.tape,
    select => InkToolKind.select,
    lasso => InkToolKind.lasso,
    laser => InkToolKind.laser,
    _ => null,
  };

  /// Only where ink can be drawn (not on the web).
  bool get needsInk => switch (this) {
    text || photo || stickers => false,
    _ => true,
  };

  /// Always in the toolbar, so there's a way back to writing.
  bool get required => this == pen;
}

/// The toolbar's tools in the order the user put them, and those they
/// hid. Kept on the device: a phone and an iPad often want different ones.
@immutable
class ToolbarLayout {
  const ToolbarLayout({
    this.order = ToolbarTool.values,
    this.hidden = const {},
    this.savedPens = false,
  });

  factory ToolbarLayout.fromJson(Map<String, dynamic> json) {
    final names = ToolbarTool.values.asNameMap();
    final saved = [
      for (final n in json['order'] as List? ?? const []) ?names[n],
    ];
    return ToolbarLayout(
      // Tools added since it was saved go at the end.
      order: [
        ...saved.toSet(),
        for (final t in ToolbarTool.values)
          if (!saved.contains(t)) t,
      ],
      hidden: {
        for (final n in json['hidden'] as List? ?? const [])
          if (names[n] case final t? when !t.required) t,
      },
      savedPens: json['savedPens'] == true,
    );
  }

  final List<ToolbarTool> order;
  final Set<ToolbarTool> hidden;

  /// Saved pens get buttons of their own after the pen, and act as tools:
  /// changing one in hand changes it.
  final bool savedPens;

  /// The tools shown, in order.
  List<ToolbarTool> get shown => [
    for (final t in order)
      if (!hidden.contains(t)) t,
  ];

  Map<String, Object> toJson() => {
    'order': [for (final t in order) t.name],
    'hidden': [for (final t in hidden) t.name],
    'savedPens': savedPens,
  };
}

class ToolbarLayoutController extends Notifier<ToolbarLayout> {
  static const _prefsKey = 'toolbarLayout';

  @override
  ToolbarLayout build() {
    final saved = ref.watch(sharedPreferencesProvider).getString(_prefsKey);
    if (saved == null) return const ToolbarLayout();
    try {
      return ToolbarLayout.fromJson(jsonDecode(saved) as Map<String, dynamic>);
    } catch (_) {
      return const ToolbarLayout();
    }
  }

  void _save(ToolbarLayout layout) {
    state = layout;
    ref
        .read(sharedPreferencesProvider)
        .setString(_prefsKey, jsonEncode(layout.toJson()));
  }

  /// Moves the tool at [from] so it ends up at [to].
  void move(int from, int to) {
    final order = [...state.order];
    final tool = order.removeAt(from);
    order.insert(to, tool);
    _save(
      ToolbarLayout(
        order: order,
        hidden: state.hidden,
        savedPens: state.savedPens,
      ),
    );
  }

  void setShown(ToolbarTool tool, bool shown) {
    if (tool.required) return;
    _save(
      ToolbarLayout(
        order: state.order,
        hidden: shown
            ? ({...state.hidden}..remove(tool))
            : {...state.hidden, tool},
        savedPens: state.savedPens,
      ),
    );
  }

  void setSavedPens(bool on) => _save(
    ToolbarLayout(order: state.order, hidden: state.hidden, savedPens: on),
  );

  void reset() => _save(const ToolbarLayout());
}

final toolbarLayoutProvider =
    NotifierProvider<ToolbarLayoutController, ToolbarLayout>(
      ToolbarLayoutController.new,
    );

/// A sheet to put the toolbar's tools in order, and show or hide them.
Future<void> showToolbarEditor(BuildContext context) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => const _ToolbarEditor(),
);

class _ToolbarEditor extends ConsumerWidget {
  const _ToolbarEditor();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(toolbarLayoutProvider);
    final edit = ref.read(toolbarLayoutProvider.notifier);
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Customize toolbar',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  TextButton(onPressed: edit.reset, child: const Text('Reset')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Drag to reorder. Switch off the tools you don\'t use.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              title: const Text('Saved pens as tools'),
              subtitle: const Text(
                'Each saved pen gets its own button after the pen. Change '
                'one while it\'s in hand and it stays changed.',
              ),
              value: layout.savedPens,
              onChanged: edit.setSavedPens,
            ),
            const Divider(height: 1),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: layout.order.length,
                onReorderItem: edit.move,
                itemBuilder: (context, i) {
                  final tool = layout.order[i];
                  return ListTile(
                    key: ValueKey(tool),
                    leading: ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.drag_indicator),
                      ),
                    ),
                    title: Row(
                      children: [
                        Icon(tool.icon, size: 20),
                        const SizedBox(width: 12),
                        Text(tool.label),
                      ],
                    ),
                    // The pen can't go: a greyed-out switch would look off.
                    trailing: tool.required
                        ? Text(
                            'Always shown',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          )
                        : Switch(
                            value: !layout.hidden.contains(tool),
                            onChanged: (on) => edit.setShown(tool, on),
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
