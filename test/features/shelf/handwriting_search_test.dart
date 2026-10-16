import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/app/app.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';
import 'package:notely/features/notebooks/notes_providers.dart';
import 'package:notely/features/notebooks/page_screen.dart';
import 'package:notely/features/shelf/handwriting_search.dart';

import '../../helpers.dart';

void main() {
  late List<SkinManifest> skins;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    skins = await loadTestSkins();
  });

  NotePage page(String id, String notebookId, String ink, {int at = 0}) =>
      NotePage(
        id: id,
        notebookId: notebookId,
        sectionId: 's',
        title: 'Page $id',
        order: 0,
        createdAt: 0,
        updatedAt: at,
        inkText: ink,
      );

  Notebook notebook(String id, {bool trashed = false}) => Notebook(
    id: id,
    title: 'Book $id',
    cover: const NotebookCover.color(0),
    createdAt: 0,
    updatedAt: 0,
    trashedAt: trashed ? 1 : null,
  );

  test('finds words in any case, newest first, with words around them', () {
    final hits = searchHandwriting(
      [
        page('1', 'a', 'Monday\nbuy milk and Bread for the week', at: 1),
        page('2', 'a', 'bread recipe', at: 2),
        page('3', 'gone', 'bread in the bin'),
        page('4', 'a', 'nothing here'),
      ],
      [notebook('a'), notebook('gone', trashed: true)],
      'BREAD',
    );
    expect(hits.map((h) => h.page.id), ['2', '1'], reason: 'not the Trash');
    final hit = hits.last;
    expect(hit.snippet, 'Monday buy milk and Bread for the week');
    expect(hit.snippet.substring(hit.start, hit.end), 'Bread');
  });

  testWidgets('Home search lists pages by their handwriting', (tester) async {
    await pumpApp(tester, skins, size: const Size(1366, 1024));
    final repo = ProviderScope.containerOf(
      tester.element(find.byType(NotelyApp)),
    ).read(notebookRepositoryProvider);
    final nb = await repo.createNotebook(
      const NewNotebook(title: 'Kitchen', cover: NotebookCover.color(0)),
    );
    final section = (await repo.watchSections(nb.id).first).single;
    final p = await repo.createPage(nb.id, section.id, title: 'Shopping');
    await repo.setPageInkText(p.id, 'eggs, flour and groceries for Sunday');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'grocer');
    await tester.pumpAndSettle();

    expect(find.text('In your handwriting'), findsOneWidget);
    expect(find.text('Kitchen · Shopping'), findsOneWidget);
    await tester.tap(find.text('Kitchen · Shopping'));
    await tester.pumpAndSettle();
    expect(find.byType(PageScreen), findsOneWidget);
  });
}
