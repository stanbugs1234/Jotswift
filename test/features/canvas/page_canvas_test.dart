import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/auth/auth_repository.dart';
import 'package:notely/features/canvas/domain/stroke.dart';
import 'package:notely/features/canvas/ink_toolbar.dart';
import 'package:notely/features/canvas/page_canvas.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/notes_providers.dart';
import 'package:notely/features/notebooks/page_screen.dart';

import '../../helpers.dart';

class _Page {
  _Page(this.backend, this.uid, this.pageId);

  final InMemoryNotesBackend backend;
  final String uid;
  final String pageId;

  Future<List<Stroke>> strokes() =>
      backend.strokes(uid).watchStrokes(pageId).first;

  Future<List<Stroke>> visibleStrokes() async =>
      (await strokes()).where((s) => !s.deleted).toList();
}

void main() {
  late List<SkinManifest> skins;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    skins = await loadTestSkins();
  });

  Future<_Page> pumpPage(WidgetTester tester, {bool readOnly = false}) async {
    tester.view
      ..physicalSize = const Size(800, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final auth = DevAuthRepository();
    await auth.signInWithEmail('sam@example.com', 'secret1');
    final uid = auth.currentUser!.uid;
    final backend = InMemoryNotesBackend();
    final repo = backend.notebooks(uid);
    final nb = await repo.createNotebook('School', 0);
    final section = (await repo.watchSections(nb.id).first).single;
    final page = await repo.createPage(nb.id, section.id);

    final container = await makeContainer(
      skins,
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        notesBackendProvider.overrideWithValue(backend),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: themed(
          skinById(skins, 'classic'),
          PageScreen(pageId: page.id, readOnly: readOnly),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return _Page(backend, uid, page.id);
  }

  Offset canvasCenter(WidgetTester tester) =>
      tester.getCenter(find.byType(PageCanvas));

  Future<void> drag(
    WidgetTester tester,
    PointerDeviceKind kind, {
    Offset from = Offset.zero,
    Offset by = const Offset(120, 40),
    int pointer = 1,
  }) async {
    final start = canvasCenter(tester) + from;
    final gesture = await tester.startGesture(
      start,
      kind: kind,
      pointer: pointer,
    );
    for (var i = 1; i <= 6; i++) {
      await gesture.moveTo(start + by * (i / 6));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('a stylus draws a stroke that gets saved', (tester) async {
    final page = await pumpPage(tester);

    await drag(tester, PointerDeviceKind.stylus);

    final strokes = await page.strokes();
    expect(strokes, hasLength(1));
    expect(strokes.single.tool, InkTool.pen);
    expect(strokes.single.points.length, greaterThan(3));
    // Saved in page units: the 120px drag is wider on the full-size page.
    expect(strokes.single.bounds.width, greaterThan(120));
  });

  testWidgets('without a stylus, a finger draws', (tester) async {
    final page = await pumpPage(tester);

    await drag(tester, PointerDeviceKind.touch);

    expect(await page.visibleStrokes(), hasLength(1));
  });

  testWidgets('after a stylus is used, fingers scroll instead of drawing', (
    tester,
  ) async {
    final page = await pumpPage(tester);
    await drag(tester, PointerDeviceKind.stylus);

    await drag(tester, PointerDeviceKind.touch, from: const Offset(0, 100));

    expect(await page.visibleStrokes(), hasLength(1));
  });

  testWidgets('in hand mode a finger scrolls but a stylus still draws', (
    tester,
  ) async {
    final page = await pumpPage(tester);
    await tester.tap(find.byTooltip('Hand (scroll with one finger)'));
    await tester.pump();

    await drag(tester, PointerDeviceKind.touch);
    expect(await page.visibleStrokes(), isEmpty);

    await drag(tester, PointerDeviceKind.stylus);
    expect(await page.visibleStrokes(), hasLength(1));
  });

  testWidgets('a second finger cancels a finger stroke (pinch to zoom)', (
    tester,
  ) async {
    final page = await pumpPage(tester);
    final center = canvasCenter(tester);

    final first = await tester.startGesture(center, pointer: 1);
    await first.moveBy(const Offset(20, 0));
    final second = await tester.startGesture(
      center + const Offset(100, 100),
      pointer: 2,
    );
    await first.moveBy(const Offset(-30, -30));
    await second.moveBy(const Offset(30, 30));
    await first.up();
    await second.up();
    await tester.pumpAndSettle();

    expect(await page.strokes(), isEmpty);
  });

  testWidgets('undo hides the last stroke and redo brings it back', (
    tester,
  ) async {
    final page = await pumpPage(tester);
    await drag(tester, PointerDeviceKind.stylus);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(await page.visibleStrokes(), isEmpty);

    await tester.tap(find.byTooltip('Redo'));
    await tester.pumpAndSettle();
    expect(await page.visibleStrokes(), hasLength(1));
  });

  testWidgets('the eraser removes strokes it touches, and undo restores', (
    tester,
  ) async {
    final page = await pumpPage(tester);
    await drag(tester, PointerDeviceKind.stylus, by: const Offset(150, 0));
    await drag(
      tester,
      PointerDeviceKind.stylus,
      from: const Offset(0, 200),
      by: const Offset(150, 0),
    );

    await tester.tap(find.byTooltip('Eraser'));
    await tester.pump();
    // Cross only the first line.
    await drag(
      tester,
      PointerDeviceKind.stylus,
      from: const Offset(75, -40),
      by: const Offset(0, 80),
    );

    expect(await page.visibleStrokes(), hasLength(1));

    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(await page.visibleStrokes(), hasLength(2));
  });

  testWidgets('the highlighter draws see-through, wide strokes', (
    tester,
  ) async {
    final page = await pumpPage(tester);
    await tester.tap(find.byTooltip('Highlighter'));
    await tester.pump();

    await drag(tester, PointerDeviceKind.stylus);

    final stroke = (await page.strokes()).single;
    expect(stroke.tool, InkTool.highlighter);
    expect(Color(stroke.color).a, closeTo(0.35, 0.01));
    expect(stroke.width, greaterThan(10));
  });

  testWidgets('the chosen ink color is used', (tester) async {
    final page = await pumpPage(tester);
    final inkColors = skinById(skins, 'classic').inkColors;

    await tester.tap(find.bySemanticsLabel('Ink color 3'));
    await tester.pump();
    await drag(tester, PointerDeviceKind.stylus);

    expect((await page.strokes()).single.color, inkColors[2].toARGB32());
  });

  testWidgets('view-only pages have no tools and ignore drawing', (
    tester,
  ) async {
    final page = await pumpPage(tester, readOnly: true);

    expect(find.byType(InkToolbar), findsNothing);
    expect(find.textContaining('view-only on the web'), findsOneWidget);

    await drag(tester, PointerDeviceKind.stylus);
    await drag(tester, PointerDeviceKind.mouse);
    expect(await page.strokes(), isEmpty);
  });
}
