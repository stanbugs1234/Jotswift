import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/dialogs.dart';
import '../canvas/page_canvas.dart';
import 'domain/notebook_models.dart';
import 'notes_providers.dart';
import 'page_actions.dart';
import 'paper_picker.dart';
import '../../core/motion/motion.dart';

/// An order between [before] and [after] (either may be missing, at the
/// start or end of a section).
double orderBetween(double? before, double? after) => switch ((before, after)) {
  (null, null) => 1,
  (null, final a?) => a - 1,
  (final b?, null) => b + 1,
  (final b?, final a?) => (b + a) / 2,
};

/// The order a page gets when [moving] is dropped on [target], among a
/// section's [pages] (sorted): it takes [target]'s place, and [target]
/// shifts away from where [moving] came from.
double orderForDrop(List<NotePage> pages, NotePage moving, NotePage target) {
  final from = pages.indexWhere((p) => p.id == moving.id);
  final to = pages.indexWhere((p) => p.id == target.id);
  if (from == -1 || from > to) {
    // Moving up (or in from elsewhere): just before the target.
    final before = to > 0 ? pages[to - 1] : null;
    return orderBetween(
      before?.id == moving.id ? null : before?.order,
      target.order,
    );
  }
  // Moving down: just after the target.
  final after = to + 1 < pages.length ? pages[to + 1] : null;
  return orderBetween(target.order, after?.order);
}

/// A section's pages as thumbnails: tap to open, hold and drag to reorder,
/// and a menu on each to rename, change paper, duplicate, move, copy or
/// delete.
class PageGrid extends ConsumerWidget {
  const PageGrid({
    required this.notebookId,
    required this.section,
    required this.onOpen,
    required this.onCreate,
    super.key,
  });

  final String notebookId;
  final Section section;
  final ValueChanged<String> onOpen;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pages = ref
        .watch(pagesProvider((notebookId: notebookId, sectionId: section.id)))
        .value;
    if (pages == null) return const Center(child: CircularProgressIndicator());
    if (pages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('No pages in ${section.title} yet.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Add a page'),
            ),
          ],
        ),
      );
    }
    final size = ref.watch(pageDimensionsProvider(pages.first.id));
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        // The page, then two lines for its title.
        childAspectRatio: size.width / (size.height + size.width * 0.32),
      ),
      itemCount: pages.length,
      itemBuilder: (context, i) => _PageTile(
        key: ValueKey(pages[i].id),
        page: pages[i],
        pages: pages,
        notebookId: notebookId,
        onOpen: onOpen,
      ),
    );
  }
}

class _PageTile extends ConsumerWidget {
  const _PageTile({
    required this.page,
    required this.pages,
    required this.notebookId,
    required this.onOpen,
    super.key,
  });

  final NotePage page;
  final List<NotePage> pages;
  final String notebookId;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final thumbnail = _Thumbnail(page: page);
    return DragTarget<NotePage>(
      onWillAcceptWithDetails: (d) => d.data.id != page.id,
      onAcceptWithDetails: (d) => ref
          .read(notebookRepositoryProvider)
          .movePage(
            d.data.id,
            notebookId: notebookId,
            sectionId: page.sectionId,
            order: orderForDrop(pages, d.data, page),
          ),
      builder: (context, candidates, _) => LongPressDraggable<NotePage>(
        data: page,
        feedback: SizedBox(
          width: 120,
          child: Opacity(opacity: 0.85, child: thumbnail),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: thumbnail),
        child: Semantics(
          button: true,
          label: page.displayTitle,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => onOpen(page.id),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: AnimatedContainer(
                    duration: Motion.of(context).duration(MotionTokens.quick),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: candidates.isNotEmpty
                            ? theme.colorScheme.primary
                            : Colors.transparent,
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        thumbnail,
                        if (page.bookmarked)
                          Positioned(
                            top: 0,
                            right: 8,
                            child: Icon(
                              Icons.bookmark,
                              size: 22,
                              color: theme.colorScheme.error,
                              semanticLabel: 'Bookmarked',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        page.displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                    _PageMenu(page: page, pages: pages, notebookId: notebookId),
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

/// A small picture of a page, as it's printed.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.page});

  final NotePage page;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.14),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: ClipRect(
      child: RepaintBoundary(
        child: FittedBox(child: PagePrint(pageId: page.id, templateWidth: 360)),
      ),
    ),
  );
}

enum _PageAction { rename, template, paper, duplicate, move, copy, delete }

class _PageMenu extends ConsumerWidget {
  const _PageMenu({
    required this.page,
    required this.pages,
    required this.notebookId,
  });

  final NotePage page;
  final List<NotePage> pages;
  final String notebookId;

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    _PageAction action,
  ) async {
    final repo = ref.read(notebookRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    switch (action) {
      case _PageAction.rename:
        final title = await askForText(
          context,
          title: 'Rename page',
          confirmLabel: 'Rename',
          initialValue: page.title,
        );
        if (title != null) await repo.renamePage(page.id, title);
      case _PageAction.template:
        await changePageTemplate(context, ref, page);
      case _PageAction.paper:
        await choosePagePaper(context, ref, page);
      case _PageAction.duplicate:
        final i = pages.indexWhere((p) => p.id == page.id);
        await repo.copyPage(
          page.id,
          notebookId: notebookId,
          sectionId: page.sectionId,
          order: orderBetween(
            page.order,
            i + 1 < pages.length ? pages[i + 1].order : null,
          ),
        );
      case _PageAction.move || _PageAction.copy:
        final copy = action == _PageAction.copy;
        final to = await showPageDestinationSheet(
          context,
          title: copy ? 'Copy page to' : 'Move page to',
        );
        if (to == null) return;
        final there = await repo.watchPages(to.notebookId, to.sectionId).first;
        final order = orderBetween(there.lastOrNull?.order, null);
        if (copy) {
          await repo.copyPage(
            page.id,
            notebookId: to.notebookId,
            sectionId: to.sectionId,
            order: order,
          );
        } else {
          await repo.movePage(
            page.id,
            notebookId: to.notebookId,
            sectionId: to.sectionId,
            order: order,
          );
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${copy ? 'Copied' : 'Moved'} to ${to.notebookTitle} · '
              '${to.sectionTitle}',
            ),
          ),
        );
      case _PageAction.delete:
        final ok = await confirmDelete(
          context,
          title: 'Delete "${page.displayTitle}"?',
          message: 'This deletes the page and everything written on it.',
        );
        if (ok) await repo.deletePage(page.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      PopupMenuButton<_PageAction>(
        tooltip: 'Page options',
        padding: EdgeInsets.zero,
        iconSize: 20,
        onSelected: (a) => _act(context, ref, a),
        itemBuilder: (context) => const [
          PopupMenuItem(value: _PageAction.rename, child: Text('Rename')),
          PopupMenuItem(
            value: _PageAction.template,
            child: Text('Change template…'),
          ),
          PopupMenuItem(value: _PageAction.paper, child: Text('Change paper')),
          PopupMenuItem(value: _PageAction.duplicate, child: Text('Duplicate')),
          PopupMenuItem(value: _PageAction.move, child: Text('Move to…')),
          PopupMenuItem(value: _PageAction.copy, child: Text('Copy to…')),
          PopupMenuItem(value: _PageAction.delete, child: Text('Delete')),
        ],
      );
}

/// Where a page goes: a section of a notebook.
typedef PageDestination = ({
  String notebookId,
  String notebookTitle,
  String sectionId,
  String sectionTitle,
});

/// Asks for a notebook, then one of its sections. Returns null if
/// cancelled.
Future<PageDestination?> showPageDestinationSheet(
  BuildContext context, {
  required String title,
}) => showModalBottomSheet<PageDestination>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => _DestinationSheet(title: title),
);

class _DestinationSheet extends ConsumerStatefulWidget {
  const _DestinationSheet({required this.title});

  final String title;

  @override
  ConsumerState<_DestinationSheet> createState() => _DestinationSheetState();
}

class _DestinationSheetState extends ConsumerState<_DestinationSheet> {
  Notebook? _notebook;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notebook = _notebook;
    final List<Widget> rows;
    if (notebook == null) {
      final notebooks = [
        for (final n in ref.watch(notebooksProvider).value ?? <Notebook>[])
          if (!n.inTrash) n,
      ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      rows = [
        for (final n in notebooks)
          ListTile(
            leading: Icon(Icons.menu_book, color: Color(n.cover.color)),
            title: Text(n.title),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() => _notebook = n),
          ),
      ];
    } else {
      final sections = ref.watch(sectionsProvider(notebook.id)).value ?? [];
      rows = [
        ListTile(
          leading: const Icon(Icons.arrow_back),
          title: Text(notebook.title),
          onTap: () => setState(() => _notebook = null),
        ),
        const Divider(height: 1),
        for (final s in sections)
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(s.title),
            onTap: () => Navigator.pop(context, (
              notebookId: notebook.id,
              notebookTitle: notebook.title,
              sectionId: s.id,
              sectionTitle: s.title,
            )),
          ),
      ];
    }
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(widget.title, style: theme.textTheme.titleLarge),
            ),
            ...rows,
          ],
        ),
      ),
    );
  }
}
