import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/features/notebooks/data/firestore_notes_backend.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/data/notes_repository.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';

/// Categories and groups behave the same in every backend.
void main() {
  final backends = <String, NotesBackend Function()>{
    'in memory': InMemoryNotesBackend.new,
    'Firestore': () => FirestoreNotesBackend(FakeFirebaseFirestore()),
  };

  for (final MapEntry(key: name, value: makeBackend) in backends.entries) {
    group(name, () {
      late NotebookRepository notebooks;
      late ShelfRepository shelf;

      setUp(() {
        final backend = makeBackend();
        notebooks = backend.notebooks('sam');
        shelf = backend.shelf('sam');
      });

      // Firestore writes are applied in the background.
      Future<Notebook> read(String id) async {
        await pumpEventQueue();
        return (await notebooks.watchNotebook(id).first)!;
      }

      Future<NotebookGroup> readGroup(String id) async {
        await pumpEventQueue();
        return (await shelf.watchGroups().first).firstWhere((g) => g.id == id);
      }

      Future<Notebook> create(String title, [ShelfPlace place = unfiled]) =>
          notebooks.createNotebook(
            NewNotebook(
              title: title,
              cover: const NotebookCover.color(1),
              place: place,
            ),
          );

      test('categories are listed in the order they were made', () async {
        await shelf.createCategory('School');
        await shelf.createCategory('Work');
        await pumpEventQueue();

        final categories = await shelf.watchCategories().first;
        expect(categories.map((c) => c.title), ['School', 'Work']);

        await shelf.renameCategory(categories.first.id, 'Uni');
        await pumpEventQueue();
        expect((await shelf.watchCategories().first).first.title, 'Uni');
      });

      test('a notebook made in a category or group is put there', () async {
        final school = await shelf.createCategory('School');
        final term = await shelf.createGroup('Term 1', (
          categoryId: school.id,
          groupId: null,
        ));

        final inCategory = await create('Biology', (
          categoryId: school.id,
          groupId: null,
        ));
        final inGroup = await create('Chemistry', (
          categoryId: school.id,
          groupId: term.id,
        ));

        expect((await read(inCategory.id)).categoryId, school.id);
        // Inside a group, the category comes from the group.
        final chem = await read(inGroup.id);
        expect(chem.groupId, term.id);
        expect(chem.categoryId, isNull);
        expect((await readGroup(term.id)).categoryId, school.id);
      });

      test('deleting a category keeps its notebooks and groups', () async {
        final school = await shelf.createCategory('School');
        final place = (categoryId: school.id, groupId: null);
        final nb = await create('Biology', place);
        final term = await shelf.createGroup('Term 1', place);
        await pumpEventQueue();

        await shelf.deleteCategory(school.id);

        expect(await read(nb.id), isNotNull);
        expect((await read(nb.id)).categoryId, isNull);
        expect((await readGroup(term.id)).categoryId, isNull);
        expect(await shelf.watchCategories().first, isEmpty);
      });

      test('deleting a group moves what was in it up a level', () async {
        final school = await shelf.createCategory('School');
        final outer = await shelf.createGroup('Year 1', (
          categoryId: school.id,
          groupId: null,
        ));
        final inner = await shelf.createGroup('Term 1', (
          categoryId: null,
          groupId: outer.id,
        ));
        final innerNotebook = await create('Chem', (
          categoryId: null,
          groupId: inner.id,
        ));
        final outerNotebook = await create('Bio', (
          categoryId: null,
          groupId: outer.id,
        ));
        await pumpEventQueue();

        await shelf.deleteGroup(inner.id);
        expect((await read(innerNotebook.id)).groupId, outer.id);

        await shelf.deleteGroup(outer.id);
        final bio = await read(outerNotebook.id);
        expect(bio.groupId, isNull);
        expect(bio.categoryId, school.id);
        expect((await read(innerNotebook.id)).categoryId, school.id);
      });

      test('moving a notebook into a group and back out', () async {
        final work = await shelf.createCategory('Work');
        final group = await shelf.createGroup('Meetings', unfiled);
        final nb = await create('Notes', (categoryId: work.id, groupId: null));
        await pumpEventQueue();

        await shelf.moveNotebook(nb.id, (categoryId: null, groupId: group.id));
        var moved = await read(nb.id);
        expect(moved.groupId, group.id);
        expect(moved.categoryId, isNull);

        await shelf.moveNotebook(nb.id, (categoryId: work.id, groupId: null));
        moved = await read(nb.id);
        expect(moved.groupId, isNull);
        expect(moved.categoryId, work.id);
      });

      test('moving a group into another group', () async {
        final a = await shelf.createGroup('A', unfiled);
        final b = await shelf.createGroup('B', unfiled);
        await pumpEventQueue();

        await shelf.moveGroup(b.id, (categoryId: null, groupId: a.id));

        expect((await readGroup(b.id)).parentGroupId, a.id);
      });

      test('custom order, opening and editing are recorded', () async {
        final nb = await create('Notes');
        await pumpEventQueue();
        final before = await read(nb.id);
        expect(before.lastOpenedAt, isNull);

        await shelf.setNotebookOrder(nb.id, 42.5);
        await notebooks.markNotebookOpened(nb.id);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await notebooks.touchNotebook(nb.id);

        final after = await read(nb.id);
        expect(after.order, 42.5);
        expect(after.lastOpenedAt, isNotNull);
        expect(after.updatedAt, greaterThan(before.updatedAt));
      });
    });
  }
}
