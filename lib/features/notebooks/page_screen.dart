import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/shell.dart' show Breakpoints;
import '../../core/motion/page_turn.dart';
import '../../core/skins/skin_providers.dart';
import '../../core/sync/sync_indicator.dart';
import '../../core/skins/widgets/page_style.dart';
import '../../shared/dialogs.dart';
import '../canvas/ink_toolbar.dart';
import '../canvas/page_canvas.dart';
import '../canvas/ink_stats.dart';
import '../canvas/pen_rail.dart';
import '../canvas/toolbar_layout.dart';
import '../audio/audio_bar.dart';
import '../canvas/zoom_window.dart';
import '../canvas/templates.dart' show templateImageProvider;
import '../exports/export_sheet.dart';
import '../shelf/tag_editor.dart';
import '../tasks/task_providers.dart' show todayProvider;
import 'domain/notebook_models.dart';
import 'notes_providers.dart';
import 'open_page.dart';
import 'page_jumper.dart';
import 'page_order.dart';
import 'paper_picker.dart';
import 'vertical_pages.dart';

/// A single page: handwriting on phones and tablets, view-only on the web.
class PageScreen extends ConsumerWidget {
  const PageScreen({
    required this.pageId,
    this.readOnly = false,
    this.inkEnabled = !kIsWeb,
    super.key,
  });

  final String pageId;

  /// Nothing can be changed.
  final bool readOnly;

  /// Handwriting can be added. Off on the web, where text boxes, photos
  /// and stickers can still be added and changed.
  final bool inkEnabled;

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    String pageId,
    String current,
  ) async {
    final title = await askForText(
      context,
      title: 'Page title',
      confirmLabel: 'Save',
      initialValue: current,
    );
    if (title != null) {
      await ref.read(notebookRepositoryProvider).renamePage(pageId, title);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Scrolling vertically, the title and tools follow the page in view.
    final vertical = ref.watch(pageScrollProvider) == PageScroll.vertical;
    final routeNotebookId = ref
        .watch(pageProvider(this.pageId))
        .value
        ?.notebookId;
    final pageId = vertical && routeNotebookId != null
        ? ref.watch(visiblePageProvider(routeNotebookId)) ?? this.pageId
        : this.pageId;
    final page = ref.watch(pageProvider(pageId));

    if (page case AsyncData(value: null)) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This page was deleted.')),
      );
    }

    final title = page.value?.title ?? '';
    // While a page scrolled into view loads, the notebook is still the one
    // opened: the list of pages must stay put, not be rebuilt at the start.
    final notebookId = page.value?.notebookId ?? routeNotebookId;
    final order = notebookId == null
        ? const <String>[]
        : ref.watch(notebookPageOrderProvider(notebookId));
    final adjacent = adjacentPages(order, pageId);
    final pages = notebookId == null
        ? const <NotePage>[]
        : ref.watch(orderedPagesProvider(notebookId));
    final dated = pages.any((p) => p.period != null);
    final bookmarked = page.value?.bookmarked ?? false;
    // Replaces this page, so Back still goes where it went before (the
    // shelf, when the notebook was opened from there).
    void openPage(String id) {
      if (id == pageId) return;
      if (vertical && notebookId != null) {
        ref.read(pageJumpProvider(notebookId).notifier).to(id);
        return;
      }
      final extra = GoRouterState.of(context).extra;
      void go() =>
          context.replace('/notebooks/$notebookId/pages/$id', extra: extra);
      // Neighbours are loaded already; give a page further away a moment
      // to load, so it doesn't appear half drawn mid-turn.
      if (id == adjacent.previous || id == adjacent.next) return go();
      final warm = warmPage(ProviderScope.containerOf(context), id);
      warm.ready.then((_) {
        if (context.mounted) go();
        WidgetsBinding.instance.addPostFrameCallback((_) => warm.close());
      });
    }

    void openToday() {
      final now = ref.read(todayProvider).toDateTime();
      final today = todaysPage(pages, now);
      if (today != null) return openPage(today.id);
      final nearest = nearestDatedPage(pages, now);
      if (nearest == null) return;
      final start = nearest.period!.from;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              start != null && start.isAfter(now)
                  ? 'This planner starts in ${_monthYear(start)}.'
                  : 'This planner has no page for today.',
            ),
          ),
        );
      openPage(nearest.id);
    }

    // Each page keeps its own paper while it turns.
    Widget turnPage(String id) => Consumer(
      builder: (context, ref, _) => PageStyle(
        style: ref.watch(pageStyleProvider(id)),
        child: PageCanvas(
          pageId: id,
          readOnly: readOnly,
          inkEnabled: inkEnabled,
          onOpenPage: openPage,
        ),
      ),
    );

    // Writing large below, landing small on the page. Not while the pages
    // scroll in a list.
    final zoomWindow =
        ref.watch(zoomWindowProvider) && !readOnly && inkEnabled && !vertical;
    final pageView = vertical && notebookId != null
        ? VerticalPages(
            notebookId: notebookId,
            order: order,
            startPageId: this.pageId,
            readOnly: readOnly,
            inkEnabled: inkEnabled,
          )
        : PageTurnSwitcher(
            pageKey: pageId,
            order: order,
            style: ref.watch(pageTurnStyleProvider),
            pageBuilder: (id) => turnPage(id as String),
            onTurned: (id) => openPage(id as String),
            child: turnPage(pageId),
          );

    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.medium;
    Future<void> choosePaper() => choosePagePaper(context, ref, page.value!);

    void toggleBookmark() => ref
        .read(notebookRepositoryProvider)
        .setPageBookmarked(pageId, !bookmarked);
    final theme = Theme.of(context);
    final notebook = notebookId == null
        ? null
        : ref.watch(notebookProvider(notebookId)).value;
    final notebookTitle = notebook?.title ?? '';
    final tagged = notebook?.tags.isNotEmpty ?? false;
    void tags() => editTags(context, notebookId!);

    Future<void> jump() async {
      if (notebookId == null) return;
      final to = await showPageJumper(
        context,
        notebookId: notebookId,
        currentPageId: pageId,
      );
      if (!context.mounted) return;
      switch (to) {
        case JumpToPage(:final pageId):
          openPage(pageId);
        case JumpToAllPages():
          context.go('/notebooks/$notebookId');
        case null:
      }
    }

    return PageStyle(
      style: ref.watch(pageStyleProvider(pageId)),
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          // The notebook, with the page under it. Tapping it opens Go to
          // page, as the title does in most notebook apps.
          title: Semantics(
            button: true,
            hint: 'Go to page',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: jump,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      notebookTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      page.value?.displayTitle ?? '',
                      key: const Key('page-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            const SyncIndicator(),
            // Finding a page.
            if (wide) ...[
              if (dated)
                IconButton(
                  tooltip: 'Today',
                  icon: const Icon(Icons.today),
                  onPressed: openToday,
                ),
              IconButton(
                tooltip: 'Go to page',
                icon: const Icon(Icons.auto_stories_outlined),
                onPressed: jump,
              ),
              if (!readOnly && page.value != null)
                IconButton(
                  tooltip: bookmarked ? 'Remove bookmark' : 'Bookmark page',
                  isSelected: bookmarked,
                  icon: Icon(
                    bookmarked ? Icons.bookmark : Icons.bookmark_border,
                  ),
                  onPressed: toggleBookmark,
                ),
              if (!readOnly && notebookId != null)
                IconButton(
                  tooltip: 'Tags',
                  isSelected: tagged,
                  icon: Icon(tagged ? Icons.sell : Icons.sell_outlined),
                  onPressed: tags,
                ),
              const SizedBox(width: 12),
            ],
            // Turning pages.
            IconButton(
              tooltip: 'Previous page',
              icon: const Icon(Icons.chevron_left),
              onPressed: adjacent.previous == null
                  ? null
                  : () => openPage(adjacent.previous!),
            ),
            IconButton(
              tooltip: 'Next page',
              icon: const Icon(Icons.chevron_right),
              onPressed: adjacent.next == null
                  ? null
                  : () => openPage(adjacent.next!),
            ),
            if (wide) const SizedBox(width: 12),
            // The page itself.
            if (notebookId != null)
              ExportButton(notebookId: notebookId, pageId: pageId),
            PopupMenuButton<VoidCallback>(
              tooltip: 'Page options',
              icon: const Icon(Icons.more_horiz),
              onSelected: (action) => action(),
              itemBuilder: (context) => [
                // Phones have room for fewer buttons.
                if (!wide && dated)
                  PopupMenuItem(
                    value: openToday,
                    child: const ListTile(
                      leading: Icon(Icons.today),
                      title: Text('Today'),
                    ),
                  ),
                if (!wide && !readOnly && page.value != null)
                  PopupMenuItem(
                    value: toggleBookmark,
                    child: ListTile(
                      leading: Icon(
                        bookmarked ? Icons.bookmark : Icons.bookmark_border,
                      ),
                      title: Text(
                        bookmarked ? 'Remove bookmark' : 'Bookmark page',
                      ),
                    ),
                  ),
                if (!wide && !readOnly && notebookId != null)
                  PopupMenuItem(
                    value: tags,
                    child: ListTile(
                      leading: Icon(tagged ? Icons.sell : Icons.sell_outlined),
                      title: const Text('Tags…'),
                    ),
                  ),
                if (!readOnly && page.value != null)
                  PopupMenuItem(
                    value: () => _rename(context, ref, pageId, title),
                    child: const ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Rename page'),
                    ),
                  ),
                if (!readOnly && page.value != null)
                  PopupMenuItem(
                    value: choosePaper,
                    child: const ListTile(
                      leading: Icon(Icons.texture),
                      title: Text('Page paper'),
                    ),
                  ),
                PopupMenuItem(
                  value: () => ref
                      .read(pageScrollProvider.notifier)
                      .set(vertical ? PageScroll.pages : PageScroll.vertical),
                  child: ListTile(
                    leading: Icon(
                      vertical
                          ? Icons.auto_stories_outlined
                          : Icons.view_day_outlined,
                    ),
                    title: Text(
                      vertical ? 'Show page by page' : 'Scroll vertically',
                    ),
                  ),
                ),
                if (!readOnly)
                  PopupMenuItem(
                    value: () => showToolbarEditor(context),
                    child: const ListTile(
                      leading: Icon(Icons.handyman_outlined),
                      title: Text('Customize toolbar'),
                    ),
                  ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            _MarkOpened(pageId: pageId),
            if (!vertical)
              _Preload(pageIds: [?adjacent.previous, ?adjacent.next]),
            if (!inkEnabled) const _ViewOnlyBanner(),
            if (!readOnly) InkToolbar(pageId: pageId, inkEnabled: inkEnabled),
            if (notebookId != null) AudioBar(notebookId: notebookId),
            const Divider(height: 1),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: pageView),
                  if (!readOnly && inkEnabled)
                    const Positioned.fill(child: PenRail()),
                  const Positioned.fill(child: InkStatsReadout()),
                ],
              ),
            ),
            if (zoomWindow)
              SizedBox(
                height: (MediaQuery.sizeOf(context).height * 0.28).clamp(
                  160.0,
                  300.0,
                ),
                child: ZoomWindowPanel(key: ValueKey(pageId), pageId: pageId),
              ),
          ],
        ),
      ),
    );
  }
}

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', //
  'August', 'September', 'October', 'November', 'December',
];

String _monthYear(DateTime d) => '${_monthNames[d.month - 1]} ${d.year}';

/// Keeps [pageIds] loaded (template drawn, ink and items read), so turning
/// to them shows them complete at once.
class _Preload extends ConsumerWidget {
  const _Preload({required this.pageIds});

  final List<String> pageIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    for (final id in pageIds) {
      ref.listen(strokesProvider(id), (_, _) {});
      ref.listen(elementsProvider(id), (_, _) {});
      final template = ref.watch(
        pageProvider(id).select((p) => p.value?.template),
      );
      if (template != null) {
        ref.listen(
          templateImageProvider((template: template, width: templateDrawWidth)),
          (_, _) {},
        );
      }
    }
    return const SizedBox.shrink();
  }
}

/// Starts loading page [id], waiting at most [limit] for its template to be
/// drawn. Close it once the page is showing (it holds the page loaded until
/// then).
({Future<void> ready, void Function() close}) warmPage(
  ProviderContainer container,
  String id, {
  Duration limit = const Duration(milliseconds: 120),
}) {
  final subs = <ProviderSubscription<Object?>>[
    container.listen(strokesProvider(id), (_, _) {}),
    container.listen(elementsProvider(id), (_, _) {}),
  ];
  Future<void> load() async {
    final page = await container.read(pageProvider(id).future);
    final template = page?.template;
    if (template == null) return;
    final key = (template: template, width: templateDrawWidth);
    subs.add(container.listen(templateImageProvider(key), (_, _) {}));
    await container.read(templateImageProvider(key).future);
  }

  return (
    ready: load().timeout(limit).catchError((_) {}),
    close: () {
      for (final s in subs) {
        s.close();
      }
    },
  );
}

/// Records each page shown, so its notebook opens there next time.
class _MarkOpened extends ConsumerStatefulWidget {
  const _MarkOpened({required this.pageId});

  final String pageId;

  @override
  ConsumerState<_MarkOpened> createState() => _MarkOpenedState();
}

class _MarkOpenedState extends ConsumerState<_MarkOpened> {
  String? _marked;

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(pageProvider(widget.pageId)).value;
    if (page != null && _marked != page.id) {
      _marked = page.id;
      // After the frame: not while building.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(notebookRepositoryProvider).markPageOpened(page);
        }
      });
    }
    return const SizedBox.shrink();
  }
}

class _ViewOnlyBanner extends StatelessWidget {
  const _ViewOnlyBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        'Handwriting is view-only on the web. You can add and edit text, '
        'photos and stickers here; write with the Jotswift app on your phone '
        'or tablet.',
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}
