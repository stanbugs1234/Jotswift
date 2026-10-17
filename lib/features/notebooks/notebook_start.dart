import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/catalog_item.dart';
import '../../core/catalog/planner_series.dart';
import '../../core/paper/paper_style.dart';
import '../../core/skins/widgets/paper.dart';
import '../../shared/ui/empty_state.dart';
import '../../shared/ui/tokens.dart';
import '../shelf/cover_view.dart';
import '../store/store_item.dart' show itemBadgeProvider;
import 'domain/notebook_models.dart';
import 'template_filter.dart';
import 'template_gallery.dart';

/// The first step of New notebook: what it starts from. Blank pages, one
/// of the user's own templates, or a planner, in one grid with a search
/// and the category chips. Choosing one moves on to the details.
///
/// A planner shows once, however many editions (dates) it has; the
/// details step picks among them. Planners the user can't use yet come
/// last, locked, and [onLocked] shows them in the store.
class NotebookStartChooser extends ConsumerStatefulWidget {
  const NotebookStartChooser({
    required this.series,
    required this.usable,
    required this.myTemplates,
    required this.blankPaper,
    required this.onBlank,
    required this.onTemplate,
    required this.onLocked,
    required this.onMine,
    this.loading = false,
    super.key,
  });

  final List<PlannerSeries> series;

  /// Whether an edition can be used now.
  final bool Function(CatalogItem) usable;
  final List<Notebook> myTemplates;

  /// The paper a blank notebook gets, for its card.
  final PaperStyle blankPaper;

  /// Still waiting for the catalog: shows placeholders for its planners.
  final bool loading;

  final VoidCallback onBlank;
  final ValueChanged<PlannerSeries> onTemplate;
  final ValueChanged<PlannerSeries> onLocked;
  final ValueChanged<Notebook> onMine;

  @override
  ConsumerState<NotebookStartChooser> createState() =>
      _NotebookStartChooserState();
}

class _NotebookStartChooserState extends ConsumerState<NotebookStartChooser> {
  var _filter = const TemplateFilter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gutter = gutterOf(context);
    final now = DateTime.now();
    final shown = [
      for (final s in widget.series)
        if (s.editions.any(_filter.matches))
          (
            series: s,
            item: s.defaultEdition(now, usable: widget.usable),
            locked: !s.editions.any(widget.usable),
          ),
    ]..sort((a, b) => (a.locked ? 1 : 0) - (b.locked ? 1 : 0));
    // Blank and the user's own templates lead the grid until a search or a
    // category narrows it to planners.
    final mine = _filter.isEmpty ? widget.myTemplates : const <Notebook>[];
    final starters = _filter.isEmpty ? 1 + mine.length : 0;
    final placeholders = widget.loading ? 6 : 0;

    Widget card(BuildContext context, int i) {
      if (i == 0 && starters > 0) {
        return TemplateCard(
          title: 'Blank notebook',
          subtitle: 'Choose paper next',
          selected: false,
          onTap: widget.onBlank,
          preview: _PaperPreview(paper: widget.blankPaper),
        );
      }
      if (i < starters) {
        final t = mine[i - 1];
        return TemplateCard(
          title: t.title,
          subtitle: 'My template',
          selected: false,
          onTap: () => widget.onMine(t),
          preview: ColoredBox(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(Insets.lg),
              child: Center(child: CoverView(cover: t.cover)),
            ),
          ),
        );
      }
      if (i >= starters + shown.length) {
        return const TemplateCard.placeholder();
      }
      final (:series, :item, :locked) = shown[i - starters];
      final detail = [
        if (locked) ref.watch(itemBadgeProvider(item)),
        if (series.editions.length > 1)
          series.editions.any((e) => editionDates(e) == null)
              ? 'Dated or undated'
              : 'Pick your dates'
        else
          ?editionLabel(item),
        if (item.linked) 'linked',
      ];
      return TemplateCard(
        item: item,
        title: series.name,
        subtitle: detail.isEmpty ? templateSummary(item) : detail.join(' · '),
        selected: false,
        locked: locked,
        onTap: () =>
            locked ? widget.onLocked(series) : widget.onTemplate(series),
        onLookInside: () async {
          final chosen = await showTemplatePages(
            context,
            item,
            locked: locked,
            lockedAction: locked
                ? FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onLocked(series);
                    },
                    child: const Text('Get it'),
                  )
                : null,
          );
          if (chosen == true) widget.onTemplate(series);
        },
      );
    }

    final all = [for (final s in widget.series) ...s.editions];
    final count = starters + shown.length + placeholders;
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(gutter, Insets.sm, gutter, Insets.lg),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Start with blank pages, or a planner with its pages '
                  'ready and linked.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (widget.series.length >= 5) ...[
                  const SizedBox(height: Insets.lg),
                  TemplateFilterBar(
                    templates: all,
                    filter: _filter,
                    onChanged: (f) => setState(() => _filter = f),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (count == 0)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.search_off,
              title: 'No templates match.',
              message: 'Try another word or category.',
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(gutter, 0, gutter, Insets.xxl),
            sliver: TemplateCardGrid(itemCount: count, itemBuilder: card),
          ),
      ],
    );
  }
}

/// A sheet of [paper] on the card's surface, for "Blank notebook".
class _PaperPreview extends StatelessWidget {
  const _PaperPreview({required this.paper});

  final PaperStyle paper;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Padding(
      padding: const EdgeInsets.all(Insets.md),
      child: Center(
        child: AspectRatio(
          aspectRatio: 0.75,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: paper.color,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: CustomPaint(painter: PaperPainter(paper, scale: 0.5)),
          ),
        ),
      ),
    ),
  );
}
