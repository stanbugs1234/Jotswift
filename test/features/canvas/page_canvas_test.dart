import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/paper/basic_papers.dart';
import 'package:notely/core/paper/paper_style.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/core/skins/widgets/paper.dart';
import 'package:notely/features/auth/auth_repository.dart';
import 'package:notely/features/canvas/domain/page_element.dart';
import 'package:notely/features/canvas/domain/stroke.dart';
import 'package:notely/features/canvas/ink_toolbar.dart';
import 'package:notely/features/canvas/ink_tools.dart';
import 'package:notely/features/canvas/page_canvas.dart';
import 'package:notely/features/canvas/pen_rail.dart';
import 'package:notely/features/canvas/stroke_painter.dart';
import 'package:notely/features/canvas/tape.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';
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

  /// The page's strips of tape, not removed.
  Future<List<TapeContent>> tapes() async => [
    for (final e in await backend.elements(uid).watchElements(pageId).first)
      if (!e.deleted && e.content is TapeContent) e.content as TapeContent,
  ];
}

void main() {
  late List<SkinManifest> skins;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    skins = await loadTestSkins();
  });

  Future<_Page> pumpPage(
    WidgetTester tester, {
    bool readOnly = false,
    bool inkEnabled = true,
    String penPanel = 'toolbar',
  }) async {
    tester.view
      ..physicalSize = const Size(800, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final auth = DevAuthRepository();
    await auth.signInWithEmail('sam@example.com', 'secret1');
    final uid = auth.currentUser!.uid;
    final backend = InMemoryNotesBackend();
    final repo = backend.notebooks(uid);
    final nb = await repo.createNotebook(
      NewNotebook(title: 'School', cover: NotebookCover.color(0)),
    );
    final section = (await repo.watchSections(nb.id).first).single;
    final page = await repo.createPage(nb.id, section.id);

    final container = await makeContainer(
      skins,
      prefs: {'penPanelSide': penPanel},
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
          PageScreen(
            pageId: page.id,
            readOnly: readOnly,
            inkEnabled: inkEnabled,
          ),
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

  testWidgets('pen ink runs a little ahead of the pen, but only the real '
      'points are saved', (tester) async {
    final page = await pumpPage(tester);
    LiveStrokePainter live() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<LiveStrokePainter>()
        .single;

    final start = canvasCenter(tester);
    const ms = Duration(milliseconds: 1);
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.stylus,
    );
    for (var i = 1; i <= 6; i++) {
      await gesture.moveTo(
        start + Offset(20.0 * i, 0),
        timeStamp: ms * (8 * i),
      );
    }
    await tester.pump();
    final tip = live().predicted.value.single;
    final drawn = live().live.value!.points.last;
    expect(tip.x, greaterThan(drawn.x));
    expect(tip.y, closeTo(drawn.y, 0.01));

    await gesture.up(timeStamp: ms * 56);
    await tester.pumpAndSettle();
    expect(live().predicted.value, isEmpty);
    final saved = (await page.strokes()).single;
    expect(saved.points, hasLength(7));
    expect(saved.points.last.x, drawn.x);
    expect(saved.followsPen, isTrue);
  });

  testWidgets('finger ink keeps its smoothing and has no guessed tip', (
    tester,
  ) async {
    final page = await pumpPage(tester);
    await drag(tester, PointerDeviceKind.touch);
    expect((await page.strokes()).single.followsPen, isFalse);
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

  testWidgets('a finger moves the page freely, even sideways when it fits', (
    tester,
  ) async {
    final page = await pumpPage(tester);
    await drag(tester, PointerDeviceKind.stylus, by: const Offset(40, 0));

    // Far past the edges: the page goes, but some of it stays in view.
    await drag(tester, PointerDeviceKind.touch, by: const Offset(250, 300));
    await drag(tester, PointerDeviceKind.stylus, by: const Offset(40, 0));

    final strokes = await page.visibleStrokes();
    expect(strokes, hasLength(2));
    final moved = strokes[0].bounds.topLeft - strokes[1].bounds.topLeft;
    expect(moved.dx, greaterThan(200));
    expect(moved.dy, greaterThan(200));
  });

  testWidgets('with the finger toggle off, a finger scrolls but a stylus '
      'still draws', (tester) async {
    final page = await pumpPage(tester);
    await tester.tap(find.byTooltip('Fingers draw · tap so fingers scroll'));
    await tester.pump();
    expect(find.text('Finger scrolls'), findsOneWidget);

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

    await tester.ensureVisible(find.byTooltip('Undo'));
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(await page.visibleStrokes(), isEmpty);

    await tester.ensureVisible(find.byTooltip('Redo'));
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

    await tester.ensureVisible(find.byTooltip('Undo'));
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

    // An upright-iPad-wide toolbar keeps colors under Pen options.
    await tester.ensureVisible(find.byTooltip('Pen options'));
    await tester.tap(find.byTooltip('Pen options'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Ink color 3'));
    await tester.pump();
    await drag(tester, PointerDeviceKind.stylus);

    expect((await page.strokes()).single.color, inkColors[2].toARGB32());
  });

  group('lasso', () {
    /// Draws a loop with the stylus around a box from [topLeft] to
    /// [bottomRight] (relative to the canvas middle).
    Future<void> loop(
      WidgetTester tester, {
      Offset topLeft = const Offset(-60, -60),
      Offset bottomRight = const Offset(200, 100),
    }) async {
      final c = canvasCenter(tester);
      final corners = [
        topLeft,
        Offset(bottomRight.dx, topLeft.dy),
        bottomRight,
        Offset(topLeft.dx, bottomRight.dy),
        topLeft,
      ];
      final gesture = await tester.startGesture(
        c + corners.first,
        kind: PointerDeviceKind.stylus,
      );
      for (var i = 0; i + 1 < corners.length; i++) {
        for (var k = 1; k <= 5; k++) {
          await gesture.moveTo(
            c + Offset.lerp(corners[i], corners[i + 1], k / 5)!,
          );
        }
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    Future<void> chooseLasso(WidgetTester tester) async {
      await tester.ensureVisible(find.byTooltip('Lasso'));
      await tester.tap(find.byTooltip('Lasso'));
      await tester.pump();
    }

    Future<void> tapAction(WidgetTester tester, String label) async {
      await tester.tap(find.byTooltip(label));
      await tester.pumpAndSettle();
    }

    testWidgets('a loop takes handwriting, and dragging moves it', (
      tester,
    ) async {
      final page = await pumpPage(tester);
      await drag(tester, PointerDeviceKind.stylus);
      final before = (await page.visibleStrokes()).single;

      await chooseLasso(tester);
      await loop(tester);
      expect(find.byTooltip('Delete'), findsOneWidget);

      await drag(
        tester,
        PointerDeviceKind.stylus,
        from: const Offset(60, 20),
        by: const Offset(0, 100),
      );

      final after = (await page.visibleStrokes()).single;
      expect(after.id, isNot(before.id));
      expect(after.points, hasLength(before.points.length));
      // 100 screen pixels is about 180 page units at fit-to-width.
      expect(after.bounds.top - before.bounds.top, closeTo(183, 8));
      expect(after.bounds.left, closeTo(before.bounds.left, 1));
      expect(after.color, before.color);

      await tester.ensureVisible(find.byTooltip('Undo'));
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect((await page.visibleStrokes()).single.id, before.id);
    });

    testWidgets('a loop around nothing selects nothing', (tester) async {
      await pumpPage(tester);
      await drag(tester, PointerDeviceKind.stylus);
      await chooseLasso(tester);

      await loop(
        tester,
        topLeft: const Offset(-200, 150),
        bottomRight: const Offset(-100, 250),
      );

      expect(find.byTooltip('Delete'), findsNothing);
    });

    testWidgets('only strokes mostly inside the loop are taken', (
      tester,
    ) async {
      final page = await pumpPage(tester);
      await drag(tester, PointerDeviceKind.stylus);
      await drag(tester, PointerDeviceKind.stylus, from: const Offset(0, 200));
      await chooseLasso(tester);

      await loop(tester);
      await tapAction(tester, 'Delete');

      final left = await page.visibleStrokes();
      expect(left, hasLength(1));
      expect(left.single.bounds.top, greaterThan(1000));
    });

    testWidgets('delete removes the selection, and undo restores it', (
      tester,
    ) async {
      final page = await pumpPage(tester);
      await drag(tester, PointerDeviceKind.stylus);
      await chooseLasso(tester);
      await loop(tester);

      await tapAction(tester, 'Delete');
      expect(await page.visibleStrokes(), isEmpty);
      expect(find.byTooltip('Delete'), findsNothing);

      await tester.ensureVisible(find.byTooltip('Undo'));
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(await page.visibleStrokes(), hasLength(1));
    });

    testWidgets('copy then paste adds a copy; duplicate adds another', (
      tester,
    ) async {
      final page = await pumpPage(tester);
      await drag(tester, PointerDeviceKind.stylus);
      await chooseLasso(tester);
      await loop(tester);

      expect(find.byTooltip('Paste'), findsNothing);
      await tapAction(tester, 'Copy');
      await tester.ensureVisible(find.byTooltip('Paste'));
      await tester.tap(find.byTooltip('Paste'));
      await tester.pumpAndSettle();
      expect(await page.visibleStrokes(), hasLength(2));

      // The pasted copy is selected: duplicate it.
      await tapAction(tester, 'Duplicate');
      final strokes = await page.visibleStrokes();
      expect(strokes, hasLength(3));
      expect(strokes.map((s) => s.id).toSet(), hasLength(3));
    });

    testWidgets('cut removes it until pasted', (tester) async {
      final page = await pumpPage(tester);
      await drag(tester, PointerDeviceKind.stylus);
      await chooseLasso(tester);
      await loop(tester);

      await tapAction(tester, 'Cut');
      expect(await page.visibleStrokes(), isEmpty);

      await tester.ensureVisible(find.byTooltip('Paste'));
      await tester.tap(find.byTooltip('Paste'));
      await tester.pumpAndSettle();
      expect(await page.visibleStrokes(), hasLength(1));
    });

    testWidgets('recoloring changes the ink color', (tester) async {
      final page = await pumpPage(tester);
      final inkColors = skinById(skins, 'classic').inkColors;
      await drag(tester, PointerDeviceKind.stylus);
      await chooseLasso(tester);
      await loop(tester);

      await tapAction(tester, 'Color');
      await tester.tap(
        find.byKey(ValueKey('lasso-color-${inkColors[2].toARGB32()}')),
      );
      await tester.pumpAndSettle();

      final stroke = (await page.visibleStrokes()).single;
      expect(stroke.color, inkColors[2].toARGB32());
    });

    testWidgets('the resize handle scales the handwriting', (tester) async {
      final page = await pumpPage(tester);
      await drag(tester, PointerDeviceKind.stylus);
      final before = (await page.visibleStrokes()).single;
      await chooseLasso(tester);
      await loop(tester);

      // The handle sits on the box's bottom right corner (the stroke's
      // bounds plus half its width), at fit-to-width scale.
      final canvas = tester.getTopLeft(find.byType(PageCanvas));
      final scale = (800 - 32) / pageSize.width;
      final corner = before.bounds.inflate(before.width / 2).bottomRight;
      final handle = canvas + Offset(16, 16) + corner * scale;
      final gesture = await tester.startGesture(
        handle,
        kind: PointerDeviceKind.stylus,
      );
      final middle =
          canvas +
          const Offset(16, 16) +
          before.bounds.inflate(before.width / 2).center * scale;
      for (var k = 1; k <= 5; k++) {
        await gesture.moveTo(handle + (handle - middle) * (k / 5));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      final after = (await page.visibleStrokes()).single;
      expect(after.bounds.width / before.bounds.width, closeTo(2, 0.1));
      expect(after.width, closeTo(before.width * 2, 0.2));
    });

    testWidgets('items in the loop move with the handwriting, in one undo', (
      tester,
    ) async {
      final page = await pumpPage(tester);
      final scale = (800 - 32) / pageSize.width;
      final size = tester.getSize(find.byType(PageCanvas));
      final middle = Offset(size.width / 2 - 16, size.height / 2 - 16) / scale;
      final elements = page.backend.elements(page.uid);
      await elements.addElement(
        page.pageId,
        PageElement(
          id: 'note',
          content: const TextContent(
            text: 'Hi',
            fontSize: 40,
            color: 0xFF000000,
          ),
          frame: ElementFrame(center: middle, width: 120, height: 60),
          z: 1,
          createdAt: 1,
        ),
      );
      await drag(tester, PointerDeviceKind.stylus);
      await chooseLasso(tester);
      await loop(tester);

      await drag(
        tester,
        PointerDeviceKind.stylus,
        from: const Offset(60, 20),
        by: const Offset(0, 100),
      );

      Future<PageElement> note() async =>
          (await elements.watchElements(page.pageId).first).singleWhere(
            (e) => e.id == 'note',
          );
      expect((await note()).frame.center.dy - middle.dy, closeTo(183, 8));

      await tester.ensureVisible(find.byTooltip('Undo'));
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect((await note()).frame.center, middle);
      expect((await page.visibleStrokes()).single.bounds.top, lessThan(1000));
    });

    testWidgets('switching tools lets go of the selection', (tester) async {
      await pumpPage(tester);
      await drag(tester, PointerDeviceKind.stylus);
      await chooseLasso(tester);
      await loop(tester);
      expect(find.byTooltip('Delete'), findsOneWidget);

      await tester.tap(find.byTooltip('Pen'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Delete'), findsNothing);
    });
  });

  group('shapes', () {
    /// Draws through [points] (relative to the canvas middle) with the
    /// stylus, optionally holding still at the end before going on to
    /// [after] and lifting.
    Future<void> draw(
      WidgetTester tester,
      List<Offset> points, {
      Duration hold = Duration.zero,
      Offset? after,
    }) async {
      final c = canvasCenter(tester);
      final gesture = await tester.startGesture(
        c + points.first,
        kind: PointerDeviceKind.stylus,
      );
      for (var i = 0; i + 1 < points.length; i++) {
        for (var k = 1; k <= 6; k++) {
          await gesture.moveTo(
            c + Offset.lerp(points[i], points[i + 1], k / 6)!,
          );
        }
      }
      if (hold > Duration.zero) await tester.pump(hold);
      if (after != null) {
        await gesture.moveTo(c + after);
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    const box = [
      Offset(-100, -60),
      Offset(102, -56),
      Offset(98, 62),
      Offset(-102, 58),
      Offset(-98, -58),
    ];

    testWidgets('holding still at the end snaps a box to a rectangle', (
      tester,
    ) async {
      final page = await pumpPage(tester);

      await draw(tester, box, hold: const Duration(milliseconds: 700));

      final stroke = (await page.visibleStrokes()).single;
      final xs = stroke.points.map((p) => p.x.round()).toSet();
      final ys = stroke.points.map((p) => p.y.round()).toSet();
      // Every point lies on one of the four straight sides.
      final left = xs.reduce(math.min), right = xs.reduce(math.max);
      final top = ys.reduce(math.min), bottom = ys.reduce(math.max);
      for (final p in stroke.points) {
        final onSide =
            (p.x - left).abs() < 1.5 ||
            (p.x - right).abs() < 1.5 ||
            (p.y - top).abs() < 1.5 ||
            (p.y - bottom).abs() < 1.5;
        expect(onSide, isTrue, reason: '${p.x}, ${p.y}');
      }
    });

    testWidgets('without holding, the stroke stays as drawn', (tester) async {
      final page = await pumpPage(tester);

      await draw(tester, box);

      final stroke = (await page.visibleStrokes()).single;
      expect(stroke.points.first.x, isNot(stroke.points.last.x));
    });

    testWidgets('after a line snaps, the pen moves its end', (tester) async {
      final page = await pumpPage(tester);

      await draw(
        tester,
        const [Offset(-100, 0), Offset(100, 4)],
        hold: const Duration(milliseconds: 700),
        after: const Offset(100, 100),
      );

      final stroke = (await page.visibleStrokes()).single;
      final start = stroke.points.first, end = stroke.points.last;
      final scale = (800 - 32) / pageSize.width;
      expect((end.x - start.x) * scale, closeTo(200, 2));
      expect((end.y - start.y) * scale, closeTo(100, 2));
    });
  });

  group('pens', () {
    Future<void> openPenOptions(WidgetTester tester) async {
      await tester.ensureVisible(find.byTooltip('Pen options'));
      await tester.tap(find.byTooltip('Pen options'));
      await tester.pumpAndSettle();
    }

    testWidgets('the pen type is saved with the stroke', (tester) async {
      final page = await pumpPage(tester);
      await openPenOptions(tester);
      await tester.tap(find.text('Brush'));
      await tester.pump();

      await drag(tester, PointerDeviceKind.stylus);

      expect((await page.strokes()).single.style, PenStyle.brush);
    });

    testWidgets('any color can be chosen by hex code', (tester) async {
      final page = await pumpPage(tester);
      await openPenOptions(tester);
      await tester.tap(find.byTooltip('More colors'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1e88e5');
      await tester.tap(find.text('Use hex'));
      await tester.pumpAndSettle();

      await drag(tester, PointerDeviceKind.stylus);

      expect((await page.strokes()).single.color, 0xFF1E88E5);
    });

    testWidgets('the width slider sets any width', (tester) async {
      final page = await pumpPage(tester);
      await openPenOptions(tester);
      await tester.drag(find.byType(Slider).first, const Offset(400, 0));
      await tester.pump();

      await drag(tester, PointerDeviceKind.stylus);

      expect((await page.strokes()).single.width, InkToolState.penRange.max);
    });

    testWidgets('a saved pen brings back its color, width and type', (
      tester,
    ) async {
      final page = await pumpPage(tester);
      final inkColors = skinById(skins, 'classic').inkColors;
      await openPenOptions(tester);
      await tester.tap(find.bySemanticsLabel('Ink color 3'));
      await tester.tap(find.text('Pencil'));
      await tester.tap(find.byTooltip('Thick'));
      await tester.pump();
      await tester.tap(find.text('Save this pen'));
      await tester.pumpAndSettle();
      expect(find.text('Save this pen'), findsNothing);

      // Change everything, then pick the saved pen.
      await tester.tap(find.bySemanticsLabel('Ink color 1'));
      await tester.tap(find.text('Ball'));
      await tester.tap(find.byTooltip('Thin'));
      await tester.pump();
      await tester.tap(find.byTooltip('Use saved pen 1'));
      await tester.pump();

      await drag(tester, PointerDeviceKind.stylus);
      final stroke = (await page.strokes()).single;
      expect(stroke.color, inkColors[2].toARGB32());
      expect(stroke.style, PenStyle.pencil);
      expect(stroke.width, InkToolState.penSizes[2]);
    });
  });

  group('pen panel', () {
    testWidgets('a tablet has the pen options at the side of the page', (
      tester,
    ) async {
      final page = await pumpPage(tester, penPanel: 'left');
      final inkColors = skinById(skins, 'classic').inkColors;
      expect(find.byType(PenRail), findsOneWidget);
      expect(find.byTooltip('Pen options'), findsNothing, reason: 'toolbar');
      expect(
        tester.getCenter(find.byTooltip('Pencil')).dx,
        lessThan(100),
        reason: 'on the left',
      );

      await tester.tap(find.byTooltip('Brush pen'));
      await tester.tap(find.bySemanticsLabel('Ink color 3'));
      await tester.pump();
      await drag(tester, PointerDeviceKind.stylus);

      final stroke = (await page.strokes()).single;
      expect(stroke.style, PenStyle.brush);
      expect(stroke.color, inkColors[2].toARGB32());
    });

    testWidgets('its slider sets the width, and pens can be saved', (
      tester,
    ) async {
      final page = await pumpPage(tester, penPanel: 'right');
      expect(
        tester.getCenter(find.byTooltip('Pencil')).dx,
        greaterThan(700),
        reason: 'on the right',
      );
      await tester.drag(find.byType(Slider).first, const Offset(0, -300));
      await tester.pump();
      await tester.tap(find.byTooltip('Save this pen'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Save this pen'), findsNothing);
      expect(find.byTooltip('Saved pen 1: Fountain'), findsOneWidget);

      await drag(tester, PointerDeviceKind.stylus);
      expect((await page.strokes()).single.width, InkToolState.penRange.max);
    });

    testWidgets('it steps aside for the lasso, and shows eraser sizes', (
      tester,
    ) async {
      await pumpPage(tester, penPanel: 'left');
      await tester.tap(find.byTooltip('Lasso'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pencil'), findsNothing);

      await tester.tap(find.byTooltip('Eraser'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Large eraser'), findsOneWidget);
      expect(find.byTooltip('More colors'), findsNothing);
    });
  });

  group('writing tools', () {
    /// Taps the page with [count] fingers at once.
    Future<void> fingerTap(WidgetTester tester, int count) async {
      final c = canvasCenter(tester);
      final gestures = [
        for (var i = 0; i < count; i++)
          await tester.startGesture(
            c + Offset(i * 60.0 - 60, 200),
            pointer: 20 + i,
          ),
      ];
      for (final g in gestures) {
        await g.up();
      }
      await tester.pumpAndSettle();
    }

    testWidgets('two fingers tap to undo, three to redo', (tester) async {
      final page = await pumpPage(tester);
      await drag(tester, PointerDeviceKind.stylus);
      expect(await page.visibleStrokes(), hasLength(1));

      await fingerTap(tester, 2);
      expect(await page.visibleStrokes(), isEmpty);

      await fingerTap(tester, 3);
      expect(await page.visibleStrokes(), hasLength(1));
    });

    testWidgets('scribbling over writing erases it, in one undo', (
      tester,
    ) async {
      final page = await pumpPage(tester);
      await drag(tester, PointerDeviceKind.stylus, by: const Offset(120, 0));
      final word = (await page.visibleStrokes()).single;

      final c = canvasCenter(tester);
      final pen = await tester.startGesture(
        c + const Offset(-5, -6),
        kind: PointerDeviceKind.stylus,
      );
      for (var i = 1; i <= 8; i++) {
        for (var k = 1; k <= 4; k++) {
          final x = i.isEven ? 125 - 130 * k / 4 : -5 + 130 * k / 4;
          await pen.moveTo(c + Offset(x, -6 + (i - 1 + k / 4) * 1.5));
        }
      }
      await pen.up();
      await tester.pumpAndSettle();
      expect(await page.visibleStrokes(), isEmpty, reason: 'both gone');

      await tester.ensureVisible(find.byTooltip('Undo'));
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect((await page.visibleStrokes()).single.id, word.id);
    });

    testWidgets('pen opacity is saved in the ink', (tester) async {
      final page = await pumpPage(tester, penPanel: 'left');
      await tester.drag(find.byType(Slider).at(1), const Offset(0, 200));
      await tester.pump();
      expect(find.text('10%'), findsOneWidget);

      await drag(tester, PointerDeviceKind.stylus);
      expect(
        Color((await page.strokes()).single.color).a,
        closeTo(InkToolState.minOpacity, 0.01),
      );
    });

    testWidgets('the highlighter can draw straight lines, under the ink', (
      tester,
    ) async {
      final page = await pumpPage(tester, penPanel: 'left');
      await drag(tester, PointerDeviceKind.stylus, by: const Offset(150, 0));
      await tester.tap(find.byTooltip('Highlighter'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Straight lines'));
      await tester.pump();

      // Nearly level: drawn dead level.
      await drag(
        tester,
        PointerDeviceKind.stylus,
        from: const Offset(0, 4),
        by: const Offset(150, 8),
      );
      final highlight = (await page.strokes()).firstWhere(
        (s) => s.tool == InkTool.highlighter,
      );
      final ys = highlight.points.map((p) => p.y);
      expect(ys.reduce(math.max) - ys.reduce(math.min), lessThan(0.5));

      // The highlight, drawn after the writing, is painted under it.
      final pen = (await page.strokes()).firstWhere(
        (s) => s.tool == InkTool.pen,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is StrokesPainter,
        ),
        paints
          ..path(color: Color(highlight.color))
          ..path(color: Color(pen.color)),
      );
    });

    testWidgets('the eyedropper picks up the color of ink on the page', (
      tester,
    ) async {
      final page = await pumpPage(tester, penPanel: 'left');
      final inkColors = skinById(skins, 'classic').inkColors;
      await tester.tap(find.bySemanticsLabel('Ink color 3'));
      await tester.pump();
      await drag(tester, PointerDeviceKind.stylus);
      await tester.tap(find.bySemanticsLabel('Ink color 1'));
      await tester.tap(find.byTooltip('Pick a color from the page'));
      await tester.pump();

      await tester.tapAt(
        canvasCenter(tester) + const Offset(60, 20),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pumpAndSettle();
      expect(await page.strokes(), hasLength(1), reason: 'no new ink');

      await drag(tester, PointerDeviceKind.stylus, from: const Offset(0, 120));
      final strokes = await page.strokes();
      expect(strokes.last.color, inkColors[2].toARGB32());
    });

    testWidgets('a hovering pen shows the size of its mark', (tester) async {
      await pumpPage(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: canvasCenter(tester));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(canvasCenter(tester) + const Offset(10, 10));
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CustomPaint &&
              w.painter.runtimeType.toString() == '_HoverPainter',
        ),
        paints..circle(),
      );
    });

    testWidgets('the pen panel tucks away to a tab and comes back', (
      tester,
    ) async {
      await pumpPage(tester, penPanel: 'left');
      await tester.tap(find.bySemanticsLabel('Hide pen panel'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pencil'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Show pen panel'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pencil'), findsOneWidget);
    });
  });

  group('tape', () {
    testWidgets('lays a strip that a tap peels back and covers again', (
      tester,
    ) async {
      final page = await pumpPage(tester, penPanel: 'left');
      await drag(tester, PointerDeviceKind.stylus, by: const Offset(120, 0));
      await tester.tap(find.byTooltip('Tape'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Striped tape'));
      await drag(tester, PointerDeviceKind.stylus, by: const Offset(160, 0));

      final tape = (await page.tapes()).single;
      expect(tape.pattern, TapePattern.stripes);
      expect(tape.revealed, isFalse);
      expect(find.byType(TapeView), findsOneWidget);

      // A Pencil tap with the pen peels it back instead of leaving a dot.
      await tester.tap(find.byTooltip('Pen'));
      await tester.pump();
      await tester.tapAt(
        canvasCenter(tester) + const Offset(80, 0),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pumpAndSettle();
      expect((await page.tapes()).single.revealed, isTrue);
      expect(await page.visibleStrokes(), hasLength(1), reason: 'no dot');

      // And a finger tap covers it again.
      await tester.tapAt(canvasCenter(tester) + const Offset(80, 0));
      await tester.pumpAndSettle();
      expect((await page.tapes()).single.revealed, isFalse);
    });

    testWidgets('the eraser takes tape off, in one undo with the ink', (
      tester,
    ) async {
      final page = await pumpPage(tester);
      await drag(tester, PointerDeviceKind.stylus, by: const Offset(120, 0));
      await tester.tap(find.byTooltip('Tape'));
      await tester.pump();
      await drag(tester, PointerDeviceKind.stylus, by: const Offset(160, 0));
      expect(await page.tapes(), hasLength(1));

      await tester.tap(find.byTooltip('Eraser'));
      await tester.pump();
      await drag(
        tester,
        PointerDeviceKind.stylus,
        from: const Offset(60, -40),
        by: const Offset(0, 80),
      );
      expect(await page.tapes(), isEmpty);
      expect(await page.visibleStrokes(), isEmpty);

      await tester.ensureVisible(find.byTooltip('Undo'));
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(await page.tapes(), hasLength(1));
      expect(await page.visibleStrokes(), hasLength(1));
    });
  });

  group('eraser options', () {
    Future<void> eraserOption(WidgetTester tester, String label) async {
      await tester.tap(find.byTooltip('Eraser'));
      await tester.pump();
      await tester.ensureVisible(find.byTooltip('Pen options'));
      await tester.tap(find.byTooltip('Pen options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    Future<void> crossFirstLine(WidgetTester tester) => drag(
      tester,
      PointerDeviceKind.stylus,
      from: const Offset(75, -40),
      by: const Offset(0, 80),
    );

    testWidgets('partial erasing cuts a stroke in two, in one undo', (
      tester,
    ) async {
      final page = await pumpPage(tester);
      await drag(tester, PointerDeviceKind.stylus, by: const Offset(150, 0));
      final original = (await page.visibleStrokes()).single;
      await eraserOption(tester, 'Partial');

      await crossFirstLine(tester);

      final pieces = await page.visibleStrokes();
      expect(pieces, hasLength(2));
      expect(pieces.map((p) => p.color).toSet(), {original.color});
      final gapStart = pieces
          .map((p) => p.bounds.right)
          .reduce((a, b) => a < b ? a : b);
      final gapEnd = pieces
          .map((p) => p.bounds.left)
          .reduce((a, b) => a > b ? a : b);
      expect(gapEnd, greaterThan(gapStart));

      await tester.ensureVisible(find.byTooltip('Undo'));
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect((await page.visibleStrokes()).single.id, original.id);
    });

    testWidgets('highlighter only leaves the pen alone', (tester) async {
      final page = await pumpPage(tester);
      await drag(tester, PointerDeviceKind.stylus, by: const Offset(150, 0));
      await tester.tap(find.byTooltip('Highlighter'));
      await tester.pump();
      await drag(
        tester,
        PointerDeviceKind.stylus,
        from: const Offset(0, 10),
        by: const Offset(150, 0),
      );
      await eraserOption(tester, 'Highlighter only');

      await crossFirstLine(tester);

      expect((await page.visibleStrokes()).single.tool, InkTool.pen);
    });

    testWidgets('the eraser can go back to the pen after erasing', (
      tester,
    ) async {
      final page = await pumpPage(tester);
      await drag(tester, PointerDeviceKind.stylus, by: const Offset(150, 0));
      await eraserOption(tester, 'Back to the pen after erasing');

      await crossFirstLine(tester);
      expect(await page.visibleStrokes(), isEmpty);

      await drag(tester, PointerDeviceKind.stylus, from: const Offset(0, 200));
      expect(await page.visibleStrokes(), hasLength(1));
    });
  });

  testWidgets('the laser pointer leaves no ink, and its trail fades', (
    tester,
  ) async {
    final page = await pumpPage(tester);
    await tester.ensureVisible(find.byTooltip('Laser pointer'));
    await tester.tap(find.byTooltip('Laser pointer'));
    await tester.pump();

    await drag(tester, PointerDeviceKind.stylus);

    expect(await page.strokes(), isEmpty);
    // pumpAndSettle in drag returned, so the fade stopped by itself.
  });

  group('Apple Pencil gestures', () {
    Future<void> pencil(WidgetTester tester, String gesture, String action) =>
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'notely/pencil',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('pencilAction', {'gesture': gesture, 'action': action}),
          ),
          (_) {},
        );

    bool selected(WidgetTester tester, String tool) => tester
        .widget<IconButton>(
          find.ancestor(
            of: find.byTooltip(tool),
            matching: find.byType(IconButton),
          ),
        )
        .isSelected!;

    testWidgets('a double-tap follows the iPad: eraser and back', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pumpPage(tester);

      await pencil(tester, 'tap', 'switchEraser');
      await tester.pump();
      expect(selected(tester, 'Eraser'), isTrue);

      await pencil(tester, 'tap', 'switchEraser');
      await tester.pump();
      expect(selected(tester, 'Pen'), isTrue);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('a squeeze can open the pen options', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pumpPage(tester);

      await pencil(tester, 'squeeze', 'showInkAttributes');
      await tester.pumpAndSettle();
      expect(find.text('Pen type'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('ruler', () {
    Future<void> wobblyLine(WidgetTester tester, double y) async {
      final c = canvasCenter(tester);
      final gesture = await tester.startGesture(
        c + Offset(-200, y),
        kind: PointerDeviceKind.stylus,
      );
      for (var i = 1; i <= 10; i++) {
        await gesture.moveTo(
          c + Offset(-200 + i * 40, y + (i.isEven ? 6 : -6)),
        );
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    double spread(Stroke s) {
      final ys = s.points.map((p) => p.y);
      return ys.reduce(math.max) - ys.reduce(math.min);
    }

    testWidgets('a stroke along the edge is drawn straight', (tester) async {
      final page = await pumpPage(tester);
      await tester.ensureVisible(find.byTooltip('Ruler'));
      await tester.tap(find.byTooltip('Ruler'));
      await tester.pump();

      // The ruler's top edge is 55 page units (30 px) above the middle.
      await wobblyLine(tester, -36);
      // Away from the ruler, a line stays as drawn.
      await wobblyLine(tester, 200);

      final strokes = await page.visibleStrokes();
      expect(spread(strokes[0]), lessThan(0.5));
      expect(spread(strokes[1]), greaterThan(10));
    });

    testWidgets('a finger moves the ruler', (tester) async {
      final page = await pumpPage(tester);
      await tester.ensureVisible(find.byTooltip('Ruler'));
      await tester.tap(find.byTooltip('Ruler'));
      await tester.pump();

      await drag(tester, PointerDeviceKind.touch, by: const Offset(0, 100));
      expect(await page.strokes(), isEmpty);

      await wobblyLine(tester, 64);
      expect(spread((await page.visibleStrokes()).single), lessThan(0.5));
    });
  });

  testWidgets('view-only pages have no tools and ignore drawing', (
    tester,
  ) async {
    final page = await pumpPage(tester, readOnly: true);

    expect(find.byType(InkToolbar), findsNothing);
    await drag(tester, PointerDeviceKind.stylus);
    await drag(tester, PointerDeviceKind.mouse);
    expect(await page.strokes(), isEmpty);
  });

  testWidgets('on the web: no pens, but text, photos and stickers', (
    tester,
  ) async {
    final page = await pumpPage(tester, inkEnabled: false);

    expect(find.textContaining('view-only on the web'), findsOneWidget);
    expect(find.byTooltip('Pen'), findsNothing);
    expect(find.byTooltip('Text'), findsOneWidget);
    expect(find.byTooltip('Photo'), findsOneWidget);
    expect(find.byTooltip('Stickers'), findsOneWidget);
    expect(find.byTooltip('Undo'), findsOneWidget);

    await drag(tester, PointerDeviceKind.stylus);
    await drag(tester, PointerDeviceKind.mouse);
    expect(await page.strokes(), isEmpty);
  });

  group('paper', () {
    PaperStyle drawnPaper(WidgetTester tester) => tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(PageCanvas),
            matching: find.byType(CustomPaint),
          ),
        )
        .map((p) => p.painter)
        .whereType<PaperPainter>()
        .single
        .paper;

    final cream = basicPaper(PaperPattern.dot, BasicPaperColor.cream);
    final grid = basicPaper(PaperPattern.grid, BasicPaperColor.gray);

    testWidgets('a page uses the skin paper until something else is chosen', (
      tester,
    ) async {
      await pumpPage(tester);

      expect(drawnPaper(tester).pattern, PaperPattern.lined);
      expect(drawnPaper(tester).color, skinById(skins, 'classic').paper.color);
    });

    testWidgets("a page uses its notebook's paper, and its own over that", (
      tester,
    ) async {
      final page = await pumpPage(tester);
      final repo = page.backend.notebooks(page.uid);
      final notebookId = (await repo.watchPage(page.pageId).first)!.notebookId;

      await repo.updateNotebook(notebookId, paper: cream);
      await tester.pumpAndSettle();
      expect(drawnPaper(tester), cream);

      await repo.setPagePaper(page.pageId, grid);
      await tester.pumpAndSettle();
      expect(drawnPaper(tester), grid);

      await repo.setPagePaper(page.pageId, null);
      await tester.pumpAndSettle();
      expect(drawnPaper(tester), cream);
    });
  });
}
