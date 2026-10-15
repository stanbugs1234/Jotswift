import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/shell.dart';
import '../notebooks/domain/notebook_models.dart';
import '../notebooks/notes_providers.dart';
import 'cover_view.dart';
import 'shelf_actions.dart';
import 'shelf_prefs.dart';
import 'shelf_view.dart';

/// The shelf: notebooks shown by their covers, with groups as stacks.
/// Shows all notebooks, the recent ones, one category, or one group.
class ShelfScreen extends ConsumerWidget {
  const ShelfScreen({this.location = const AllNotebooks(), super.key});

  final ShelfLocation location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notebooks = ref.watch(notebooksProvider);
    final groups = ref.watch(groupsProvider);
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final prefs = ref.watch(shelfPrefsProvider);
    final shelf = Shelf(notebooks.value ?? const [], groups.value ?? const []);
    final hasSidebar = MediaQuery.sizeOf(context).width >= Breakpoints.expanded;

    final title = switch (location) {
      AllNotebooks() => 'Notebooks',
      RecentNotebooks() => 'Recent',
      InCategory(:final id) =>
        categories.where((c) => c.id == id).firstOrNull?.title ?? 'Category',
      InGroup(:final id) => shelf.group(id)?.title ?? 'Group',
    };

    final Widget body;
    if (notebooks case AsyncError(:final error)) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not load notebooks.\n$error'),
        ),
      );
    } else if (!notebooks.hasValue || !groups.hasValue) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final contents = shelf.contents(location, prefs.sort);
      body = contents.isEmpty
          ? _EmptyShelf(
              location: location,
              isFirstNotebook: notebooks.value!.isEmpty,
            )
          : _ShelfItems(
              shelf: shelf,
              contents: contents,
              prefs: prefs,
              subtitle: location is RecentNotebooks
                  ? ShelfSort.lastOpened
                  : prefs.sort,
            );
    }

    return Scaffold(
      appBar: AppBar(
        leading: location is InGroup
            ? BackButton(
                onPressed: () => context.go(shelf.parentOf(location).path),
              )
            : null,
        title: Text(title),
        actions: [
          if (location is! RecentNotebooks)
            IconButton(
              tooltip: 'New group',
              icon: const Icon(Icons.create_new_folder_outlined),
              onPressed: () => createGroupAt(context, ref, location),
            ),
          const _ViewMenu(),
          IconButton(
            tooltip: 'Notebook styles',
            icon: const Icon(Icons.palette_outlined),
            onPressed: () => context.push('/settings/skins'),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
        bottom: hasSidebar || location is InGroup
            ? null
            : _CategoryChips(location: location, categories: categories),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => createNotebookAt(context, ref, location),
        icon: const Icon(Icons.add),
        label: const Text('New notebook'),
      ),
      body: body,
    );
  }
}

/// Categories as chips, for screens too narrow for the sidebar.
class _CategoryChips extends ConsumerWidget implements PreferredSizeWidget {
  const _CategoryChips({required this.location, required this.categories});

  final ShelfLocation location;
  final List<Category> categories;

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget chip(String label, ShelfLocation to, {VoidCallback? onLongPress}) =>
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onLongPress: onLongPress,
            child: ChoiceChip(
              label: Text(label),
              selected: location == to,
              onSelected: (_) => context.go(to.path),
            ),
          ),
        );

    return SizedBox(
      height: preferredSize.height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        children: [
          chip('All', const AllNotebooks()),
          chip('Recent', const RecentNotebooks()),
          for (final c in categories)
            chip(
              c.title,
              InCategory(c.id),
              onLongPress: () => showCategoryMenu(
                context,
                ref,
                c,
                isOpen: location == InCategory(c.id),
              ),
            ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('Category'),
            tooltip: 'New category',
            onPressed: () => createCategory(context, ref),
          ),
        ],
      ),
    );
  }
}

/// Sort order, grid or list, and cover size.
class _ViewMenu extends ConsumerWidget {
  const _ViewMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(shelfPrefsProvider);
    final controller = ref.read(shelfPrefsProvider.notifier);

    CheckedPopupMenuItem<VoidCallback> option(
      String label,
      bool checked,
      VoidCallback onTap,
    ) => CheckedPopupMenuItem(
      value: onTap,
      checked: checked,
      child: Text(label),
    );

    return PopupMenuButton<VoidCallback>(
      tooltip: 'View options',
      icon: const Icon(Icons.tune),
      onSelected: (apply) => apply(),
      itemBuilder: (context) => [
        const PopupMenuItem(enabled: false, child: Text('Sort by')),
        for (final sort in ShelfSort.values)
          option(
            sort.label,
            prefs.sort == sort,
            () => controller.setSort(sort),
          ),
        const PopupMenuDivider(),
        option(
          'Grid',
          prefs.layout == ShelfLayout.grid,
          () => controller.setLayout(ShelfLayout.grid),
        ),
        option(
          'List',
          prefs.layout == ShelfLayout.list,
          () => controller.setLayout(ShelfLayout.list),
        ),
        const PopupMenuDivider(),
        option(
          'Large covers',
          prefs.size == ShelfSize.large,
          () => controller.setSize(ShelfSize.large),
        ),
        option(
          'Small covers',
          prefs.size == ShelfSize.small,
          () => controller.setSize(ShelfSize.small),
        ),
      ],
    );
  }
}

/// A notebook or group being dragged on the shelf.
typedef _Dragged = ({Notebook? notebook, NotebookGroup? group});

class _ShelfItems extends ConsumerWidget {
  const _ShelfItems({
    required this.shelf,
    required this.contents,
    required this.prefs,
    required this.subtitle,
  });

  final Shelf shelf;
  final ShelfContents contents;
  final ShelfPrefs prefs;

  /// Which date notebooks show under their title.
  final ShelfSort subtitle;

  /// Drops [dragged] into a group, or (in the custom order) just before
  /// another notebook.
  Future<void> _drop(
    WidgetRef ref,
    _Dragged dragged, {
    Notebook? onNotebook,
    NotebookGroup? onGroup,
  }) async {
    final repo = ref.read(shelfRepositoryProvider);
    final into = (categoryId: null, groupId: onGroup?.id);
    if (dragged.notebook case final n? when onGroup != null) {
      await repo.moveNotebook(n.id, into);
    } else if (dragged.group case final g? when onGroup != null) {
      await repo.moveGroup(g.id, into);
    } else if (dragged.notebook case final n? when onNotebook != null) {
      final others = contents.notebooks.where((o) => o.id != n.id).toList();
      final i = others.indexWhere((o) => o.id == onNotebook.id);
      final before = i > 0 ? others[i - 1].sortOrder : null;
      await repo.setNotebookOrder(
        n.id,
        orderBetween(before, onNotebook.sortOrder),
      );
    }
  }

  bool _accepts(
    _Dragged dragged, {
    Notebook? onNotebook,
    NotebookGroup? onGroup,
  }) {
    if (onGroup != null) {
      final g = dragged.group;
      return g == null ||
          (g.id != onGroup.id &&
              !shelf.descendantGroupIds(g.id).contains(onGroup.id));
    }
    return dragged.notebook != null &&
        dragged.notebook!.id != onNotebook!.id &&
        prefs.sort == ShelfSort.custom;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = prefs.layout == ShelfLayout.list;
    final items = <Widget>[
      for (final g in contents.groups)
        _DropTarget(
          accepts: (d) => _accepts(d, onGroup: g),
          onDrop: (d) => _drop(ref, d, onGroup: g),
          builder: (highlight) => _Draggable(
            data: (notebook: null, group: g),
            cover: GroupStackView(
              covers: [for (final n in shelf.notebooksIn(g)) n.cover],
            ),
            child: _GroupTile(
              group: g,
              count: shelf.notebooksIn(g).length,
              covers: [for (final n in shelf.notebooksIn(g)) n.cover],
              list: list,
              highlight: highlight,
            ),
          ),
        ),
      for (final n in contents.notebooks)
        _DropTarget(
          accepts: (d) => _accepts(d, onNotebook: n),
          onDrop: (d) => _drop(ref, d, onNotebook: n),
          builder: (highlight) => _Draggable(
            data: (notebook: n, group: null),
            cover: CoverView(cover: n.cover),
            child: _NotebookTile(
              notebook: n,
              subtitle: subtitle,
              list: list,
              highlight: highlight,
            ),
          ),
        ),
    ];

    const padding = EdgeInsets.fromLTRB(16, 16, 16, 96);
    if (list) {
      return ListView(padding: padding, children: items);
    }
    final large = prefs.size == ShelfSize.large;
    return GridView(
      padding: padding,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: large ? 200 : 136,
        mainAxisSpacing: 20,
        crossAxisSpacing: 20,
        childAspectRatio: large ? 0.56 : 0.5,
      ),
      children: items,
    );
  }
}

class _Draggable extends StatelessWidget {
  const _Draggable({
    required this.data,
    required this.cover,
    required this.child,
  });

  final _Dragged data;
  final Widget cover;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LongPressDraggable<_Dragged>(
      data: data,
      feedback: SizedBox(
        width: 110,
        child: Opacity(opacity: 0.85, child: cover),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: child),
      child: child,
    );
  }
}

class _DropTarget extends StatelessWidget {
  const _DropTarget({
    required this.accepts,
    required this.onDrop,
    required this.builder,
  });

  final bool Function(_Dragged) accepts;
  final void Function(_Dragged) onDrop;
  final Widget Function(bool highlight) builder;

  @override
  Widget build(BuildContext context) {
    return DragTarget<_Dragged>(
      onWillAcceptWithDetails: (d) => accepts(d.data),
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, hovering, _) => builder(hovering.isNotEmpty),
    );
  }
}

class _NotebookTile extends ConsumerWidget {
  const _NotebookTile({
    required this.notebook,
    required this.subtitle,
    required this.list,
    required this.highlight,
  });

  final Notebook notebook;
  final ShelfSort subtitle;
  final bool list;
  final bool highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = subtitle == ShelfSort.lastOpened
        ? (notebook.lastOpenedAt == null
              ? 'Not opened yet'
              : 'Opened ${shortDate(notebook.lastOpenedAt!)}')
        : 'Edited ${shortDate(notebook.updatedAt)}';
    final menu = PopupMenuButton<NotebookAction>(
      tooltip: 'Notebook options',
      onSelected: (a) => onNotebookAction(context, ref, notebook, a),
      itemBuilder: (context) => const [
        PopupMenuItem(value: NotebookAction.rename, child: Text('Rename')),
        PopupMenuItem(value: NotebookAction.color, child: Text('Change color')),
        PopupMenuItem(value: NotebookAction.move, child: Text('Move to…')),
        PopupMenuItem(value: NotebookAction.delete, child: Text('Delete')),
      ],
    );
    return _Tile(
      label: '${notebook.title} notebook',
      title: notebook.title,
      subtitle: date,
      cover: CoverView(cover: notebook.cover),
      menu: menu,
      list: list,
      highlight: highlight,
      onTap: () => context.push('/notebooks/${notebook.id}'),
    );
  }
}

class _GroupTile extends ConsumerWidget {
  const _GroupTile({
    required this.group,
    required this.count,
    required this.covers,
    required this.list,
    required this.highlight,
  });

  final NotebookGroup group;
  final int count;
  final List<NotebookCover> covers;
  final bool list;
  final bool highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menu = PopupMenuButton<GroupAction>(
      tooltip: 'Group options',
      onSelected: (a) => onGroupAction(context, ref, group, a),
      itemBuilder: (context) => const [
        PopupMenuItem(value: GroupAction.rename, child: Text('Rename')),
        PopupMenuItem(value: GroupAction.move, child: Text('Move to…')),
        PopupMenuItem(value: GroupAction.delete, child: Text('Delete group')),
      ],
    );
    return _Tile(
      label: '${group.title} group',
      title: group.title,
      subtitle: count == 1 ? '1 notebook' : '$count notebooks',
      cover: GroupStackView(covers: covers),
      menu: menu,
      list: list,
      highlight: highlight,
      onTap: () => context.go(InGroup(group.id).path),
    );
  }
}

/// A cover with its title and a short subtitle, in a grid or a list.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.title,
    required this.subtitle,
    required this.cover,
    required this.menu,
    required this.list,
    required this.highlight,
    required this.onTap,
  });

  final String label;
  final String title;
  final String subtitle;
  final Widget cover;
  final Widget menu;
  final bool list;

  /// Something is being dragged over this tile and can be dropped here.
  final bool highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      color: highlight
          ? theme.colorScheme.primary.withValues(alpha: 0.12)
          : null,
    );

    if (list) {
      return Semantics(
        button: true,
        label: label,
        child: DecoratedBox(
          decoration: decoration,
          child: ListTile(
            leading: SizedBox(width: 40, child: cover),
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(subtitle),
            trailing: menu,
            onTap: onTap,
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      label: label,
      child: DecoratedBox(
        decoration: decoration,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: Center(child: cover)),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 32, height: 32, child: menu),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyShelf extends ConsumerWidget {
  const _EmptyShelf({required this.location, required this.isFirstNotebook});

  final ShelfLocation location;

  /// The user has no notebooks anywhere yet.
  final bool isFirstNotebook;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final (title, message) = switch (location) {
      RecentNotebooks() => (
        'Nothing opened yet',
        'Notebooks you open show up here.',
      ),
      _ when isFirstNotebook => (
        'No notebooks yet',
        'Create a notebook to start writing.',
      ),
      _ => ('Nothing here yet', 'Create a notebook, or move one here.'),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (location is! RecentNotebooks) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => createNotebookAt(context, ref, location),
                icon: const Icon(Icons.add),
                label: const Text('Create a notebook'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "today", "yesterday", "Oct 3", or "Oct 3, 2025" for other years.
String shortDate(int millis, {DateTime? now}) {
  final date = DateTime.fromMillisecondsSinceEpoch(millis);
  final today = now ?? DateTime.now();
  final days = DateTime(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime(date.year, date.month, date.day)).inDays;
  if (days == 0) return 'today';
  if (days == 1) return 'yesterday';
  final day = '${_months[date.month - 1]} ${date.day}';
  return date.year == today.year ? day : '$day, ${date.year}';
}
