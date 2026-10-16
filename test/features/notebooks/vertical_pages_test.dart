import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/app/router.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/canvas/domain/page_element.dart';
import 'package:notely/features/canvas/domain/stroke.dart';
import 'package:notely/features/canvas/page_canvas.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';
import 'package:notely/features/notebooks/notes_providers.dart';
import 'package:notely/features/notebooks/vertical_pages.dart';

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

  /// A notebook of four pages (or [titles]), open on the first, at
  /// 1000 x 900.
  Future<ProviderContainer> pumpPages(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
    List<String> titles = const ['One', 'Two', 'Three', 'Four'],
  }) async {
    final auth = await pumpApp(
      tester,
      skins,
      size: const Size(1000, 900),
      prefs: prefs,
      overrides: [notesBackendProvider.overrideWithValue(backend)],
    );
    uid = auth.currentUser!.uid;
    final repo = backend.notebooks(uid);
    final nb = await repo.createNotebook(
      const NewNotebook(title: 'Bio', cover: NotebookCover.color(1)),
    );
    final section = (await repo.watchSections(nb.id).first).single;
    pageIds = [
      for (final t in titles)
        (await repo.createPage(nb.id, section.id, title: t)).id,
    ];
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Navigator).first),
    );
    container
        .read(routerProvider)
        .go('/notebooks/${nb.id}/pages/${pageIds[0]}');
    await tester.pumpAndSettle();
    return container;
  }

  String appBarTitle(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('page-title'))).data!;

  testWidgets('pages can be scrolled one under another', (tester) async {
    final container = await pumpPages(tester);
    expect(find.byType(PageCanvas), findsOneWidget);

    await tester.tap(find.byTooltip('Page options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scroll vertically'));
    await tester.pumpAndSettle();

    expect(container.read(pageScrollProvider), PageScroll.vertical);
    expect(find.byType(VerticalPages), findsOneWidget);
    expect(appBarTitle(tester), 'One');

    // Until a pen is used, fingers draw, so two fingers scroll.
    final center = tester.getCenter(find.byType(VerticalPages));
    final a = await tester.startGesture(center - const Offset(60, 0));
    final b = await tester.startGesture(center + const Offset(60, 0));
    for (var i = 0; i < 30; i++) {
      await a.moveBy(const Offset(0, -50));
      await b.moveBy(const Offset(0, -50));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(appBarTitle(tester), isNot('One'));

    await tester.tap(find.byTooltip('Page options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show page by page'));
    await tester.pumpAndSettle();
    expect(find.byType(VerticalPages), findsNothing);
  });

  testWidgets('the choice is remembered on this device', (tester) async {
    await pumpPages(tester, prefs: {'pageScroll': 'vertical'});

    expect(find.byType(VerticalPages), findsOneWidget);
  });

  testWidgets('Next page scrolls to it', (tester) async {
    await pumpPages(tester, prefs: {'pageScroll': 'vertical'});

    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();

    expect(appBarTitle(tester), 'Two');
  });

  for (final fingers in ['on', 'off']) {
    testWidgets('a link scrolls to the page it points to (fingers $fingers)', (
      tester,
    ) async {
      await pumpPages(
        tester,
        prefs: {'pageScroll': 'vertical', 'fingerDrawing': fingers},
      );
      await backend
          .elements(uid)
          .addElement(
            pageIds[0],
            PageElement(
              id: 'to-four',
              content: LinkContent(pageIds[3]),
              frame: const ElementFrame(
                center: Offset(500, 400),
                width: 400,
                height: 200,
              ),
              z: 1,
              createdAt: 0,
            ),
          );
      await tester.pumpAndSettle();

      final first = find.byType(PageCanvas).first;
      final scale = tester.getSize(first).width / pageSize.width;
      await tester.tapAt(
        tester.getTopLeft(first) + const Offset(500, 400) * scale,
      );
      await tester.pumpAndSettle();

      expect(appBarTitle(tester), 'Four');
    });
  }

  testWidgets('a link to a page far down goes there, not back to the start', (
    tester,
  ) async {
    await pumpPages(
      tester,
      prefs: {'pageScroll': 'vertical', 'fingerDrawing': 'off'},
      titles: [for (var i = 1; i <= 40; i++) 'Page $i'],
    );
    await backend
        .elements(uid)
        .addElement(
          pageIds[0],
          PageElement(
            id: 'to-last',
            content: LinkContent(pageIds.last),
            frame: const ElementFrame(
              center: Offset(500, 400),
              width: 400,
              height: 200,
            ),
            z: 1,
            createdAt: 0,
          ),
        );
    await tester.pumpAndSettle();

    final first = find.byType(PageCanvas).first;
    final scale = tester.getSize(first).width / pageSize.width;
    await tester.tapAt(
      tester.getTopLeft(first) + const Offset(500, 400) * scale,
    );
    await tester.pumpAndSettle();

    expect(appBarTitle(tester), 'Page 40');
  });

  testWidgets('the pen writes on a page without scrolling', (tester) async {
    await pumpPages(tester, prefs: {'pageScroll': 'vertical'});
    final list = find.byType(Scrollable).last;
    final before = tester.state<ScrollableState>(list).position.pixels;

    final firstPage = tester.getRect(find.byType(PageCanvas).first);
    final pen = await tester.startGesture(
      firstPage.center,
      kind: PointerDeviceKind.stylus,
    );
    for (var i = 1; i <= 10; i++) {
      await pen.moveBy(const Offset(0, -20));
      await tester.pump();
    }
    await pen.up();
    await tester.pumpAndSettle();

    expect(tester.state<ScrollableState>(list).position.pixels, before);
    final strokes = await backend.strokes(uid).watchStrokes(pageIds[0]).first;
    expect(strokes, hasLength(1));
  });

  testWidgets('once the pen is used, one finger scrolls', (tester) async {
    await pumpPages(tester, prefs: {'pageScroll': 'vertical'});
    final pen = await tester.startGesture(
      tester.getCenter(find.byType(PageCanvas).first),
      kind: PointerDeviceKind.stylus,
    );
    await pen.up();
    await tester.pumpAndSettle();

    await tester.fling(
      find.byType(VerticalPages),
      const Offset(0, -1400),
      1500,
    );
    await tester.pumpAndSettle();

    expect(appBarTitle(tester), isNot('One'));
    expect(
      await backend.strokes(uid).watchStrokes(pageIds[0]).first,
      hasLength(lessThanOrEqualTo(1)),
    );
  });
}
