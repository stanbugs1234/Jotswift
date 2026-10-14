import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_repository.dart';
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

final strokeRepositoryProvider = Provider<StrokeRepository>(
  (ref) =>
      ref.watch(notesBackendProvider).strokes(ref.watch(currentUidProvider)),
);

final notebooksProvider = StreamProvider<List<Notebook>>(
  (ref) => ref.watch(notebookRepositoryProvider).watchNotebooks(),
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

/// Every stroke on a page, including erased ones.
final strokesProvider = StreamProvider.autoDispose.family<List<Stroke>, String>(
  (ref, pageId) => ref.watch(strokeRepositoryProvider).watchStrokes(pageId),
);
