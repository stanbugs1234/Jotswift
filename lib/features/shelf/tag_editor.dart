import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/ui/tokens.dart';
import '../notebooks/domain/notebook_models.dart';
import '../notebooks/notes_providers.dart';
import 'shelf_view.dart';

/// Adds and removes notebook [notebookId]'s tags. Each change is saved
/// straight away.
Future<void> editTags(BuildContext context, String notebookId) =>
    showDialog<void>(
      context: context,
      builder: (context) => _TagEditor(notebookId: notebookId),
    );

class _TagEditor extends ConsumerStatefulWidget {
  const _TagEditor({required this.notebookId});

  final String notebookId;

  @override
  ConsumerState<_TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends ConsumerState<_TagEditor> {
  final _field = TextEditingController();
  final _focus = FocusNode();

  /// The tags as last saved here, so quick changes build on each other
  /// before the notebook comes back with them.
  List<String>? _tags;

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _save(List<String> tags) async {
    setState(() => _tags = tags);
    await ref.read(shelfRepositoryProvider).setTags(widget.notebookId, tags);
  }

  Future<void> _add(List<String> shown, String text) async {
    final tags = _tags ?? shown;
    final tag = normalizeTag(text);
    _field.clear();
    _focus.requestFocus();
    if (tag.isEmpty || tags.any((t) => t.toLowerCase() == tag.toLowerCase())) {
      setState(() {});
      return;
    }
    await _save([...tags, tag]);
  }

  @override
  Widget build(BuildContext context) {
    final notebook = ref.watch(notebookProvider(widget.notebookId)).value;
    final tags = _tags ?? notebook?.tags ?? const <String>[];
    final all = Shelf(
      ref.watch(notebooksProvider).value ?? const [],
      const [],
    ).tagCounts.keys;
    final typed = normalizeTag(_field.text).toLowerCase();
    final suggestions = [
      for (final t in all)
        if (!tags.any((x) => x.toLowerCase() == t.toLowerCase()) &&
            t.toLowerCase().contains(typed))
          t,
    ];
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(
        notebook == null ? 'Tags' : 'Tags for "${notebook.title}"',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (tags.isEmpty)
                Text(
                  'Tag notebooks to find them under Tags in the sidebar, '
                  'or by searching #tag.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Wrap(
                  spacing: Insets.sm,
                  runSpacing: Insets.sm,
                  children: [
                    for (final t in tags)
                      InputChip(
                        label: Text('#$t'),
                        onDeleted: () => _save([...tags.where((x) => x != t)]),
                        deleteButtonTooltipMessage: 'Remove #$t',
                      ),
                  ],
                ),
              const SizedBox(height: Insets.md),
              TextField(
                controller: _field,
                focusNode: _focus,
                autofocus: true,
                maxLength: 30,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Add a tag',
                  prefixText: '#',
                  counterText: '',
                ),
                onChanged: (text) {
                  // A comma ends a tag, as Enter does.
                  if (text.contains(',')) {
                    final parts = text.split(',');
                    _field.text = parts.removeLast();
                    for (final p in parts) {
                      _add(tags, p);
                    }
                  } else {
                    setState(() {});
                  }
                },
                onSubmitted: (text) => _add(tags, text),
              ),
              if (suggestions.isNotEmpty) ...[
                const SizedBox(height: Insets.md),
                Text('Your tags', style: theme.textTheme.labelMedium),
                const SizedBox(height: Insets.sm),
                Wrap(
                  spacing: Insets.sm,
                  runSpacing: Insets.sm,
                  children: [
                    for (final t in suggestions.take(20))
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 16),
                        label: Text('#$t'),
                        onPressed: () => _add(tags, t),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            // What's typed but not yet added counts too.
            if (normalizeTag(_field.text).isNotEmpty) {
              await _add(tags, _field.text);
            }
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Done'),
        ),
      ],
    );
  }
}
