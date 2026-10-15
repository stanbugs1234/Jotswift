import 'package:flutter_test/flutter_test.dart';
import 'package:notely/features/canvas/domain/stroke.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';

Stroke dot(String id) => Stroke(
  id: id,
  tool: InkTool.pen,
  color: 0xFF000000,
  width: 4,
  points: const [InkPoint(1, 1)],
  createdAt: 0,
);

void main() {
  late InMemoryNotesBackend backend;

  setUp(() => backend = InMemoryNotesBackend());

  test('a new notebook starts with one "Notes" section', () async {
    final repo = backend.notebooks('sam');
    final nb = await repo.createNotebook(
      NewNotebook(title: 'School', cover: NotebookCover.color(0xFF2C4A7C)),
    );

    expect((await repo.watchNotebooks().first).single.title, 'School');
    expect((await repo.watchSections(nb.id).first).single.title, 'Notes');
  });

  test('pages are listed per section in creation order', () async {
    final repo = backend.notebooks('sam');
    final nb = await repo.createNotebook(
      NewNotebook(title: 'School', cover: NotebookCover.color(0)),
    );
    final notes = (await repo.watchSections(nb.id).first).single;
    final other = await repo.createSection(nb.id, 'Labs');

    final p1 = await repo.createPage(nb.id, notes.id);
    final p2 = await repo.createPage(nb.id, notes.id);
    await repo.createPage(nb.id, other.id);

    final pages = await repo.watchPages(nb.id, notes.id).first;
    expect(pages.map((p) => p.id), [p1.id, p2.id]);
  });

  test('renaming a page updates it', () async {
    final repo = backend.notebooks('sam');
    final nb = await repo.createNotebook(
      NewNotebook(title: 'School', cover: NotebookCover.color(0)),
    );
    final section = (await repo.watchSections(nb.id).first).single;
    final page = await repo.createPage(nb.id, section.id);

    await repo.renamePage(page.id, 'Lecture 1');

    expect((await repo.watchPage(page.id).first)!.title, 'Lecture 1');
  });

  test('deleting a notebook deletes its sections, pages and ink', () async {
    final repo = backend.notebooks('sam');
    final strokes = backend.strokes('sam');
    final nb = await repo.createNotebook(
      NewNotebook(title: 'School', cover: NotebookCover.color(0)),
    );
    final section = (await repo.watchSections(nb.id).first).single;
    final page = await repo.createPage(nb.id, section.id);
    await strokes.addStroke(page.id, dot('a'));

    await repo.deleteNotebook(nb.id);

    expect(await repo.watchNotebooks().first, isEmpty);
    expect(await repo.watchSections(nb.id).first, isEmpty);
    expect(await repo.watchPage(page.id).first, isNull);
    expect(await strokes.watchStrokes(page.id).first, isEmpty);
  });

  test('erasing marks strokes deleted instead of removing them', () async {
    final strokes = backend.strokes('sam');
    await strokes.addStroke('p', dot('a'));
    await strokes.addStroke('p', dot('b'));

    await strokes.setDeleted('p', ['a'], true);
    var all = await strokes.watchStrokes('p').first;
    expect({for (final s in all) s.id: s.deleted}, {'a': true, 'b': false});

    await strokes.setDeleted('p', ['a'], false);
    all = await strokes.watchStrokes('p').first;
    expect(all.every((s) => !s.deleted), isTrue);
  });

  test("users can't see each other's notebooks", () async {
    await backend
        .notebooks('sam')
        .createNotebook(
          NewNotebook(title: 'Sam', cover: NotebookCover.color(0)),
        );

    expect(await backend.notebooks('alex').watchNotebooks().first, isEmpty);
  });
}
