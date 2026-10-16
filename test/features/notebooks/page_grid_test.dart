import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/app/router.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/canvas/domain/stroke.dart';
import 'package:notely/features/notebooks/data/firestore_notes_backend.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/data/notes_repository.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';
import 'package:notely/features/notebooks/notes_providers.dart';
import 'package:notely/features/notebooks/page_grid.dart';

import '../../helpers.dart';

NotePage page(String id, double order) => NotePage(
  id: id,
  notebookId: 'n',
  sectionId: 's',
  title: id,
  order: order,
  createdAt: 0,
  updatedAt: 0,
);

void main() {
  group('ordering', () {
    test('between two pages, or past either end', () {
      expect(orderBetween(null, null), 1);
      expect(orderBetween(null, 4), 3);
      expect(orderBetween(4, null), 5);
      expect(orderBetween(2, 3), 2.5);
    });

    final pages = [page('a', 1), page('b', 2), page('c', 3), page('d', 4)];

    test('dropping on a page earlier puts it just before', () {
      expect(orderForDrop(pages, pages[3], pages[1]), 1.5);
      expect(orderForDrop(pages, pages[2], pages[0]), 0);
    });

    test('dropping on a page later puts it just after', () {
      expect(orderForDrop(pages, pages[0], pages[2]), 3.5);
      expect(orderForDrop(pages, pages[1], pages[3]), 5);
    });

    test('a neighbour dropped on the next page swaps with it', () {
      expect(orderForDrop(pages, pages[1], pages[2]), 3.5);
      expect(orderForDrop(pages, pages[2], pages[1]), 1.5);
    });
  });

  final backends = <String, NotesBackend Function()>{
    'in memory': InMemoryNotesBackend.new,
    'Firestore': () => FirestoreNotesBackend(FakeFirebaseFirestore()),
  };
  for (final MapEntry(key: name, value: make) in backends.entries) {
    test(
      'pages move and copy with their ink, period and bookmark ($name)',
      () async {
        final backend = make();
        final repo = backend.notebooks('sam');
        final strokes = backend.strokes('sam');
        final a = await repo.createNotebook(
          const NewNotebook(title: 'A', cover: NotebookCover.color(1)),
        );
        final b = await repo.createNotebook(
          const NewNotebook(title: 'B', cover: NotebookCover.color(1)),
        );
        await pumpEventQueue();
        final sa = (await repo.watchSections(a.id).first).single;
        final sb = (await repo.watchSections(b.id).first).single;
        final p = await repo.createPage(a.id, sa.id, title: 'Cells');
        await pumpEventQueue();
        await repo.setPageBookmarked(p.id, true);
        Stroke line(String id, {bool deleted = false}) => Stroke(
          id: id,
          tool: InkTool.pen,
          color: 0xFF000000,
          width: 3,
          points: const [InkPoint(0, 0), InkPoint(10, 10)],
          createdAt: 1,
          deleted: deleted,
        );
        await strokes.addStroke(p.id, line('kept'));
        await strokes.addStroke(p.id, line('erased', deleted: true));
        await pumpEventQueue();

        final copyId = await repo.copyPage(
          p.id,
          notebookId: b.id,
          sectionId: sb.id,
          order: 7,
        );
        await pumpEventQueue();
        final copy = (await repo.watchPage(copyId).first)!;
        expect(copy.notebookId, b.id);
        expect(copy.title, 'Cells');
        expect(copy.order, 7);
        expect(copy.bookmarked, isTrue);
        expect((await strokes.watchStrokes(copyId).first).map((s) => s.id), [
          'kept',
        ]);
        // The original is untouched.
        expect((await repo.watchPage(p.id).first)!.notebookId, a.id);

        await repo.movePage(p.id, notebookId: b.id, sectionId: sb.id, order: 2);
        await pumpEventQueue();
        expect((await repo.watchPages(b.id, sb.id).first).map((p) => p.id), [
          p.id,
          copyId,
        ]);
        expect(await repo.watchPages(a.id, sa.id).first, isEmpty);
        expect(await strokes.watchStrokes(p.id).first, hasLength(2));
      },
    );
  }

  group('the page grid', () {
    late List<SkinManifest> skins;
    late InMemoryNotesBackend backend;
    late NotebookRepository repo;
    late String notebookId, sectionId;

    setUpAll(() async {
      skins = await loadTestSkins();
    });

    Future<void> pumpGrid(WidgetTester tester) async {
      final auth = await pumpApp(
        tester,
        skins,
        size: const Size(900, 1200),
        overrides: [notesBackendProvider.overrideWithValue(backend)],
      );
      repo = backend.notebooks(auth.currentUser!.uid);
      final nb = await repo.createNotebook(
        const NewNotebook(title: 'Bio', cover: NotebookCover.color(1)),
      );
      notebookId = nb.id;
      sectionId = (await repo.watchSections(nb.id).first).single.id;
      for (final t in ['One', 'Two', 'Three']) {
        await repo.createPage(nb.id, sectionId, title: t);
      }
      await repo.createNotebook(
        const NewNotebook(title: 'Chemistry', cover: NotebookCover.color(2)),
      );
      ProviderScope.containerOf(tester.element(find.byType(Navigator).first))
          .read(routerProvider)
          .go('/notebooks/$notebookId');
      await tester.pumpAndSettle();
    }

    Future<List<String>> titles() async => [
      for (final p in await repo.watchPages(notebookId, sectionId).first)
        p.title,
    ];

    Future<void> menu(WidgetTester tester, int tile, String item) async {
      await tester.tap(find.byTooltip('Page options').at(tile));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    setUp(() => backend = InMemoryNotesBackend());

    testWidgets('shows each page as a thumbnail', (tester) async {
      await pumpGrid(tester);

      expect(find.text('One'), findsOneWidget);
      expect(find.text('Three'), findsOneWidget);
      expect(find.byTooltip('Page options'), findsNWidgets(3));
    });

    testWidgets('dragging a page onto another reorders them', (tester) async {
      await pumpGrid(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Three')) - const Offset(0, 60),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(
        tester.getCenter(find.text('One')) - const Offset(0, 60),
      );
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(await titles(), ['Three', 'One', 'Two']);
    });

    testWidgets('duplicate puts a copy right after the page', (tester) async {
      await pumpGrid(tester);

      await menu(tester, 0, 'Duplicate');

      expect(await titles(), ['One', 'One', 'Two', 'Three']);
    });

    testWidgets('a page can be moved to another notebook', (tester) async {
      await pumpGrid(tester);

      await menu(tester, 1, 'Move to…');
      await tester.tap(find.text('Chemistry'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Notes'));
      await tester.pumpAndSettle();

      expect(await titles(), ['One', 'Three']);
      expect(find.text('Moved to Chemistry · Notes'), findsOneWidget);
      final chemistry = (await repo.watchNotebooks().first).firstWhere(
        (n) => n.title == 'Chemistry',
      );
      final there = (await repo.watchSections(chemistry.id).first).single;
      expect(
        (await repo.watchPages(chemistry.id, there.id).first).map(
          (p) => p.title,
        ),
        ['Two'],
      );
    });

    testWidgets('a page can be copied to another notebook', (tester) async {
      await pumpGrid(tester);

      await menu(tester, 0, 'Copy to…');
      await tester.tap(find.text('Chemistry'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Notes'));
      await tester.pumpAndSettle();

      expect(await titles(), ['One', 'Two', 'Three']);
      expect(find.text('Copied to Chemistry · Notes'), findsOneWidget);
    });
  });
}
