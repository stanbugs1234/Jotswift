import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';
import 'package:notely/features/notebooks/page_screen.dart';
import 'package:notely/features/shelf/shelf_view.dart';

import '../../helpers.dart';
import 'shelf_view_test.dart' show notebook;

Notebook tagged(String id, List<String> tags, {int? trashedAt}) {
  final n = notebook(id).copyWith(tags: tags);
  return trashedAt == null ? n : n.copyWith(trashedAt: trashedAt);
}

void main() {
  group('tags on the shelf', () {
    final shelf = Shelf([
      tagged('a', ['Meeting', 'ideas']),
      tagged('b', ['meeting']),
      tagged('c', []),
    ], const []);

    test('a tag lists its notebooks, ignoring case', () {
      final ids = shelf
          .contents(const TaggedNotebooks('MEETING'), ShelfSort.name)
          .notebooks
          .map((n) => n.id);
      expect(ids, ['a', 'b']);
    });

    test('tags are counted once each, by name', () {
      expect(shelf.tagCounts, {'ideas': 1, 'Meeting': 2});
    });

    test('search finds tags; "#" looks only in tags', () {
      final withTitle = Shelf([
        tagged('a', ['ideas']),
        notebook('b', title: 'Ideas list'),
      ], const []);
      expect(
        withTitle.search('idea').map((n) => n.id),
        unorderedEquals(['a', 'b']),
      );
      expect(withTitle.search('#idea').map((n) => n.id), ['a']);
    });

    test('the location goes through its URL', () {
      const at = TaggedNotebooks('to do & more');
      final uri = Uri.parse(at.path);
      expect(ShelfLocation.fromQuery(uri.queryParameters), at);
      expect(at.canCreate, isFalse);
    });
  });

  group('the model', () {
    test('tags are kept, and left out when there are none', () {
      final map = tagged('a', ['x', 'y']).toMap();
      expect(map['tags'], ['x', 'y']);
      expect(Notebook.fromMap('a', map).tags, ['x', 'y']);
      expect(notebook('b').toMap().containsKey('tags'), isFalse);
    });

    test('normalizeTag', () {
      expect(normalizeTag('  #  big   ideas '), 'big ideas');
      expect(normalizeTag('##'), '');
      expect(normalizeTag('x' * 40).length, 30);
    });

    test('the in-memory backend saves and clears them', () async {
      final backend = InMemoryNotesBackend();
      final notebooks = backend.notebooks('u');
      final shelf = backend.shelf('u');
      final created = await notebooks.createNotebook(
        const NewNotebook(title: 'T', cover: NotebookCover.color(0)),
      );
      await shelf.setTags(created.id, ['a']);
      var n = (await notebooks.watchNotebooks().first).single;
      expect(n.tags, ['a']);
      await shelf.setTags(created.id, []);
      n = (await notebooks.watchNotebooks().first).single;
      expect(n.tags, isEmpty);
    });
  });

  group('tablet', () {
    late List<SkinManifest> skins;
    setUpAll(() async => skins = await loadTestSkins());

    testWidgets('a quick note is tagged from its page and found in the '
        'sidebar', (tester) async {
      await pumpApp(tester, skins, size: const Size(1366, 1024));
      await tester.tap(find.text('Quick note').first);
      await tester.pumpAndSettle();
      expect(find.byType(PageScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Tags'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'meeting');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, '#meeting'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Back to the shelf.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      final tag = find.widgetWithText(ListTile, '#meeting');
      await tester.ensureVisible(tag);
      await tester.pumpAndSettle();
      await tester.tap(tag);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('shelf-title')).last).data,
        '#meeting',
      );
      expect(find.text('Quick note'), findsWidgets);

      // Removing the last one takes the tag out of the sidebar.
      await tester.tap(find.byTooltip('Notebook options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tags…'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove #meeting'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, '#meeting'), findsNothing);
      expect(find.text('No notebooks tagged #meeting'), findsOneWidget);
    });
  });
}
