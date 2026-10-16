import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/shell.dart';
import '../notebooks/domain/notebook_models.dart';
import '../notebooks/notes_providers.dart';
import '../store/store_screen.dart';
import 'cover_view.dart';
import 'shelf_actions.dart';
import 'shelf_prefs.dart';
import 'shelf_view.dart';
import '../imports/open_in.dart';

/// The shelf, laid out like Noteshelf's home: a big title, quick actions,
/// then notebooks shown by their covers with groups as stacks. Shows Home
/// (everything), recent, starred, unfiled, the Trash, one category or one
/// group.
class ShelfScreen extends ConsumerStatefulWidget {
  const ShelfScreen({this.location = const AllNotebooks(), super.key});

  final ShelfLocation location;

  @override
  ConsumerState<ShelfScreen> createState() => _ShelfScreenState();
}

class _ShelfScreenState extends ConsumerState<ShelfScreen> {
  /// The search text, or null when not searching.
  String? _query;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _importIncoming());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Makes a notebook of files sent from another app, if any are waiting.
  void _importIncoming() {
    if (!mounted || widget.location is! AllNotebooks) return;
    final files = ref.read(incomingFilesProvider.notifier).take();
    if (files.isEmpty) return;
    importNotebookAt(context, ref, widget.location, files: files);
  }

  void _toggleSearch() => setState(() {
    _search.clear();
    _query = _query == null ? '' : null;
  });

  @override
  Widget build(BuildContext context) {
    ref.listen(incomingFilesProvider, (_, files) {
      if (files.isNotEmpty) Future.microtask(_importIncoming);
    });
    final location = widget.location;
    final notebooks = ref.watch(notebooksProvider);
    final groups = ref.watch(groupsProvider);
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final prefs = ref.watch(shelfPrefsProvider);
    final shelf = Shelf(notebooks.value ?? const [], groups.value ?? const []);
    final hasSidebar = sidebarShown(context, ref);
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.medium;
    final query = _query;
    final searching = query != null && query.trim().isNotEmpty;

    final title = switch (location) {
      AllNotebooks() => 'Home',
      RecentNotebooks() => 'Recent',
      StarredNotebooks() => 'Starred',
      UnfiledNotebooks() => 'Unfiled',
      TrashedNotebooks() => 'Trash',
      InCategory(:final id) =>
        categories.where((c) => c.id == id).firstOrNull?.title ?? 'Category',
      InGroup(:final id) => shelf.group(id)?.title ?? 'Group',
    };

    String placeOf(Notebook n) {
      final id = shelf.categoryOfNotebook(n);
      if (id == null) return 'Unfiled';
      return categories.where((c) => c.id == id).firstOrNull?.title ??
          'Unfiled';
    }

    final List<Widget> content;
    if (notebooks case AsyncError(:final error)) {
      content = [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load notebooks.\n$error'),
            ),
          ),
        ),
      ];
    } else if (!notebooks.hasValue || !groups.hasValue) {
      content = const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    } else {
      final contents = searching
          ? ShelfContents(const [], shelf.search(query))
          : shelf.contents(location, prefs.sort);
      content = contents.isEmpty
          ? [
              SliverFillRemaining(
                hasScrollBody: false,
                child: searching
                    ? Center(child: Text('No notebooks match "$query".'))
                    : _EmptyShelf(
                        location: location,
                        isFirstNotebook: shelf.notebookCount == 0,
                      ),
              ),
            ]
          : [
              _ShelfItems(
                shelf: shelf,
                contents: contents,
                prefs: prefs,
                trash: location is TrashedNotebooks && !searching,
                subtitle: location is RecentNotebooks
                    ? ShelfSort.lastOpened
                    : prefs.sort,
                // Where each notebook is, when the list mixes places.
                placeOf: switch (location) {
                  _ when searching => placeOf,
                  AllNotebooks() ||
                  RecentNotebooks() ||
                  StarredNotebooks() => placeOf,
                  _ => null,
                },
              ),
            ];
    }

    return Scaffold(
      appBar: AppBar(
        leading: location is InGroup
            ? BackButton(
                onPressed: () => context.go(shelf.parentOf(location).path),
              )
            : null,
        title: query == null
            ? null
            : TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search notebooks',
                  border: InputBorder.none,
                ),
                onChanged: (text) => setState(() => _query = text),
              ),
        actions: [
          if (location is TrashedNotebooks && shelf.trashCount > 0)
            TextButton(
              onPressed: () => emptyTrash(
                context,
                ref,
                shelf.contents(location, prefs.sort).notebooks,
              ),
              child: const Text('Empty Trash'),
            ),
          if (location.canCreate) _AddMenu(location: location),
          IconButton(
            tooltip: query == null ? 'Search' : 'Close search',
            icon: Icon(query == null ? Icons.search : Icons.close),
            onPressed: _toggleSearch,
          ),
          const _ViewMenu(),
          if (!hasSidebar)
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
      bottomNavigationBar: location is AllNotebooks && wide && !searching
          ? const _DiscoverBanner()
          : null,
      body: CustomScrollView(
        slivers: [
          if (!searching)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      key: const Key('shelf-title'),
                      style: titleSerif(
                        ref,
                        Theme.of(context).textTheme.headlineLarge,
                      ),
                    ),
                    if (location is TrashedNotebooks) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Restore a notebook, or delete it for good.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (location.canCreate && !searching)
            SliverToBoxAdapter(child: _QuickActions(location: location)),
          ...content,
        ],
      ),
    );
  }
}

/// Quick note, New notebook and Templates, as a row of cards.
class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.location});

  final ShelfLocation location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = [
      (
        label: 'Quick note',
        icon: Icons.add,
        color: const Color(0xFF2E9C8F),
        onTap: () => createQuickNote(context, ref, location),
      ),
      (
        label: 'New notebook',
        icon: Icons.menu_book_outlined,
        color: const Color(0xFFC0812E),
        onTap: () => createNotebookAt(context, ref, location),
      ),
      (
        label: 'Import',
        icon: Icons.file_open_outlined,
        color: const Color(0xFF7B4FA0),
        onTap: () => importNotebookAt(context, ref, location),
      ),
      (
        label: 'Templates',
        icon: Icons.storefront_outlined,
        color: const Color(0xFF4C8BC9),
        onTap: () => context.push(storePath),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 480;
          return Row(
            children: [
              for (final (i, a) in actions.indexed) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  child: _QuickActionCard(
                    label: a.label,
                    icon: a.icon,
                    color: a.color,
                    stacked: stacked,
                    onTap: a.onTap,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.stacked,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;

  /// Icon above the label, for narrow screens.
  final bool stacked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badge = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 18, color: color),
    );
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelLarge,
    );
    return Material(
      color: theme.colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: stacked
              ? Column(children: [badge, const SizedBox(height: 6), text])
              : Row(
                  children: [
                    badge,
                    const SizedBox(width: 10),
                    Flexible(child: text),
                  ],
                ),
        ),
      ),
    );
  }
}

/// The + menu: everything that can be made here.
class _AddMenu extends ConsumerWidget {
  const _AddMenu({required this.location});

  final ShelfLocation location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<VoidCallback>(
      tooltip: 'New',
      icon: const Icon(Icons.add),
      onSelected: (create) => create(),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: () => createQuickNote(context, ref, location),
          child: const ListTile(
            leading: Icon(Icons.edit_note),
            title: Text('Quick note'),
          ),
        ),
        PopupMenuItem(
          value: () => createNotebookAt(context, ref, location),
          child: const ListTile(
            leading: Icon(Icons.menu_book_outlined),
            title: Text('Notebook'),
          ),
        ),
        PopupMenuItem(
          value: () => importNotebookAt(context, ref, location),
          child: const ListTile(
            leading: Icon(Icons.file_open_outlined),
            title: Text('Import PDF or images'),
          ),
        ),
        PopupMenuItem(
          value: () => createGroupAt(context, ref, location),
          child: const ListTile(
            leading: Icon(Icons.create_new_folder_outlined),
            title: Text('Group'),
          ),
        ),
        if (location is! InGroup)
          PopupMenuItem(
            value: () => createCategory(context, ref),
            child: const ListTile(
              leading: Icon(Icons.label_outline),
              title: Text('Category'),
            ),
          ),
      ],
    );
  }
}

/// The strip along the bottom of Home that leads to the store.
class _DiscoverBanner extends StatelessWidget {
  const _DiscoverBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Material(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.auto_awesome_outlined),
            title: Text(
              'Discover templates and collections',
              style: theme.textTheme.labelLarge,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(storePath),
          ),
        ),
      ),
    );
  }
}

/// Places and categories as chips, for when the sidebar is hidden.
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
      // Not lazy: there are only a few, and all of them stay reachable.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Row(
          children: [
            chip('Home', const AllNotebooks()),
            chip('Starred', const StarredNotebooks()),
            chip('Recent', const RecentNotebooks()),
            chip('Unfiled', const UnfiledNotebooks()),
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
            chip('Trash', const TrashedNotebooks()),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Category'),
              tooltip: 'New category',
              onPressed: () => createCategory(context, ref),
            ),
          ],
        ),
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
      icon: const Icon(Icons.more_horiz),
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
    this.trash = false,
    this.placeOf,
  });

  final Shelf shelf;
  final ShelfContents contents;
  final ShelfPrefs prefs;

  /// Which date notebooks show under their title.
  final ShelfSort subtitle;

  /// These are in the Trash: they can be restored, not opened or moved.
  final bool trash;

  /// Names where a notebook is (its category, or "Unfiled"), when the
  /// list mixes places.
  final String Function(Notebook)? placeOf;

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
      if (trash)
        for (final n in contents.notebooks)
          _TrashedTile(notebook: n, list: list)
      else
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
                place: placeOf?.call(n),
                list: list,
                highlight: highlight,
              ),
            ),
          ),
    ];

    const padding = EdgeInsets.fromLTRB(16, 4, 16, 32);
    if (list) {
      return SliverPadding(
        padding: padding,
        sliver: SliverList.list(children: items),
      );
    }
    final large = prefs.size == ShelfSize.large;
    return SliverPadding(
      padding: padding,
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: large ? 200 : 136,
          mainAxisSpacing: 20,
          crossAxisSpacing: 20,
          childAspectRatio: large ? 0.52 : 0.46,
        ),
        delegate: SliverChildListDelegate(items),
      ),
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
    this.place,
  });

  final Notebook notebook;
  final ShelfSort subtitle;

  /// Where the notebook is, shown under the date.
  final String? place;
  final bool list;
  final bool highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = switch (notebook.lastPageTitle) {
      // Where it will open.
      final page? => 'Continue · $page',
      null when subtitle == ShelfSort.lastOpened =>
        notebook.lastOpenedAt == null
            ? 'Not opened yet'
            : shortDateTime(notebook.lastOpenedAt!),
      null => shortDateTime(notebook.updatedAt),
    };
    final menu = PopupMenuButton<NotebookAction>(
      tooltip: 'Notebook options',
      onSelected: (a) => onNotebookAction(context, ref, notebook, a),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: NotebookAction.rename,
          child: Text('Rename'),
        ),
        const PopupMenuItem(
          value: NotebookAction.edit,
          child: Text('Cover, paper & style'),
        ),
        const PopupMenuItem(
          value: NotebookAction.move,
          child: Text('Move to…'),
        ),
        PopupMenuItem(
          value: NotebookAction.star,
          child: Text(notebook.starred ? 'Unstar' : 'Star'),
        ),
        const PopupMenuItem(
          value: NotebookAction.trash,
          child: Text('Move to Trash'),
        ),
      ],
    );
    return _Tile(
      label: '${notebook.title} notebook',
      title: notebook.title,
      subtitle: date,
      place: place,
      starred: notebook.starred,
      cover: CoverView(cover: notebook.cover),
      menu: menu,
      list: list,
      highlight: highlight,
      onTap: () => openNotebook(context, ref, notebook),
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
    this.place,
    this.starred = false,
  });

  final String label;
  final String title;
  final String subtitle;

  /// A third line: where it is on the shelf.
  final String? place;
  final bool starred;
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

    const star = Padding(
      padding: EdgeInsets.only(left: 4),
      child: Icon(
        Icons.star,
        size: 14,
        color: Color(0xFFC79A2E),
        semanticLabel: 'Starred',
      ),
    );

    if (list) {
      return Semantics(
        button: true,
        label: label,
        child: DecoratedBox(
          decoration: decoration,
          child: ListTile(
            leading: SizedBox(width: 40, child: cover),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (starred) star,
              ],
            ),
            subtitle: Text(place == null ? subtitle : '$subtitle · $place'),
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
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                              if (starred) star,
                            ],
                          ),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                          if (place case final place?)
                            Text(
                              place,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
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

/// A notebook in the Trash: tapping offers to restore or delete it.
class _TrashedTile extends ConsumerWidget {
  const _TrashedTile({required this.notebook, required this.list});

  final Notebook notebook;
  final bool list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menu = PopupMenuButton<TrashAction>(
      tooltip: 'Notebook options',
      onSelected: (a) => onTrashedNotebookAction(context, ref, notebook, a),
      itemBuilder: (context) => const [
        PopupMenuItem(value: TrashAction.restore, child: Text('Restore')),
        PopupMenuItem(
          value: TrashAction.delete,
          child: Text('Delete for good'),
        ),
      ],
    );
    return _Tile(
      label: '${notebook.title} notebook, in the Trash',
      title: notebook.title,
      subtitle: 'Deleted ${shortDate(notebook.trashedAt!)}',
      cover: Opacity(opacity: 0.6, child: CoverView(cover: notebook.cover)),
      menu: menu,
      list: list,
      highlight: false,
      onTap: () => _ask(context, ref),
    );
  }

  Future<void> _ask(BuildContext context, WidgetRef ref) async {
    final action = await showDialog<TrashAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('"${notebook.title}" is in the Trash'),
        content: const Text('Restore it to open it again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, TrashAction.delete),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete for good'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, TrashAction.restore),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (action != null && context.mounted) {
      await onTrashedNotebookAction(context, ref, notebook, action);
    }
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
      StarredNotebooks() => (
        'No starred notebooks',
        'Star a notebook from its ⋯ menu to find it here.',
      ),
      TrashedNotebooks() => (
        'The Trash is empty',
        'Notebooks you delete wait here, so you can restore them.',
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
            if (location.canCreate) ...[
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

/// "Today, 5:39 AM", "Oct 3, 5:39 AM", or "Oct 3, 2025" for other years.
String shortDateTime(int millis, {DateTime? now}) {
  final date = DateTime.fromMillisecondsSinceEpoch(millis);
  final today = now ?? DateTime.now();
  final day = shortDate(millis, now: today);
  if (date.year != today.year) return day;
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final time = '$hour:$minute ${date.hour < 12 ? 'AM' : 'PM'}';
  return '${day[0].toUpperCase()}${day.substring(1)}, $time';
}
