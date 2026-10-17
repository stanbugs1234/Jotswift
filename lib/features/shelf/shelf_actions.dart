import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/catalog/catalog_item.dart';
import '../../core/entitlements/feature_gate.dart';
import '../../core/paper/paper_style.dart';
import '../../core/skins/skin_providers.dart';
import '../../shared/dialogs.dart';
import '../notebooks/domain/notebook_models.dart';
import '../canvas/templates.dart';
import '../imports/document_import.dart';
import '../imports/import_actions.dart';
import '../notebooks/notebook_editor.dart';
import '../notebooks/notes_providers.dart';
import '../notebooks/open_page.dart';
import '../notebooks/page_order.dart';
import '../notebooks/planner_builder.dart';
import '../store/paywall.dart';
import 'shelf_view.dart';
import 'tag_editor.dart';
import '../notebooks/my_templates.dart' show copyNotebookProvider;

/// The shelf as it is now (empty while loading).
Shelf currentShelf(WidgetRef ref) => Shelf(
  ref.read(notebooksProvider).value ?? const [],
  ref.read(groupsProvider).value ?? const [],
);

/// Makes a notebook at [location], starting the editor with [cover],
/// [paper] or [template] when given (from the store). Free accounts at the
/// notebook limit see the Pro paywall first.
Future<void> createNotebookAt(
  BuildContext context,
  WidgetRef ref,
  ShelfLocation location, {
  NotebookCover? cover,
  PaperStyle? paper,
  CatalogItem? template,
}) async {
  if (!await _mayCreate(context, ref) || !context.mounted) return;
  final count = ref.read(notebooksProvider).value?.length ?? 0;
  final result = await NotebookEditor.show(
    context,
    initial: NewNotebook(
      title: '',
      cover:
          cover ??
          NotebookCover.color(notebookColors[count % notebookColors.length]),
      paper: paper,
      collectionId: ref.read(activeSkinProvider).id,
      place: location.place,
    ),
    template: template,
  );
  if (result == null || !context.mounted) return;
  final planner = result.template;
  final mine = result.mine;
  final notebook = mine != null
      ? await ref.read(copyNotebookProvider)(mine.id, result.notebook)
      : planner == null
      ? await ref
            .read(notebookRepositoryProvider)
            .createNotebook(result.notebook)
      : await _createPlanner(context, ref, result, planner);
  if (notebook == null) return;
  if (context.mounted) await openNotebook(context, ref, notebook);
}

/// Makes a notebook from [planner], showing "Setting up your planner..."
/// with progress while its pages are made.
Future<Notebook?> _createPlanner(
  BuildContext context,
  WidgetRef ref,
  NotebookEditorResult result,
  CatalogItem planner,
) {
  final create = ref.read(createFromTemplateProvider);
  return withPlannerProgress(
    context,
    (onProgress) => create(
      result.notebook,
      planner,
      file: result.variant,
      skip: result.skip,
      from: result.from,
      onProgress: onProgress,
    ),
  );
}

/// Asks for PDFs or images (unless given [files], sent from another app)
/// and makes a notebook of them at [location], named after the first file,
/// then opens it.
Future<void> importNotebookAt(
  BuildContext context,
  WidgetRef ref,
  ShelfLocation location, {
  List<ImportFile>? files,
}) async {
  if (!await _mayCreate(context, ref) || !context.mounted) return;
  files ??= await chooseImportFiles(context, ref);
  if (files == null || !context.mounted) return;
  final documents = await importWithProgress(context, ref, files);
  if (documents == null || !context.mounted) return;
  final repo = ref.read(notebookRepositoryProvider);
  final count = ref.read(notebooksProvider).value?.length ?? 0;
  final (size, orientation) = closestPaperSize(documents.first.firstPageSize);
  final title = documents.first.title;
  final notebook = await repo.createNotebook(
    NewNotebook(
      title: title.isEmpty ? 'Imported' : title,
      cover: NotebookCover.color(notebookColors[count % notebookColors.length]),
      paperSize: size,
      orientation: orientation,
      collectionId: ref.read(activeSkinProvider).id,
      place: location.place,
    ),
  );
  final section = (await repo.watchSections(notebook.id).first).first;
  await repo.createPages(notebook.id, section.id, importedPages(documents));
  if (context.mounted) await openNotebook(context, ref, notebook);
}

/// Opens [notebook] on the page it should open to (see [pageToOpen]):
/// today's page in a planner on a new day, otherwise where the user left
/// off. Back from it shows the notebook's sections and pages, then returns
/// here. A notebook with no pages opens on its page list.
Future<void> openNotebook(
  BuildContext context,
  WidgetRef ref,
  Notebook notebook,
) async {
  final repo = ref.read(notebookRepositoryProvider);
  final (sections, pages) = await (
    repo.watchSections(notebook.id).first,
    repo.watchNotebookPages(notebook.id).first,
  ).wait;
  if (!context.mounted) return;
  final page = pageToOpen(notebook, sortPages(sections, pages), DateTime.now());
  if (page == null) {
    await context.push('/notebooks/${notebook.id}');
  } else {
    _openFromShelf(context, notebook.id, page.id);
  }
}

/// Opens a page like a book, with its notebook's page list beneath it, so
/// Back goes to the sections and then to the shelf as it was (the shelf's
/// query, e.g. `view=starred`, is kept).
void _openFromShelf(BuildContext context, String notebookId, String pageId) {
  final query = GoRouterState.of(context).uri.queryParameters;
  context.go(
    Uri(
      path: '/notebooks/$notebookId/pages/$pageId',
      queryParameters: query.isEmpty ? null : query,
    ).toString(),
    extra: openedFromShelf,
  );
}

/// Free accounts at the notebook limit see the Pro paywall. True when a
/// notebook may be made.
Future<bool> _mayCreate(BuildContext context, WidgetRef ref) async {
  if (ref.read(canCreateNotebookProvider)) return true;
  return showPaywall(
    context,
    ref,
    reason:
        'Free accounts have up to $freeNotebookLimit notebooks, counting '
        'any in the Trash. Get Jotswift Pro for as many as you like.',
  );
}

/// Makes a notebook at [location] with the usual cover and paper, without
/// asking anything, and opens its first page to write on.
Future<void> createQuickNote(
  BuildContext context,
  WidgetRef ref,
  ShelfLocation location,
) async {
  if (!await _mayCreate(context, ref) || !context.mounted) return;
  final repo = ref.read(notebookRepositoryProvider);
  final count = ref.read(notebooksProvider).value?.length ?? 0;
  final notebook = await repo.createNotebook(
    NewNotebook(
      title: 'Quick note',
      cover: NotebookCover.color(notebookColors[count % notebookColors.length]),
      collectionId: ref.read(activeSkinProvider).id,
      place: location.place,
    ),
  );
  final sections = await repo.watchSections(notebook.id).first;
  final page = await repo.createPage(notebook.id, sections.first.id);
  if (context.mounted) _openFromShelf(context, notebook.id, page.id);
}

/// Changes a notebook's title, cover, paper and style.
Future<void> editNotebook(
  BuildContext context,
  WidgetRef ref,
  Notebook notebook,
) async {
  final spec = (await NotebookEditor.show(
    context,
    editing: notebook,
    initial: NewNotebook(
      title: notebook.title,
      cover: notebook.cover,
      paper: notebook.paper,
      paperSize: notebook.paperSize,
      orientation: notebook.orientation,
      collectionId: notebook.collectionId,
    ),
  ))?.notebook;
  if (spec == null) return;
  await ref
      .read(notebookRepositoryProvider)
      .updateNotebook(
        notebook.id,
        title: spec.title,
        cover: spec.cover,
        paper: spec.paper,
        collectionId: spec.collectionId,
      );
}

Future<void> createGroupAt(
  BuildContext context,
  WidgetRef ref,
  ShelfLocation location,
) async {
  final title = await askForText(
    context,
    title: 'New group',
    confirmLabel: 'Create',
    hint: 'e.g. Semester 1, Trips',
  );
  if (title == null || !context.mounted) return;
  await ref
      .read(shelfRepositoryProvider)
      .createGroup(title.isEmpty ? 'Untitled group' : title, location.place);
}

Future<void> createCategory(BuildContext context, WidgetRef ref) async {
  final title = await askForText(
    context,
    title: 'New category',
    confirmLabel: 'Create',
    hint: 'e.g. School, Work',
  );
  if (title == null || title.isEmpty || !context.mounted) return;
  final category = await ref
      .read(shelfRepositoryProvider)
      .createCategory(title);
  if (context.mounted) context.go(InCategory(category.id).path);
}

enum _CategoryAction { rename, delete }

/// Rename or delete [category]. [isOpen] is whether the shelf shows it now.
Future<void> showCategoryMenu(
  BuildContext context,
  WidgetRef ref,
  Category category, {
  required bool isOpen,
}) async {
  final action = await showModalBottomSheet<_CategoryAction>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename category'),
            onTap: () => Navigator.pop(context, _CategoryAction.rename),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete category'),
            onTap: () => Navigator.pop(context, _CategoryAction.delete),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  final repo = ref.read(shelfRepositoryProvider);
  switch (action) {
    case _CategoryAction.rename:
      final title = await askForText(
        context,
        title: 'Rename category',
        confirmLabel: 'Rename',
        initialValue: category.title,
      );
      if (title != null && title.isNotEmpty) {
        await repo.renameCategory(category.id, title);
      }
    case _CategoryAction.delete:
      final ok = await confirmDelete(
        context,
        title: 'Delete "${category.title}"?',
        message: 'The notebooks and groups in it are kept, with no category.',
      );
      if (!ok) return;
      await repo.deleteCategory(category.id);
      if (isOpen && context.mounted) context.go(const AllNotebooks().path);
  }
}

enum NotebookAction { rename, edit, move, tags, star, trash }

Future<void> onNotebookAction(
  BuildContext context,
  WidgetRef ref,
  Notebook notebook,
  NotebookAction action,
) async {
  final repo = ref.read(notebookRepositoryProvider);
  switch (action) {
    case NotebookAction.rename:
      final title = await askForText(
        context,
        title: 'Rename notebook',
        confirmLabel: 'Rename',
        initialValue: notebook.title,
      );
      if (title != null && title.isNotEmpty) {
        await repo.updateNotebook(notebook.id, title: title);
      }
    case NotebookAction.edit:
      await editNotebook(context, ref, notebook);
    case NotebookAction.move:
      final place = await pickShelfPlace(
        context,
        ref,
        title: 'Move "${notebook.title}"',
        current: (categoryId: notebook.categoryId, groupId: notebook.groupId),
      );
      if (place != null) {
        await ref
            .read(shelfRepositoryProvider)
            .moveNotebook(notebook.id, place);
      }
    case NotebookAction.tags:
      await editTags(context, notebook.id);
    case NotebookAction.star:
      await ref
          .read(shelfRepositoryProvider)
          .setStarred(notebook.id, !notebook.starred);
    case NotebookAction.trash:
      await moveToTrash(context, ref, notebook);
  }
}

/// Moves [notebook] to the Trash, with a moment to undo it.
Future<void> moveToTrash(
  BuildContext context,
  WidgetRef ref,
  Notebook notebook,
) async {
  final shelf = ref.read(shelfRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);
  await shelf.setTrashed(notebook.id, true);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('Moved "${notebook.title}" to the Trash'),
        // Goes away by itself, though it has an action.
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => shelf.setTrashed(notebook.id, false),
        ),
      ),
    );
}

enum TrashAction { restore, delete }

/// Restore a notebook from the Trash, or delete it for good.
Future<void> onTrashedNotebookAction(
  BuildContext context,
  WidgetRef ref,
  Notebook notebook,
  TrashAction action,
) async {
  switch (action) {
    case TrashAction.restore:
      await ref.read(shelfRepositoryProvider).setTrashed(notebook.id, false);
    case TrashAction.delete:
      final ok = await confirmDelete(
        context,
        title: 'Delete "${notebook.title}" for good?',
        message:
            'This deletes the notebook and every page in it. '
            'It cannot be undone.',
      );
      if (ok) {
        await ref.read(notebookRepositoryProvider).deleteNotebook(notebook.id);
      }
  }
}

/// Deletes every notebook in the Trash, after asking.
Future<void> emptyTrash(
  BuildContext context,
  WidgetRef ref,
  List<Notebook> trashed,
) async {
  if (trashed.isEmpty) return;
  final count = trashed.length == 1
      ? '1 notebook'
      : '${trashed.length} notebooks';
  final ok = await confirmDelete(
    context,
    title: 'Empty the Trash?',
    message: 'This deletes $count and every page in them. It cannot be undone.',
    confirmLabel: 'Empty Trash',
  );
  if (!ok || !context.mounted) return;
  final repo = ref.read(notebookRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);
  // All at once; each notebook leaves the Trash as soon as its delete
  // starts, and one that fails doesn't stop the others.
  final results = await Future.wait([
    for (final n in trashed)
      repo.deleteNotebook(n.id).then((_) => true, onError: (_) => false),
  ]);
  final failed = results.where((ok) => !ok).length;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? 'Trash emptied'
              : "$failed couldn't be deleted. Check your connection and try "
                    'again.',
        ),
      ),
    );
}

enum GroupAction { rename, move, delete }

Future<void> onGroupAction(
  BuildContext context,
  WidgetRef ref,
  NotebookGroup group,
  GroupAction action,
) async {
  final repo = ref.read(shelfRepositoryProvider);
  switch (action) {
    case GroupAction.rename:
      final title = await askForText(
        context,
        title: 'Rename group',
        confirmLabel: 'Rename',
        initialValue: group.title,
      );
      if (title != null && title.isNotEmpty) {
        await repo.renameGroup(group.id, title);
      }
    case GroupAction.move:
      final shelf = currentShelf(ref);
      final place = await pickShelfPlace(
        context,
        ref,
        title: 'Move "${group.title}"',
        current: (categoryId: group.categoryId, groupId: group.parentGroupId),
        excludeGroups: {group.id, ...shelf.descendantGroupIds(group.id)},
      );
      if (place != null) await repo.moveGroup(group.id, place);
    case GroupAction.delete:
      final ok = await confirmDelete(
        context,
        title: 'Delete the group "${group.title}"?',
        message: 'The notebooks in it are kept and move up one level.',
      );
      if (ok) await repo.deleteGroup(group.id);
  }
}

/// Asks where to put something: a category, a group, or no category.
/// Groups in [excludeGroups] (a group and everything inside it) can't be
/// picked. Returns null if cancelled.
Future<ShelfPlace?> pickShelfPlace(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required ShelfPlace current,
  Set<String> excludeGroups = const {},
}) {
  final categories = ref.read(categoriesProvider).value ?? const [];
  final groups = (ref.read(groupsProvider).value ?? const <NotebookGroup>[])
      .where((g) => !excludeGroups.contains(g.id))
      .toList();
  final shelf = Shelf(const [], groups);

  final options =
      <({ShelfPlace place, String label, int depth, IconData icon})>[];
  void addGroups(Iterable<NotebookGroup> level, int depth) {
    for (final g in level) {
      options.add((
        place: (categoryId: null, groupId: g.id),
        label: g.title,
        depth: depth,
        icon: Icons.folder_outlined,
      ));
      addGroups(groups.where((c) => c.parentGroupId == g.id), depth + 1);
    }
  }

  options.add((
    place: unfiled,
    label: 'No category',
    depth: 0,
    icon: Icons.inbox_outlined,
  ));
  addGroups(
    groups
        .where((g) => shelf.group(g.parentGroupId ?? '') == null)
        .where((g) => g.categoryId == null),
    1,
  );
  for (final c in categories) {
    options.add((
      place: (categoryId: c.id, groupId: null),
      label: c.title,
      depth: 0,
      icon: Icons.label_outline,
    ));
    addGroups(
      groups.where(
        (g) =>
            shelf.group(g.parentGroupId ?? '') == null && g.categoryId == c.id,
      ),
      1,
    );
  }

  return showDialog<ShelfPlace>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        for (final o in options)
          SimpleDialogOption(
            padding: EdgeInsets.fromLTRB(24.0 + o.depth * 20, 10, 24, 10),
            onPressed: o.place == current
                ? null
                : () => Navigator.pop(context, o.place),
            child: Row(
              children: [
                Icon(o.icon, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(o.label)),
                if (o.place == current) const Icon(Icons.check, size: 18),
              ],
            ),
          ),
      ],
    ),
  );
}
