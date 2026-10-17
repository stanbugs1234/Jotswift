import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/paper/paper_style.dart';
import '../../shared/dialogs.dart';
import 'domain/notebook_models.dart';
import 'notes_providers.dart';
import 'page_grid.dart' show orderBetween;
import 'paper_picker.dart' show notebookPaper;

/// Saves a copy of [page] (its paper or template, writing and items) as one
/// of the user's page templates, under a name they choose. New page then
/// offers it under My pages, in any notebook.
Future<void> savePageAsTemplate(
  BuildContext context,
  WidgetRef ref,
  NotePage page,
) async {
  final name = await askForText(
    context,
    title: 'Save page as template',
    confirmLabel: 'Save',
    initialValue: page.title,
    hint: 'Template name',
  );
  if (name == null || name.trim().isEmpty || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final repo = ref.read(notebookRepositoryProvider);
  var holder = (await repo.watchNotebooks().first)
      .where((n) => n.pageTemplates && !n.inTrash)
      .firstOrNull;
  if (holder == null) {
    final from = ref.read(notebookProvider(page.notebookId)).value;
    holder = await repo.createNotebook(
      NewNotebook(
        title: 'My pages',
        cover: from?.cover ?? const NotebookCover.color(0xFF5B6B7F),
        paperSize: from?.paperSize ?? PaperSize.letter,
        orientation: from?.orientation ?? PaperOrientation.portrait,
        isTemplate: true,
        pageTemplates: true,
      ),
    );
  }
  final section = (await repo.watchSections(holder.id).first).first;
  final saved = await repo.watchPages(holder.id, section.id).first;
  final copy = await repo.copyPage(
    page.id,
    notebookId: holder.id,
    sectionId: section.id,
    order: orderBetween(
      saved.map((p) => p.order).fold<double?>(null, (a, b) {
        return a == null || b > a ? b : a;
      }),
      null,
    ),
  );
  await repo.renamePage(copy, name.trim());
  // Plain pages take their notebook's paper: keep the one it had here.
  if (page.template == null && page.paper == null) {
    await repo.setPageBackground(
      copy,
      template: null,
      paper: notebookPaper(ref, page.notebookId),
    );
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          'Saved "${name.trim()}". Find it under My pages when you add a '
          'page.',
        ),
      ),
    );
}

/// Adds a copy of the page template [template] to [sectionId] of
/// [notebookId] at [order] (the end of the section if null). Returns the
/// new page's id.
Future<String> addPageTemplate(
  WidgetRef ref,
  NotePage template, {
  required String notebookId,
  required String sectionId,
  double? order,
}) async {
  final repo = ref.read(notebookRepositoryProvider);
  final at =
      order ??
      orderBetween(
        (await repo.watchPages(notebookId, sectionId).first)
            .map((p) => p.order)
            .fold<double?>(null, (a, b) => a == null || b > a ? b : a),
        null,
      );
  return repo.copyPage(
    template.id,
    notebookId: notebookId,
    sectionId: sectionId,
    order: at,
  );
}
