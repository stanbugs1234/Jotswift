import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../canvas/domain/page_element.dart';
import 'domain/notebook_models.dart';
import 'notes_providers.dart';

/// Makes [into] as a copy of notebook [sourceId]: its sections in order,
/// and every page with its paper, template, ink and items. Links between
/// pages that the user made point at the copied pages.
///
/// Saving a notebook as one of the user's own templates, and starting a
/// notebook from one, both copy this way, so changing either afterwards
/// leaves the other alone.
Future<Notebook> copyNotebookInto(
  Ref ref,
  String sourceId,
  NewNotebook into,
) async {
  final repo = ref.read(notebookRepositoryProvider);
  final elements = ref.read(elementRepositoryProvider);
  final created = await repo.createNotebook(into);
  final first = (await repo.watchSections(created.id).first).first;
  final sections = await repo.watchSections(sourceId).first;

  final copies = <String, String>{}; // source page id to its copy
  for (final (i, section) in sections.indexed) {
    final String sectionId;
    if (i == 0) {
      sectionId = first.id;
      await repo.renameSection(created.id, sectionId, section.title);
    } else {
      sectionId = (await repo.createSection(created.id, section.title)).id;
    }
    final pages = await repo.watchPages(sourceId, section.id).first;
    for (final page in pages) {
      copies[page.id] = await repo.copyPage(
        page.id,
        notebookId: created.id,
        sectionId: sectionId,
        order: page.order,
      );
    }
  }

  for (final copy in copies.values) {
    for (final e in await elements.watchElements(copy).first) {
      if (e.content case LinkContent(:final pageId) when !e.deleted) {
        final target = copies[pageId];
        if (target == null) continue;
        await elements.setElementContent(
          copy,
          e.id,
          LinkContent(target),
          e.frame,
        );
      }
    }
  }
  return created;
}
