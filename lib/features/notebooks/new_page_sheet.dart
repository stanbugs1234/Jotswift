import '../../shared/ui/skeleton.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/catalog/catalog_item.dart';
import '../../core/catalog/catalog_providers.dart';
import '../../core/catalog/template_spec.dart';
import '../../core/entitlements/entitlements.dart';
import '../../core/paper/paper_style.dart';
import '../../core/skins/widgets/paper.dart';
import '../canvas/page_canvas.dart' show PagePrint;
import '../canvas/templates.dart';
import '../store/store_item.dart';
import '../store/store_screen.dart';
import 'data/notes_repository.dart';
import 'domain/notebook_models.dart';
import 'notes_providers.dart' show myPageTemplatesProvider;
import 'template_filter.dart';
import 'template_picks.dart';

/// What the New page sheet chose.
sealed class NewPageChoice {
  const NewPageChoice();
}

/// A blank page on the notebook's paper.
class BlankPageChoice extends NewPageChoice {
  const BlankPageChoice();
}

/// A blank page on a paper still to be picked.
class OtherPaperChoice extends NewPageChoice {
  const OtherPaperChoice();
}

/// A page of a template.
class TemplatePageChoice extends NewPageChoice {
  const TemplatePageChoice(this.page);

  final NewPage page;
}

/// One of the user's own page templates: a copy of it, writing and all.
class MyPageChoice extends NewPageChoice {
  const MyPageChoice(this.page);

  final NotePage page;
}

/// A whole planner: all its pages, as new sections.
class WholePlannerChoice extends NewPageChoice {
  const WholePlannerChoice(this.item);

  final CatalogItem item;
}

/// Asks what kind of page to add: blank, another paper, or any page of any
/// template. Templates the user doesn't have yet are listed too and open
/// their store page. [search] starts the search with those words (e.g. a
/// template's name). [same] offers a page like the one being written on
/// first. [changing] asks for a page's new background instead of a new
/// page (so whole planners aren't offered). Returns null if cancelled.
Future<NewPageChoice?> showNewPageSheet(
  BuildContext context, {
  required PaperStyle paper,
  String? search,
  NewPage? same,
  bool changing = false,
}) => showModalBottomSheet<NewPageChoice>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => _NewPageSheet(
    paper: paper,
    search: search,
    same: same,
    changing: changing,
  ),
);

/// One row of the sheet.
sealed class _Row {
  const _Row();
}

class _Heading extends _Row {
  const _Heading(this.text);
  final String text;
}

class _Usable extends _Row {
  const _Usable(this.item);
  final CatalogItem item;
}

class _Locked extends _Row {
  const _Locked(this.item);
  final CatalogItem item;
}

class _NewPageSheet extends ConsumerStatefulWidget {
  const _NewPageSheet({
    required this.paper,
    this.search,
    this.same,
    this.changing = false,
  });

  final PaperStyle paper;
  final String? search;
  final NewPage? same;
  final bool changing;

  @override
  ConsumerState<_NewPageSheet> createState() => _NewPageSheetState();
}

class _NewPageSheetState extends ConsumerState<_NewPageSheet> {
  late var _filter = TemplateFilter(query: widget.search ?? '');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paper = widget.paper;
    ref
      ..watch(favoriteTemplatePagesProvider)
      ..watch(recentTemplatePagesProvider);
    final entitlements = ref.watch(entitlementsProvider);
    final templates = [
      for (final t in ref.watch(storeCatalogProvider))
        if (t.kind == CatalogKind.template && t.templateMode != null) t,
    ];
    final shown = templates.where(_filter.matches).toList();
    final usable = shown.where(entitlements.canUseCatalogItem).toList();
    final locked = shown.where((t) => !usable.contains(t)).toList();
    // Page packs first, then the pages of planners.
    usable.sort(
      (a, b) =>
          (a.templateMode == TemplateMode.pages ? 0 : 1) -
          (b.templateMode == TemplateMode.pages ? 0 : 1),
    );
    final rows = <_Row>[
      for (final item in usable) _Usable(item),
      if (locked.isNotEmpty) const _Heading('More in the store'),
      for (final item in locked) _Locked(item),
    ];

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.changing ? 'Change template' : 'New page',
                    style: theme.textTheme.titleLarge,
                  ),
                  if (templates.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    TemplateFilterBar(
                      templates: templates,
                      filter: _filter,
                      onChanged: (f) => setState(() => _filter = f),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: rows.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            if (widget.same case final same?)
                              _Tile(
                                label: 'Same as this page',
                                onTap: () => Navigator.pop(
                                  context,
                                  TemplatePageChoice(same),
                                ),
                                child: _PagePicture(page: same, paper: paper),
                              ),
                            _Tile(
                              label: widget.changing
                                  ? 'Plain paper'
                                  : 'Blank page',
                              onTap: () => Navigator.pop(
                                context,
                                const BlankPageChoice(),
                              ),
                              child: CustomPaint(
                                painter: PaperPainter(paper, scale: 0.18),
                                child: const SizedBox.expand(),
                              ),
                            ),
                            _Tile(
                              label: 'More papers',
                              onTap: () => Navigator.pop(
                                context,
                                const OtherPaperChoice(),
                              ),
                              child: _PaperSampler(paper: paper),
                            ),
                          ],
                        ),
                        _MyPagesRow(query: _filter.query),
                        if (_filter.isEmpty) ...[
                          _PicksRow(
                            title: 'Favorites',
                            picks: ref
                                .read(favoriteTemplatePagesProvider.notifier)
                                .picks,
                          ),
                          _PicksRow(
                            title: 'Recent',
                            picks: ref
                                .read(recentTemplatePagesProvider.notifier)
                                .picks,
                          ),
                        ],
                        if (templates.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 24),
                            child: Text(
                              'Templates appear here once they download. Check '
                              'your connection.',
                            ),
                          )
                        else if (shown.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 24),
                            child: Text('No templates match.'),
                          ),
                      ],
                    );
                  }
                  return switch (rows[i - 1]) {
                    _Heading(:final text) => Padding(
                      padding: const EdgeInsets.only(top: 28, bottom: 4),
                      child: Text(text, style: theme.textTheme.titleMedium),
                    ),
                    _Usable(:final item) => _TemplateRow(
                      item: item,
                      wholePlanner: !widget.changing,
                    ),
                    _Locked(:final item) => _LockedRow(item: item),
                  };
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A template the user has: its pages, or for a planner, one tile per
/// section that opens the section's pages.
class _TemplateRow extends ConsumerWidget {
  const _TemplateRow({required this.item, this.wholePlanner = true});

  final CatalogItem item;

  /// Offers to add every page of a planner.
  final bool wholePlanner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Row(
            children: [
              Flexible(
                child: Text(item.name, style: theme.textTheme.titleSmall),
              ),
              if (item.linked) ...[
                const SizedBox(width: 8),
                const LinkedPagesBadge(size: 12),
              ],
              if (wholePlanner &&
                  item.templateMode == TemplateMode.notebook) ...[
                const Spacer(),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.library_add_outlined, size: 18),
                  label: Text(
                    item.pageCount == null
                        ? 'Add whole planner'
                        : 'Add whole planner · ${item.pageCount} pages',
                  ),
                  onPressed: () =>
                      Navigator.pop(context, WholePlannerChoice(item)),
                ),
              ],
            ],
          ),
        ),
        switch (ref.watch(templateSpecProvider(item))) {
          AsyncData(value: final spec) when spec.mode == TemplateMode.pages =>
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final page in spec.pages)
                  _TemplatePageTile(item: item, page: page),
              ],
            ),
          AsyncData(value: final spec) => SizedBox(
            height: 190,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              scrollDirection: Axis.horizontal,
              children: [
                for (final section in spec.sections)
                  if (section.pages.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _TemplatePageTile(
                        item: item,
                        page: section.pages.first,
                        label: section.pages.length == 1
                            ? section.pages.first.title
                            : '${section.title} · ${section.pages.length} ›',
                        semantics: section.pages.length == 1
                            ? null
                            : '${section.title} pages of ${item.name}',
                        onTap: section.pages.length == 1
                            ? null
                            : () => _openSection(context, item, section),
                      ),
                    ),
              ],
            ),
          ),
          AsyncError() => const Text(
            'Could not download these templates. Check your connection.',
          ),
          _ => const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          ),
        },
      ],
    );
  }

  Future<void> _openSection(
    BuildContext context,
    CatalogItem item,
    ({String title, List<TemplatePage> pages}) section,
  ) async {
    final choice = await Navigator.of(context).push<TemplatePageChoice>(
      MaterialPageRoute(
        builder: (_) => _SectionPagesScreen(item: item, section: section),
      ),
    );
    if (choice != null && context.mounted) Navigator.pop(context, choice);
  }
}

/// Every page of one planner section, to pick one.
class _SectionPagesScreen extends StatelessWidget {
  const _SectionPagesScreen({required this.item, required this.section});

  final CatalogItem item;
  final ({String title, List<TemplatePage> pages}) section;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${item.name} · ${section.title}')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 130,
          mainAxisExtent: 190,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: section.pages.length,
        itemBuilder: (context, i) =>
            _TemplatePageTile(item: item, page: section.pages[i]),
      ),
    );
  }
}

/// A template the user doesn't have yet: opens its store page.
class _LockedRow extends ConsumerWidget {
  const _LockedRow({required this.item});

  final CatalogItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 44,
        height: 56,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: ItemPreview(item: item),
        ),
      ),
      title: Row(
        children: [
          Flexible(child: Text(item.name)),
          if (item.linked) ...[
            const SizedBox(width: 8),
            const LinkedPagesBadge(size: 12),
          ],
        ],
      ),
      subtitle: Text(kindLabel(item)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(ref.watch(itemBadgeProvider(item))),
          const SizedBox(width: 6),
          const Icon(Icons.lock_outline, size: 18),
        ],
      ),
      onTap: () {
        final router = GoRouter.of(context);
        Navigator.pop(context);
        router.push('$storePath/${item.id}');
      },
    );
  }
}

/// A template page's picture and title, with a star to keep it under
/// Favorites. Picks the page (and remembers it under Recent) unless
/// [onTap] says otherwise.
class _TemplatePageTile extends ConsumerWidget {
  const _TemplatePageTile({
    required this.item,
    required this.page,
    this.label,
    this.semantics,
    this.onTap,
  });

  final CatalogItem item;
  final TemplatePage page;
  final String? label;
  final String? semantics;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref
        .watch(
          templateImageProvider((
            template: templatePage(item, page.pdfPage),
            width: 240,
          )),
        )
        .value;
    final pick = TemplatePick(
      itemId: item.id,
      pdfPage: page.pdfPage,
      title: page.title,
    );
    ref.watch(favoriteTemplatePagesProvider);
    final favorites = ref.read(favoriteTemplatePagesProvider.notifier);
    final starred = favorites.isFavorite(pick);
    return Stack(
      children: [
        _Tile(
          label: label ?? page.title,
          semantics: semantics ?? '${page.title} template',
          onTap:
              onTap ??
              () {
                ref.read(recentTemplatePagesProvider.notifier).add(pick);
                Navigator.pop(
                  context,
                  TemplatePageChoice(templateNewPage(item, page)),
                );
              },
          child: image == null
              ? const Skeleton(radius: 2)
              : RawImage(image: image, fit: BoxFit.contain),
        ),
        // A section tile opens the section; its pages have stars.
        if (onTap == null)
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              tooltip: starred
                  ? 'Remove ${page.title} from Favorites'
                  : 'Add ${page.title} to Favorites',
              visualDensity: VisualDensity.compact,
              iconSize: 20,
              icon: Icon(
                starred ? Icons.star : Icons.star_outline,
                color: starred ? const Color(0xFFC79A2E) : Colors.black54,
              ),
              onPressed: () => favorites.toggle(pick),
            ),
          ),
      ],
    );
  }
}

/// Favorite or recent template pages in a row, leaving out any whose
/// template can't be used any more.
class _PicksRow extends ConsumerWidget {
  const _PicksRow({required this.title, required this.picks});

  final String title;
  final List<TemplatePick> picks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entitlements = ref.watch(entitlementsProvider);
    final tiles = [
      for (final pick in picks)
        if (ref.watch(catalogItemProvider(pick.itemId)) case final item?
            when item.files != null && entitlements.canUseCatalogItem(item))
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _TemplatePageTile(
              item: item,
              page: (
                pdfPage: pick.pdfPage,
                title: pick.title,
                period: null,
                group: null,
              ),
            ),
          ),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        SizedBox(
          height: 190,
          child: ListView(scrollDirection: Axis.horizontal, children: tiles),
        ),
      ],
    );
  }
}

/// The user's own page templates, matching [query]: each a small print of
/// the page.
class _MyPagesRow extends ConsumerWidget {
  const _MyPagesRow({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = query.toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    final pages = [
      for (final p in ref.watch(myPageTemplatesProvider).value ?? const [])
        if (words.every(p.displayTitle.toLowerCase().contains)) p,
    ];
    if (pages.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(
            'My pages',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        SizedBox(
          height: 190,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final page in pages)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _Tile(
                    label: page.displayTitle,
                    onTap: () => Navigator.pop(context, MyPageChoice(page)),
                    child: FittedBox(
                      child: PagePrint(pageId: page.id, templateWidth: 240),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// What [page] is drawn on: its template page, else its paper (or the
/// notebook's [paper]).
class _PagePicture extends ConsumerWidget {
  const _PagePicture({required this.page, required this.paper});

  final NewPage page;
  final PaperStyle paper;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (page.template case final template?) {
      final image = ref
          .watch(templateImageProvider((template: template, width: 240)))
          .value;
      return image == null
          ? const Skeleton(radius: 2)
          : RawImage(image: image, fit: BoxFit.contain);
    }
    return CustomPaint(
      painter: PaperPainter(page.paper ?? paper, scale: 0.18),
      child: const SizedBox.expand(),
    );
  }
}

/// A fan of papers in the notebook's colors (dots, grid, lined): a peek
/// at what More papers offers.
class _PaperSampler extends StatelessWidget {
  const _PaperSampler({required this.paper});

  final PaperStyle paper;

  @override
  Widget build(BuildContext context) {
    final edge = Theme.of(context).colorScheme.outline;
    Widget card(PaperPattern pattern, double turn, Offset shift) => Center(
      child: Transform.translate(
        offset: shift,
        child: Transform.rotate(
          angle: turn,
          child: Container(
            width: 64,
            height: 84,
            decoration: BoxDecoration(
              border: Border.all(color: edge, width: 0.8),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: CustomPaint(
              painter: PaperPainter(
                paper.copyWith(pattern: pattern, color: paper.color),
                scale: 0.3,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Stack(
        fit: StackFit.expand,
        children: [
          card(PaperPattern.dot, -0.16, const Offset(-14, -6)),
          card(PaperPattern.grid, 0.12, const Offset(14, -2)),
          card(PaperPattern.lined, 0, const Offset(0, 8)),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.onTap,
    required this.child,
    this.semantics,
  });

  final String label;
  final String? semantics;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: semantics ?? label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          width: 110,
          child: Column(
            children: [
              Container(
                height: 140,
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: theme.colorScheme.outline),
                ),
                child: child,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
