import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/app/router.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/canvas/domain/page_element.dart';
import 'package:notely/features/canvas/page_canvas.dart';
import 'package:notely/features/canvas/page_items.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';
import 'package:notely/features/notebooks/notes_providers.dart';

import '../../helpers.dart';

void main() {
  late List<SkinManifest> skins;
  late InMemoryNotesBackend backend;
  late String uid;
  late List<String> pageIds;

  setUpAll(() async {
    skins = await loadTestSkins();
  });

  setUp(() => backend = InMemoryNotesBackend());

  test('a link is saved and read back; unknown kinds are skipped', () {
    const link = LinkContent('p2');
    expect(ElementContent.fromMap({...link.toMap()}), link);
    expect(ElementContent.fromMap({'kind': 'link'}), isNull);
    expect(ElementContent.fromMap({'kind': 'hologram'}), isNull);
  });

  test('a page keeps its outline entry', () {
    const page = NotePage(
      id: 'p',
      notebookId: 'n',
      sectionId: 's',
      title: 'Week 1',
      order: 1,
      createdAt: 0,
      updatedAt: 0,
      outline: 'Chapter 1',
    );
    expect(NotePage.fromMap('p', page.toMap()).outline, 'Chapter 1');
    expect(
      page.copyWith(outline: () => null).toMap(),
      isNot(contains('outline')),
    );
  });

  /// A notebook with pages One, Two and Three, open on One.
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
    final section = (await repo.watchSections(nb.id).first).single;
    pageIds = [
      for (final t in ['One', 'Two', 'Three'])
        (await repo.createPage(nb.id, section.id, title: t)).id,
    ];
    ProviderScope.containerOf(tester.element(find.byType(Navigator).first))
        .read(routerProvider)
        .go('/notebooks/${nb.id}/pages/${pageIds[0]}');
    await tester.pumpAndSettle();
  }

  // A page shows its notebook above its title; other screens just a title.
  String appBarTitle(WidgetTester tester) {
    final page = find.byKey(const Key('page-title'));
    return tester
        .widget<Text>(
          page.evaluate().isNotEmpty
              ? page
              : find
                    .descendant(
                      of: find.byType(AppBar),
                      matching: find.byType(Text),
                    )
                    .first,
        )
        .data!;
  }

  Future<void> penPath(WidgetTester tester, List<Offset> points) async {
    final pen = await tester.startGesture(
      points.first,
      kind: PointerDeviceKind.stylus,
    );
    for (final p in points.skip(1)) {
      await pen.moveTo(p);
    }
    await pen.up();
    await tester.pumpAndSettle();
  }

  testWidgets('lassoed writing becomes a link to another page', (tester) async {
    await pumpNotebook(tester);
    final c = tester.getCenter(find.byType(PageCanvas));
    await penPath(tester, [
      for (var x = 0.0; x <= 120; x += 20) c + Offset(x, 0),
    ]);

    await tester.tap(find.byTooltip('Lasso'));
    await tester.pump();
    final corners = [
      const Offset(-40, -40),
      const Offset(160, -40),
      const Offset(160, 40),
      const Offset(-40, 40),
      const Offset(-40, -40),
    ];
    await penPath(tester, [
      for (var i = 0; i + 1 < corners.length; i++)
        for (var k = 1; k <= 5; k++)
          c + Offset.lerp(corners[i], corners[i + 1], k / 5)!,
    ]);
    await tester.tap(find.byTooltip('Link to a page'));
    await tester.pumpAndSettle();
    expect(find.text('Link to page'), findsOneWidget);
    expect(find.text('All pages'), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, 'Two'));
    await tester.pumpAndSettle();

    final elements = await backend
        .elements(uid)
        .watchElements(pageIds[0])
        .first;
    expect((elements.single.content as LinkContent).pageId, pageIds[1]);
    expect(find.byType(LinkView), findsOneWidget);

    // A finger tap on it (the pen has been used, so fingers don't draw)
    // opens the page.
    await tester.tap(find.byTooltip('Pen'));
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.byType(LinkView)));
    await tester.pumpAndSettle();
    expect(appBarTitle(tester), 'Two');
  });

  testWidgets('pages can be added to the outline and found there', (
    tester,
  ) async {
    await pumpNotebook(tester);

    await tester.tap(find.byTooltip('Go to page'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add this page to the outline'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Chapter 1');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.text('Outline'), findsOneWidget);
    expect(find.text('Chapter 1'), findsOneWidget);
    expect(find.byTooltip('Add this page to the outline'), findsNothing);
    final repo = backend.notebooks(uid);
    expect((await repo.watchPage(pageIds[0]).first)!.outline, 'Chapter 1');

    await tester.tap(find.byTooltip('Outline entry options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from outline'));
    await tester.pumpAndSettle();
    expect(find.text('Outline'), findsNothing);
    expect((await repo.watchPage(pageIds[0]).first)!.outline, isNull);
  });
}
