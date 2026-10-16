import 'package:flutter/material.dart';

import '../../core/catalog/catalog_item.dart';
import '../../core/paper/paper_style.dart';
import '../../core/skins/widgets/paper.dart';
import '../../shared/ui/empty_state.dart';
import '../../shared/ui/tokens.dart';
import '../shelf/cover_view.dart';
import 'domain/notebook_models.dart';
import 'template_filter.dart';
import 'template_gallery.dart';

/// The first step of New notebook: what it starts from. Blank pages, one
/// of the user's own templates, or a planner, in one grid with a search
/// and the category chips. Choosing one moves on to the details.
class NotebookStartChooser extends StatefulWidget {
  const NotebookStartChooser({
    required this.templates,
    required this.myTemplates,
    required this.blankPaper,
    required this.onBlank,
    required this.onTemplate,
    required this.onMine,
    super.key,
  });

  final List<CatalogItem> templates;
  final List<Notebook> myTemplates;

  /// The paper a blank notebook gets, for its card.
  final PaperStyle blankPaper;

  final VoidCallback onBlank;
  final ValueChanged<CatalogItem> onTemplate;
  final ValueChanged<Notebook> onMine;

  @override
  State<NotebookStartChooser> createState() => _NotebookStartChooserState();
}

class _NotebookStartChooserState extends State<NotebookStartChooser> {
  var _filter = const TemplateFilter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gutter = gutterOf(context);
    final templates = widget.templates.where(_filter.matches).toList();
    // Blank and the user's own templates lead the grid until a search or a
    // category narrows it to planners.
    final mine = _filter.isEmpty ? widget.myTemplates : const <Notebook>[];
    final starters = _filter.isEmpty ? 1 + mine.length : 0;

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
      final t = templates[i - starters];
      return TemplateCard(
        item: t,
        title: t.name,
        subtitle: templateSummary(t),
        selected: false,
        onTap: () => widget.onTemplate(t),
        onLookInside: () async {
          if (await showTemplatePages(context, t) == true) {
            widget.onTemplate(t);
          }
        },
      );
    }

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
                if (widget.templates.length >= 5) ...[
                  const SizedBox(height: Insets.lg),
                  TemplateFilterBar(
                    templates: widget.templates,
                    filter: _filter,
                    onChanged: (f) => setState(() => _filter = f),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (starters + templates.length == 0)
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
            sliver: TemplateCardGrid(
              itemCount: starters + templates.length,
              itemBuilder: card,
            ),
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
