import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/catalog_item.dart';
import '../../core/paper/paper_style.dart';
import '../canvas/templates.dart';
import 'data/notes_repository.dart';
import 'domain/notebook_models.dart';
import 'new_page_sheet.dart';
import 'notes_providers.dart';
import 'page_templates.dart';
import 'paper_picker.dart';
import 'planner_builder.dart';

/// What a page is drawn on.
typedef PageBackground = ({PageTemplate? template, PaperStyle? paper});

/// Which pages a change of template goes on.
enum PageScope { page, section, notebook }

/// Asks for a new template or paper for [page], and which pages to put it
/// on (this page, its section or the whole notebook), then changes them.
/// Writing and items stay. Says how many changed, with Undo.
Future<void> changePageTemplate(
  BuildContext context,
  WidgetRef ref,
  NotePage page,
) async {
  final paper = notebookPaper(ref, page.notebookId);
  final choice = await showNewPageSheet(context, paper: paper, changing: true);
  if (choice == null || !context.mounted) return;
  final PageBackground background;
  switch (choice) {
    case BlankPageChoice():
      background = (template: null, paper: null);
    case OtherPaperChoice():
      final picked = await showPagePaperSheet(
        context,
        current: page.paper ?? paper,
        title: 'Change paper',
        confirmLabel: 'Use this paper',
      );
      if (picked == null) return;
      background = (template: null, paper: picked.paper);
    case TemplatePageChoice(page: final p):
      background = (template: p.template, paper: p.paper);
    // Just its background: the page's own writing stays.
    case MyPageChoice(page: final p):
      background = (template: p.template, paper: p.paper);
    case WholePlannerChoice():
      return;
  }
  if (!context.mounted) return;

  final repo = ref.read(notebookRepositoryProvider);
  final (inSection, inNotebook) = await (
    repo.watchPages(page.notebookId, page.sectionId).first,
    repo.watchNotebookPages(page.notebookId).first,
  ).wait;
  if (!context.mounted) return;
  final scope = inNotebook.length <= 1
      ? PageScope.page
      : await _askScope(
          context,
          sectionPages: inSection.length,
          notebookPages: inNotebook.length,
        );
  if (scope == null || !context.mounted) return;
  final pages = switch (scope) {
    PageScope.page => [page],
    PageScope.section => inSection,
    PageScope.notebook => inNotebook,
  };

  final before = {
    for (final p in pages) p.id: (template: p.template, paper: p.paper),
  };
  await _setAll(repo, {for (final p in pages) p.id: background});
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          pages.length == 1 ? 'Page changed' : 'Changed ${pages.length} pages',
        ),
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _setAll(repo, before),
        ),
      ),
    );
}

Future<void> _setAll(
  NotebookRepository repo,
  Map<String, PageBackground> backgrounds,
) => Future.wait([
  for (final MapEntry(key: id, value: b) in backgrounds.entries)
    repo.setPageBackground(id, template: b.template, paper: b.paper),
]);

Future<PageScope?> _askScope(
  BuildContext context, {
  required int sectionPages,
  required int notebookPages,
}) => showDialog<PageScope>(
  context: context,
  builder: (context) => SimpleDialog(
    title: const Text('Change which pages?'),
    children: [
      _ScopeOption(
        scope: PageScope.page,
        icon: Icons.description_outlined,
        label: 'This page',
      ),
      if (sectionPages > 1 && sectionPages < notebookPages)
        _ScopeOption(
          scope: PageScope.section,
          icon: Icons.folder_outlined,
          label: 'Every page in this section ($sectionPages)',
        ),
      _ScopeOption(
        scope: PageScope.notebook,
        icon: Icons.menu_book_outlined,
        label: 'Every page in the notebook ($notebookPages)',
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
        child: Text('Your writing stays where it is.'),
      ),
    ],
  ),
);

class _ScopeOption extends StatelessWidget {
  const _ScopeOption({
    required this.scope,
    required this.icon,
    required this.label,
  });

  final PageScope scope;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => SimpleDialogOption(
    onPressed: () => Navigator.pop(context, scope),
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 16),
        Expanded(child: Text(label)),
      ],
    ),
  );
}

/// Asks what page to add after [page] (one like it is offered first), adds
/// it right after, and returns its id; null if cancelled. A whole planner
/// is added as new sections, returning its first page.
Future<String?> addPageAfter(
  BuildContext context,
  WidgetRef ref,
  NotePage page,
) async {
  final paper = notebookPaper(ref, page.notebookId);
  final choice = await showNewPageSheet(
    context,
    paper: paper,
    same: (title: '', paper: page.paper, template: page.template),
  );
  if (choice == null || !context.mounted) return null;
  final NewPage add;
  switch (choice) {
    case BlankPageChoice():
      add = (title: '', paper: null, template: null);
    case OtherPaperChoice():
      final picked = await showPagePaperSheet(
        context,
        current: paper,
        title: 'New page',
        confirmLabel: 'Add page',
      );
      if (picked == null) return null;
      add = (title: '', paper: picked.paper, template: null);
    case TemplatePageChoice(page: final p):
      add = p;
    case MyPageChoice(page: final p):
      return addPageTemplate(
        ref,
        p,
        notebookId: page.notebookId,
        sectionId: page.sectionId,
        order: await _orderAfter(ref, page),
      );
    case WholePlannerChoice(:final item):
      return addWholePlanner(context, ref, page.notebookId, item);
  }

  final repo = ref.read(notebookRepositoryProvider);
  final created = await repo.createPage(
    page.notebookId,
    page.sectionId,
    paper: add.paper,
    template: add.template,
    title: add.title,
  );
  final order = await _orderAfter(ref, page, except: created.id);
  if (order != null) {
    await repo.movePage(
      created.id,
      notebookId: page.notebookId,
      sectionId: page.sectionId,
      order: order,
    );
  }
  return created.id;
}

/// The order right after [page] in its section (halfway to the next page,
/// leaving out [except]), or null if it's the last.
Future<double?> _orderAfter(
  WidgetRef ref,
  NotePage page, {
  String? except,
}) async {
  final pages = await ref
      .read(notebookRepositoryProvider)
      .watchPages(page.notebookId, page.sectionId)
      .first;
  final after = pages
      .where((p) => p.id != except && p.order > page.order)
      .map((p) => p.order)
      .fold<double?>(null, (a, b) => a == null || b < a ? b : a);
  return after == null ? null : (page.order + after) / 2;
}

/// Adds every page of the planner [item] to [notebookId], as new sections,
/// after asking its layout and which pages. Returns its first page's id.
Future<String?> addWholePlanner(
  BuildContext context,
  WidgetRef ref,
  String notebookId,
  CatalogItem item,
) async {
  final choice = await showAddPlannerSheet(context, item);
  if (choice == null || !context.mounted) return null;
  final add = ref.read(addPlannerPagesProvider);
  return withPlannerProgress<String?>(
    context,
    (onProgress) => add(
      notebookId,
      item,
      file: choice.file,
      skip: choice.skip,
      from: choice.from,
      onProgress: onProgress,
    ),
  );
}
