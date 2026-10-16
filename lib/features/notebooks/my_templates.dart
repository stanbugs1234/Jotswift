import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/dialogs.dart';
import '../shelf/cover_view.dart';
import 'domain/notebook_models.dart';
import 'notebook_copy.dart';
import 'notes_providers.dart';

const myTemplatesPath = '/settings/templates';

/// What [copyNotebookInto] needs, so widgets can call it.
final copyNotebookProvider =
    Provider<Future<Notebook> Function(String sourceId, NewNotebook into)>(
      (ref) =>
          (sourceId, into) => copyNotebookInto(ref, sourceId, into),
    );

/// Saves a copy of [notebook] (sections, pages, writing and all) as one of
/// the user's own templates, under a name they choose.
Future<void> saveAsTemplate(
  BuildContext context,
  WidgetRef ref,
  Notebook notebook,
) async {
  final name = await askForText(
    context,
    title: 'Save as template',
    confirmLabel: 'Save',
    initialValue: notebook.title,
    hint: 'Template name',
  );
  if (name == null || name.trim().isEmpty || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  await ref.read(copyNotebookProvider)(
    notebook.id,
    NewNotebook(
      title: name.trim(),
      cover: notebook.cover,
      paper: notebook.paper,
      paperSize: notebook.paperSize,
      orientation: notebook.orientation,
      collectionId: notebook.collectionId,
      isTemplate: true,
    ),
  );
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          'Saved "${name.trim()}". Choose it under Start with when you make '
          'a new notebook.',
        ),
      ),
    );
}

/// The user's own templates: open one to change it, rename or delete it.
class MyTemplatesScreen extends ConsumerWidget {
  const MyTemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(myTemplatesProvider).value ?? const [];
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('My templates')),
      body: templates.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No templates yet.\n\nSet up a notebook the way you like '
                  'it: sections, pages and anything written on them. Then '
                  'choose Save as template from its ⋯ menu.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            )
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'New notebooks start as a copy of the template. Changing '
                    "a template doesn't change notebooks made from it.",
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                for (final t in templates) _TemplateTile(template: t),
              ],
            ),
    );
  }
}

class _TemplateTile extends ConsumerWidget {
  const _TemplateTile({required this.template});

  final Notebook template;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = ref.watch(sectionsProvider(template.id)).value;
    final repo = ref.read(notebookRepositoryProvider);
    void edit() => context.go('/notebooks/${template.id}');
    return ListTile(
      leading: SizedBox(
        width: 32,
        child: CoverView(cover: template.cover, elevation: 1),
      ),
      title: Text(template.title),
      subtitle: sections == null
          ? null
          : Text(
              '${sections.length} section${sections.length == 1 ? '' : 's'}',
            ),
      onTap: edit,
      trailing: PopupMenuButton<String>(
        tooltip: 'Template options',
        onSelected: (action) async {
          switch (action) {
            case 'edit':
              edit();
            case 'rename':
              final name = await askForText(
                context,
                title: 'Rename template',
                confirmLabel: 'Rename',
                initialValue: template.title,
              );
              if (name != null && name.trim().isNotEmpty) {
                await repo.updateNotebook(template.id, title: name.trim());
              }
            case 'delete':
              final ok = await confirmDelete(
                context,
                title: 'Delete "${template.title}"?',
                message:
                    'Notebooks already made from it are kept. This can’t be '
                    'undone.',
              );
              if (ok) await repo.deleteNotebook(template.id);
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}
