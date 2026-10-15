import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/paper/basic_papers.dart';
import 'package:notely/core/paper/paper_style.dart';
import 'package:notely/features/notebooks/data/firestore_notes_backend.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/data/notes_repository.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';

/// Covers and paper behave the same in every backend.
void main() {
  final backends = <String, NotesBackend Function()>{
    'in memory': InMemoryNotesBackend.new,
    'Firestore': () => FirestoreNotesBackend(FakeFirebaseFirestore()),
  };

  final cream = basicPaper(PaperPattern.dot, BasicPaperColor.cream);
  final grid = basicPaper(PaperPattern.grid, BasicPaperColor.white);

  for (final MapEntry(key: name, value: makeBackend) in backends.entries) {
    group(name, () {
      late NotebookRepository repo;

      setUp(() => repo = makeBackend().notebooks('sam'));

      // Firestore writes are applied in the background.
      Future<Notebook> notebook(String id) async {
        await pumpEventQueue();
        return (await repo.watchNotebook(id).first)!;
      }

      Future<NotePage> page(String id) async {
        await pumpEventQueue();
        return (await repo.watchPage(id).first)!;
      }

      test('a notebook keeps its cover, paper, size and orientation', () async {
        final created = await repo.createNotebook(
          NewNotebook(
            title: 'Journal',
            cover: const NotebookCover.art('botanical_leaf', color: 0xFF4F7B5A),
            paper: cream,
            paperSize: PaperSize.a5,
            orientation: PaperOrientation.landscape,
          ),
        );

        final saved = await notebook(created.id);
        expect(saved.cover.kind, CoverKind.art);
        expect(saved.cover.coverId, 'botanical_leaf');
        expect(saved.paper, cream);
        expect(saved.paperSize, PaperSize.a5);
        expect(saved.orientation, PaperOrientation.landscape);
      });

      test('a notebook made without paper uses the skin paper', () async {
        final created = await repo.createNotebook(
          const NewNotebook(title: 'Plain', cover: NotebookCover.color(1)),
        );

        expect((await notebook(created.id)).paper, isNull);
      });

      test('changing the cover and paper keeps the title', () async {
        final created = await repo.createNotebook(
          const NewNotebook(title: 'Work', cover: NotebookCover.color(1)),
        );

        await repo.updateNotebook(
          created.id,
          cover: const NotebookCover.color(2),
          paper: grid,
        );

        final saved = await notebook(created.id);
        expect(saved.title, 'Work');
        expect(saved.cover, const NotebookCover.color(2));
        expect(saved.paper, grid);
      });

      test('a page can be made with its own paper', () async {
        final nb = await repo.createNotebook(
          const NewNotebook(title: 'Work', cover: NotebookCover.color(1)),
        );
        await pumpEventQueue();
        final section = (await repo.watchSections(nb.id).first).single;

        final created = await repo.createPage(nb.id, section.id, paper: grid);

        expect((await page(created.id)).paper, grid);
      });

      test(
        'favorite papers are listed newest first and can be removed',
        () async {
          final favorites = makeBackend().favoritePapers('sam');
          await favorites.setFavoritePaper(cream, favorite: true);
          await Future<void>.delayed(const Duration(milliseconds: 2));
          await favorites.setFavoritePaper(grid, favorite: true);
          await pumpEventQueue();
          expect(await favorites.watchFavoritePapers().first, [grid, cream]);

          await favorites.setFavoritePaper(cream, favorite: false);
          await pumpEventQueue();
          expect(await favorites.watchFavoritePapers().first, [grid]);
        },
      );

      test('a page can have its own paper and go back to the notebook '
          'paper', () async {
        final nb = await repo.createNotebook(
          NewNotebook(
            title: 'Work',
            cover: const NotebookCover.color(1),
            paper: cream,
          ),
        );
        await pumpEventQueue();
        final section = (await repo.watchSections(nb.id).first).single;
        final created = await repo.createPage(nb.id, section.id);
        expect((await page(created.id)).paper, isNull);

        await repo.setPagePaper(created.id, grid);
        expect((await page(created.id)).paper, grid);

        await repo.setPagePaper(created.id, null);
        expect((await page(created.id)).paper, isNull);
      });
    });
  }
}
