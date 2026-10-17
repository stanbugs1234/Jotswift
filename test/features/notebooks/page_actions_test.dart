import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/app/router.dart';
import 'package:notely/core/paper/paper_style.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';
import 'package:notely/features/notebooks/notes_providers.dart';

import '../../helpers.dart';

void main() {
  late List<SkinManifest> skins;
  late InMemoryNotesBackend backend;
  late String uid;
  late String notebookId;
  late List<String> pageIds;

  setUpAll(() async => skins = await loadTestSkins());
  setUp(() => backend = InMemoryNotesBackend());

  const grid = PaperStyle(
    color: Color(0xFFFFFFFF),
    lineColor: Color(0xFFB0C4DE),
    pattern: PaperPattern.grid,
    spacing: 24,
  );

  /// A notebook with pages One, Two and Three on grid paper, open on One.
  Future<void> pumpNotebook(WidgetTester tester) async {
    final auth = await pumpApp(
      tester,
      skins,
      size: const Size(1000, 1000),
      overrides: [notesBackendProvider.overrideWithValue(backend)],
    );
    uid = auth.currentUser!.uid;
    final repo = backend.notebooks(uid);
    final nb = await repo.createNotebook(
      const NewNotebook(title: 'Bio', cover: NotebookCover.color(1)),
    );
    notebookId = nb.id;
    final section = (await repo.watchSections(nb.id).first).single;
    pageIds = [
      for (final t in ['One', 'Two', 'Three'])
        (await repo.createPage(nb.id, section.id, title: t, paper: grid)).id,
    ];
    ProviderScope.containerOf(tester.element(find.byType(Navigator).first))
        .read(routerProvider)
        .go('/notebooks/${nb.id}/pages/${pageIds[0]}');
    await tester.pumpAndSettle();
  }

  Future<List<NotePage>> pages() =>
      backend.notebooks(uid).watchNotebookPages(notebookId).first;

  testWidgets('a template change can go on every page, and be undone', (
    tester,
  ) async {
    await pumpNotebook(tester);
    await tester.tap(find.byTooltip('Page options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change template…'));
    await tester.pumpAndSettle();
    expect(find.text('Change template'), findsOneWidget);
    await tester.tap(find.text('Plain paper'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Every page in the notebook (3)'));
    await tester.pumpAndSettle();

    expect((await pages()).map((p) => p.paper), everyElement(isNull));
    expect(find.text('Changed 3 pages'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect((await pages()).map((p) => p.paper), everyElement(grid));
  });

  testWidgets('a template change can go on just this page', (tester) async {
    await pumpNotebook(tester);
    await tester.tap(find.byTooltip('Page options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change template…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plain paper'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This page'));
    await tester.pumpAndSettle();

    final byId = {for (final p in await pages()) p.id: p};
    expect(byId[pageIds[0]]!.paper, isNull);
    expect(byId[pageIds[1]]!.paper, grid);
    expect(byId[pageIds[2]]!.paper, grid);
  });

  testWidgets('a page is added right after the one being written on', (
    tester,
  ) async {
    await pumpNotebook(tester);
    await tester.tap(find.byTooltip('Add page after this'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Same as this page'));
    await tester.pumpAndSettle();

    final ordered = (await pages())..sort((a, b) => a.order.compareTo(b.order));
    expect(ordered, hasLength(4));
    expect(ordered[0].id, pageIds[0]);
    expect(ordered[1].id, isNot(anyOf(pageIds)));
    expect(ordered[1].paper, grid, reason: 'like the page it follows');
    expect(ordered[2].id, pageIds[1]);
  });
}
