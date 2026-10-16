import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/paper/paper_style.dart';
import '../auth/auth_repository.dart';
import '../canvas/domain/page_element.dart';
import '../canvas/domain/stroke.dart';
import 'data/in_memory_notes_backend.dart';
import 'data/notes_repository.dart';
import 'domain/notebook_models.dart';

/// Overridden in `main()` with the Firestore backend when Firebase is set up.
final notesBackendProvider = Provider<NotesBackend>(
  (ref) => InMemoryNotesBackend(),
);

/// The signed-in user's id. Notes screens are only reachable when signed in.
final currentUidProvider = Provider<String>((ref) {
  ref.watch(authStateProvider);
  final uid = ref.read(authRepositoryProvider).currentUser?.uid;
  if (uid == null) throw StateError('Notes need a signed-in user');
  return uid;
});

final notebookRepositoryProvider = Provider<NotebookRepository>(
  (ref) =>
      ref.watch(notesBackendProvider).notebooks(ref.watch(currentUidProvider)),
);

final shelfRepositoryProvider = Provider<ShelfRepository>(
  (ref) => ref.watch(notesBackendProvider).shelf(ref.watch(currentUidProvider)),
);

final favoritePapersRepositoryProvider = Provider<FavoritePapersRepository>(
  (ref) => ref
      .watch(notesBackendProvider)
      .favoritePapers(ref.watch(currentUidProvider)),
);

final favoritePapersProvider = StreamProvider<List<PaperStyle>>(
  (ref) => ref.watch(favoritePapersRepositoryProvider).watchFavoritePapers(),
);

final categoriesProvider = StreamProvider<List<Category>>(
  (ref) => ref.watch(shelfRepositoryProvider).watchCategories(),
);

final groupsProvider = StreamProvider<List<NotebookGroup>>(
  (ref) => ref.watch(shelfRepositoryProvider).watchGroups(),
);

final strokeRepositoryProvider = Provider<StrokeRepository>(
  (ref) =>
      ref.watch(notesBackendProvider).strokes(ref.watch(currentUidProvider)),
);

/// The notebooks on the shelf (not the user's own templates).
final notebooksProvider = StreamProvider<List<Notebook>>(
  (ref) => ref
      .watch(notebookRepositoryProvider)
      .watchNotebooks()
      .map(
        (all) => [
          for (final n in all)
            if (!n.isTemplate) n,
        ],
      ),
);

/// The user's own templates ("Save as template"), by name.
final myTemplatesProvider = StreamProvider<List<Notebook>>(
  (ref) => ref
      .watch(notebookRepositoryProvider)
      .watchNotebooks()
      .map(
        (all) =>
            [
              for (final n in all)
                if (n.isTemplate && !n.inTrash) n,
            ]..sort(
              (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
            ),
      ),
);

final notebookProvider = StreamProvider.family<Notebook?, String>(
  (ref, id) => ref.watch(notebookRepositoryProvider).watchNotebook(id),
);

final sectionsProvider = StreamProvider.family<List<Section>, String>(
  (ref, notebookId) =>
      ref.watch(notebookRepositoryProvider).watchSections(notebookId),
);

/// Pages in a (notebookId, sectionId).
final pagesProvider =
    StreamProvider.family<
      List<NotePage>,
      ({String notebookId, String sectionId})
    >(
      (ref, key) => ref
          .watch(notebookRepositoryProvider)
          .watchPages(key.notebookId, key.sectionId),
    );

final pageProvider = StreamProvider.family<NotePage?, String>(
  (ref, pageId) => ref.watch(notebookRepositoryProvider).watchPage(pageId),
);

final elementRepositoryProvider = Provider<ElementRepository>(
  (ref) =>
      ref.watch(notesBackendProvider).elements(ref.watch(currentUidProvider)),
);

/// Every element on a page (stickers), including removed ones, bottom first.
final elementsProvider = StreamProvider.autoDispose
    .family<List<PageElement>, String>(
      (ref, pageId) =>
          ref.watch(elementRepositoryProvider).watchElements(pageId),
    );

/// Every stroke on a page, including erased ones.
final strokesProvider = StreamProvider.autoDispose.family<List<Stroke>, String>(
  (ref, pageId) => ref.watch(strokeRepositoryProvider).watchStrokes(pageId),
);

/// The paper a page is drawn on: its own, else its notebook's. Null means
/// neither chose one, so the active skin's paper is used.
final pagePaperProvider = Provider.family<PaperStyle?, String>((ref, pageId) {
  final page = ref.watch(pageProvider(pageId)).value;
  if (page == null) return null;
  return page.paper ??
      ref.watch(notebookProvider(page.notebookId)).value?.paper;
});

/// The size of a page, from its notebook (Letter portrait while loading).
final pageDimensionsProvider = Provider.family<Size, String>((ref, pageId) {
  final page = ref.watch(pageProvider(pageId)).value;
  final notebook = page == null
      ? null
      : ref.watch(notebookProvider(page.notebookId)).value;
  return (notebook?.paperSize ?? PaperSize.letter).dimensions(
    notebook?.orientation ?? PaperOrientation.portrait,
  );
});
