import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/dialogs.dart';
import '../notebooks/domain/notebook_models.dart';
import '../notebooks/notes_providers.dart';
import 'shelf_view.dart';

/// The shelf as it is now (empty while loading).
Shelf currentShelf(WidgetRef ref) => Shelf(
  ref.read(notebooksProvider).value ?? const [],
  ref.read(groupsProvider).value ?? const [],
);

Future<void> createNotebookAt(
  BuildContext context,
  WidgetRef ref,
  ShelfLocation location,
) async {
  final title = await askForText(
    context,
    title: 'New notebook',
    confirmLabel: 'Create',
    hint: 'e.g. School, Work, Journal',
  );
  if (title == null || !context.mounted) return;
  final count = ref.read(notebooksProvider).value?.length ?? 0;
  final notebook = await ref
      .read(notebookRepositoryProvider)
      .createNotebook(
        NewNotebook(
          title: title.isEmpty ? 'Untitled notebook' : title,
          cover: NotebookCover.color(
            notebookColors[count % notebookColors.length],
          ),
          place: location.place,
        ),
      );
  if (context.mounted) await context.push('/notebooks/${notebook.id}');
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

enum NotebookAction { rename, color, move, delete }

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
    case NotebookAction.color:
      final i = notebookColors.indexOf(notebook.cover.color);
      await repo.updateNotebook(
        notebook.id,
        cover: NotebookCover.color(
          notebookColors[(i + 1) % notebookColors.length],
        ),
      );
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
    case NotebookAction.delete:
      final ok = await confirmDelete(
        context,
        title: 'Delete "${notebook.title}"?',
        message:
            'This deletes the notebook and every page in it. '
            'It cannot be undone.',
      );
      if (ok) await repo.deleteNotebook(notebook.id);
  }
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
