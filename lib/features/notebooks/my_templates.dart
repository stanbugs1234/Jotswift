import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/skins/skin_providers.dart';
import '../../shared/dialogs.dart';
import '../canvas/page_canvas.dart' show PagePrint;
import '../canvas/templates.dart' show closestPaperSize;
import '../imports/document_import.dart' show importedPages;
import '../imports/import_actions.dart';
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

/// Makes one of the user's own templates from PDFs or images they choose,
/// every page kept, named after the first file. It's then offered under
/// Start with when making a notebook.
Future<void> importAsTemplate(BuildContext context, WidgetRef ref) async {
  final files = await chooseImportFiles(context, ref);
  if (files == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final documents = await importWithProgress(context, ref, files);
  if (documents == null) return;
  final repo = ref.read(notebookRepositoryProvider);
  final (size, orientation) = closestPaperSize(documents.first.firstPageSize);
  final title = documents.first.title.isEmpty
      ? 'Imported template'
      : documents.first.title;
  final count = ref.read(myTemplatesProvider).value?.length ?? 0;
  final template = await repo.createNotebook(
    NewNotebook(
      title: title,
      cover: NotebookCover.color(notebookColors[count % notebookColors.length]),
      paperSize: size,
      orientation: orientation,
      collectionId: ref.read(activeSkinProvider).id,
      isTemplate: true,
    ),
  );
  final section = (await repo.watchSections(template.id).first).first;
  await repo.createPages(template.id, section.id, importedPages(documents));
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          'Saved "$title" as a template. Choose it under Start with when '
          'you make a new notebook.',
        ),
      ),
    );
}

/// The user's own templates: open one to change it, rename or delete it;
/// import one from a PDF; and the pages they saved as templates.
class MyTemplatesScreen extends ConsumerWidget {
  const MyTemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(myTemplatesProvider).value ?? const [];
    final pages = ref.watch(myPageTemplatesProvider).value ?? const [];
    final theme = Theme.of(context);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(text, style: theme.textTheme.titleSmall),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('My templates'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Import PDF or images'),
              onPressed: () => importAsTemplate(context, ref),
            ),
          ),
        ],
      ),
      body: templates.isEmpty && pages.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No templates yet.\n\nSet up a notebook the way you like '
                  'it: sections, pages and anything written on them. Then '
                  'choose Save as template from its ⋯ menu.\n\nOr import a '
                  'PDF, like a planner you bought, as a template; or save a '
                  'single page with Save page as template.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (templates.isNotEmpty) ...[
                  heading('Notebooks'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text(
                      'New notebooks start as a copy of the template. '
                      "Changing a template doesn't change notebooks made "
                      'from it.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  for (final t in templates) _TemplateTile(template: t),
                ],
                if (pages.isNotEmpty) ...[
                  heading('Pages'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text(
                      'Offered under My pages when you add a page.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  for (final p in pages) _PageTemplateTile(page: p),
                ],
              ],
            ),
    );
  }
}

/// A small print of [pageId] with a shadow, for a list.
class _PagePreview extends StatelessWidget {
  const _PagePreview({required this.pageId});

  final String pageId;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 40,
    height: 52,
    child: DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: FittedBox(child: PagePrint(pageId: pageId, templateWidth: 120)),
    ),
  );
}

/// The first page of the template [notebookId], or its [cover] until
/// there is one.
class TemplateFirstPage extends ConsumerWidget {
  const TemplateFirstPage({
    required this.notebookId,
    required this.cover,
    super.key,
  });

  final String notebookId;
  final NotebookCover cover;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = ref.watch(firstPageProvider(notebookId)).value;
    return first == null
        ? CoverView(cover: cover, elevation: 1)
        : FittedBox(child: PagePrint(pageId: first, templateWidth: 240));
  }
}

/// A saved page template: rename or delete it.
class _PageTemplateTile extends ConsumerWidget {
  const _PageTemplateTile({required this.page});

  final NotePage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(notebookRepositoryProvider);
    return ListTile(
      leading: _PagePreview(pageId: page.id),
      title: Text(page.displayTitle),
      trailing: PopupMenuButton<String>(
        tooltip: 'Page template options',
        onSelected: (action) async {
          switch (action) {
            case 'rename':
              final name = await askForText(
                context,
                title: 'Rename page template',
                confirmLabel: 'Rename',
                initialValue: page.title,
              );
              if (name != null && name.trim().isNotEmpty) {
                await repo.renamePage(page.id, name.trim());
              }
            case 'delete':
              final ok = await confirmDelete(
                context,
                title: 'Delete "${page.displayTitle}"?',
                message:
                    'Pages already added from it are kept. This can’t be '
                    'undone.',
              );
              if (ok) await repo.deletePage(page.id);
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
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
        width: 40,
        height: 52,
        child: TemplateFirstPage(
          notebookId: template.id,
          cover: template.cover,
        ),
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
