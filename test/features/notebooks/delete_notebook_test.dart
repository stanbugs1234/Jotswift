import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/features/canvas/domain/stroke.dart';
import 'package:notely/features/notebooks/data/firestore_notes_backend.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/data/notes_repository.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';

/// Deleting a notebook (emptying the Trash) removes it and everything in
/// it, in every backend.
void main() {
  final backends = <String, NotesBackend Function()>{
    'in memory': InMemoryNotesBackend.new,
    'Firestore': () => FirestoreNotesBackend(FakeFirebaseFirestore()),
  };

  Stroke line(String id) => Stroke(
    id: id,
    tool: InkTool.pen,
    color: 0xFF000000,
    width: 3,
    points: const [InkPoint(0, 0), InkPoint(10, 10)],
    createdAt: 1,
  );

  for (final MapEntry(key: name, value: makeBackend) in backends.entries) {
    test('$name: a planner with many pages is deleted with its ink', () async {
      final backend = makeBackend();
      final repo = backend.notebooks('sam');
      final strokes = backend.strokes('sam');

      Future<Notebook> planner(String title) async {
        final nb = await repo.createNotebook(
          NewNotebook(title: title, cover: const NotebookCover.color(0)),
        );
        await pumpEventQueue(); // Firestore writes land in the background.
        final section = (await repo.watchSections(nb.id).first).single;
        await repo.createPages(nb.id, section.id, [
          for (var i = 0; i < 60; i++)
            (title: 'Week $i', paper: null, template: null),
        ]);
        await pumpEventQueue();
        return nb;
      }

      final gone = await planner('Old planner');
      final kept = await planner('Kept');
      final pages = await repo.watchNotebookPages(gone.id).first;
      expect(pages, hasLength(60));
      for (final p in pages.take(5)) {
        await strokes.addStroke(p.id, line('s-${p.id}'));
      }
      await pumpEventQueue();

      await repo.deleteNotebook(gone.id);
      await pumpEventQueue();

      expect((await repo.watchNotebooks().first).map((n) => n.title), ['Kept']);
      expect(await repo.watchNotebookPages(gone.id).first, isEmpty);
      expect(await repo.watchSections(gone.id).first, isEmpty);
      for (final p in pages.take(5)) {
        expect(await strokes.watchStrokes(p.id).first, isEmpty);
      }
      expect(await repo.watchNotebookPages(kept.id).first, hasLength(60));
    });
  }
}
