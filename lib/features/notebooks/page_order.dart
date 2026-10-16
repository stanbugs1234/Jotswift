import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/notebook_models.dart';
import 'notes_providers.dart';

/// Every page in a notebook, in reading order: by section, then by the
/// page's place in its section.
final notebookPageOrderProvider = Provider.family<List<String>, String>((
  ref,
  notebookId,
) {
  return [for (final p in ref.watch(orderedPagesProvider(notebookId))) p.id];
});

/// Every page in a notebook, in reading order.
final orderedPagesProvider = Provider.family<List<NotePage>, String>((
  ref,
  notebookId,
) {
  final sections = ref.watch(sectionsProvider(notebookId)).value ?? const [];
  final pages =
      ref.watch(notebookPagesProvider(notebookId)).value ?? const <NotePage>[];
  return sortPages(sections, pages);
});

/// Every page in a notebook, in no particular order.
final notebookPagesProvider = StreamProvider.family<List<NotePage>, String>(
  (ref, notebookId) =>
      ref.watch(notebookRepositoryProvider).watchNotebookPages(notebookId),
);

/// Page ids by section order, then page order. Pages in sections that no
/// longer exist go last.
List<String> orderPages(List<Section> sections, List<NotePage> pages) => [
  for (final p in sortPages(sections, pages)) p.id,
];

/// [pages] by section order, then page order.
List<NotePage> sortPages(List<Section> sections, List<NotePage> pages) {
  final sectionRank = {for (final (i, s) in sections.indexed) s.id: i};
  final sorted = [...pages]
    ..sort((a, b) {
      final bySection = (sectionRank[a.sectionId] ?? sections.length).compareTo(
        sectionRank[b.sectionId] ?? sections.length,
      );
      if (bySection != 0) return bySection;
      final byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : a.createdAt.compareTo(b.createdAt);
    });
  return sorted;
}

/// The pages before and after [pageId] in its notebook (null at either end).
({String? previous, String? next}) adjacentPages(
  List<String> order,
  String pageId,
) {
  final i = order.indexOf(pageId);
  if (i < 0) return (previous: null, next: null);
  return (
    previous: i > 0 ? order[i - 1] : null,
    next: i + 1 < order.length ? order[i + 1] : null,
  );
}
