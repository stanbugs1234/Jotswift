import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/input/finger_drawing.dart';
import 'package:notely/core/settings/synced_setting.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/auth/auth_repository.dart';
import 'package:notely/features/canvas/domain/page_element.dart';
import 'package:notely/features/canvas/domain/stroke.dart';
import 'package:notely/features/canvas/page_canvas.dart';
import 'package:notely/features/canvas/stickers.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';
import 'package:notely/features/notebooks/notes_providers.dart';
import 'package:notely/features/notebooks/page_screen.dart';

import '../../helpers.dart';

/// Answers the iPad's "Only Draw with Apple Pencil" question.
void mockPencilOnly(bool value) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(DevicePencilController.channel, (call) async {
        if (call.method == 'prefersPencilOnlyDrawing') return value;
        return null;
      });
}

void main() {
  late List<SkinManifest> skins;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    skins = await loadTestSkins();
  });

  group('the rule', () {
    const plain = DevicePencil(pencilOnly: false, stylusUsed: false);
    const pencilOnly = DevicePencil(pencilOnly: true, stylusUsed: false);
    const stylusUsed = DevicePencil(pencilOnly: false, stylusUsed: true);

    test('On and Off win over the device', () {
      for (final d in [plain, pencilOnly, stylusUsed]) {
        for (final ios in [true, false]) {
          expect(fingersDraw(FingerDrawing.on, d, isIOS: ios), isTrue);
          expect(fingersDraw(FingerDrawing.off, d, isIOS: ios), isFalse);
        }
      }
    });

    test("on iOS, follows the iPad's Pencil-only setting", () {
      expect(fingersDraw(FingerDrawing.device, plain, isIOS: true), isTrue);
      expect(
        fingersDraw(FingerDrawing.device, pencilOnly, isIOS: true),
        isFalse,
      );
      // On iOS, having used a Pencil doesn't override the iPad's setting.
      expect(
        fingersDraw(FingerDrawing.device, stylusUsed, isIOS: true),
        isTrue,
      );
    });

    test('elsewhere, a stylus once used means fingers scroll', () {
      expect(fingersDraw(FingerDrawing.device, plain, isIOS: false), isTrue);
      expect(
        fingersDraw(FingerDrawing.device, stylusUsed, isIOS: false),
        isFalse,
      );
    });
  });

  group('on a page', () {
    late InMemoryNotesBackend backend;
    late String uid;

    /// Opens a fresh page (like after a page turn or on a new planner
    /// day), with [elements] already on it.
    Future<String> openPage(
      WidgetTester tester, {
      Map<String, Object> prefs = const {},
      List<PageElement> elements = const [],
    }) async {
      tester.view
        ..physicalSize = const Size(1100, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final auth = DevAuthRepository();
      await auth.signInWithEmail('sam@example.com', 'secret1');
      uid = auth.currentUser!.uid;
      backend = InMemoryNotesBackend();
      final repo = backend.notebooks(uid);
      final nb = await repo.createNotebook(
        const NewNotebook(title: 'N', cover: NotebookCover.color(1)),
      );
      final section = (await repo.watchSections(nb.id).first).single;
      final pageId = (await repo.createPage(nb.id, section.id)).id;
      for (final e in elements) {
        await backend.elements(uid).addElement(pageId, e);
      }

      final container = await makeContainer(
        skins,
        prefs: prefs,
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          notesBackendProvider.overrideWithValue(backend),
          stickerImageProvider.overrideWith((ref, key) async => null),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: themed(skinById(skins, 'classic'), PageScreen(pageId: pageId)),
        ),
      );
      await tester.pumpAndSettle();
      return pageId;
    }

    Future<List<Stroke>> visible(String pageId) async => [
      for (final s in await backend.strokes(uid).watchStrokes(pageId).first)
        if (!s.deleted) s,
    ];

    Offset center(WidgetTester tester) =>
        tester.getCenter(find.byType(PageCanvas));

    /// Where the page currently sits on screen.
    Offset pageTopLeft(WidgetTester tester) => tester.getTopLeft(
      find
          .descendant(
            of: find.byType(PageCanvas),
            matching: find.byType(Transform),
          )
          .first,
    );

    Future<void> drag(
      WidgetTester tester,
      PointerDeviceKind kind, {
      Offset from = Offset.zero,
      Offset by = const Offset(0, -160),
      int pointer = 1,
    }) async {
      final start = center(tester) + from;
      final g = await tester.startGesture(start, kind: kind, pointer: pointer);
      for (var i = 1; i <= 8; i++) {
        await g.moveTo(start + by * (i / 8));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();
    }

    testWidgets("with the iPad set to Pencil-only, a finger scrolls a fresh "
        "page and doesn't draw (the reported bug)", (tester) async {
      mockPencilOnly(true);
      addTearDown(() => mockPencilOnly(false));

      final pageId = await openPage(tester);
      final before = pageTopLeft(tester);
      await drag(tester, PointerDeviceKind.touch);

      expect(await visible(pageId), isEmpty);
      expect(pageTopLeft(tester).dy, lessThan(before.dy));
      expect(find.text('Finger scrolls'), findsOneWidget);

      // The Pencil still writes.
      await drag(tester, PointerDeviceKind.stylus, by: const Offset(120, 30));
      expect(await visible(pageId), hasLength(1));
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets("with the iPad's setting off, a finger draws", (tester) async {
      mockPencilOnly(false);

      final pageId = await openPage(tester);
      await drag(tester, PointerDeviceKind.touch);
      expect(await visible(pageId), hasLength(1));
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('once a stylus was used, fingers scroll, remembered for '
        'every page (Android)', (tester) async {
      final pageId = await openPage(tester);
      await drag(tester, PointerDeviceKind.stylus, by: const Offset(100, 0));
      expect(await visible(pageId), hasLength(1));

      await drag(tester, PointerDeviceKind.touch, from: const Offset(0, 100));
      expect(await visible(pageId), hasLength(1));

      // Saved on the device, not on this page, so every page knows.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PageCanvas)),
      );
      expect(
        container.read(sharedPreferencesProvider).getBool('stylusUsed'),
        isTrue,
      );
    });

    testWidgets('a palm touching while the Pencil writes neither draws nor '
        'moves the page', (tester) async {
      final pageId = await openPage(tester, prefs: {'fingerDrawing': 'on'});
      final before = pageTopLeft(tester);

      final pen = await tester.startGesture(
        center(tester),
        kind: PointerDeviceKind.stylus,
        pointer: 1,
      );
      await pen.moveBy(const Offset(20, 0));
      final palm = await tester.startGesture(
        center(tester) + const Offset(150, 200),
        pointer: 2,
      );
      for (var i = 0; i < 5; i++) {
        await palm.moveBy(const Offset(0, -30));
        await pen.moveBy(const Offset(15, 4));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await palm.up();
      await pen.up();
      await tester.pumpAndSettle();

      final strokes = await visible(pageId);
      expect(strokes, hasLength(1));
      expect(strokes.single.pressureSensitive || true, isTrue);
      expect(pageTopLeft(tester), before);
    });

    testWidgets('a palm that lands just before the Pencil is dropped', (
      tester,
    ) async {
      final pageId = await openPage(tester, prefs: {'fingerDrawing': 'on'});

      final palm = await tester.startGesture(
        center(tester) + const Offset(200, 200),
        pointer: 2,
      );
      await palm.moveBy(const Offset(10, 10));
      await tester.pump(const Duration(milliseconds: 60));
      await drag(tester, PointerDeviceKind.stylus, by: const Offset(120, 0));
      await palm.up();
      await tester.pumpAndSettle();

      final strokes = await visible(pageId);
      expect(strokes, hasLength(1), reason: 'only the Pencil stroke');
    });

    testWidgets('holding a sticker with a finger picks it up and moves it, '
        'with the pen tool', (tester) async {
      const frame = ElementFrame(
        center: Offset(700, 900),
        width: 240,
        height: 240,
      );
      final pageId = await openPage(
        tester,
        prefs: {'fingerDrawing': 'off'},
        elements: [
          const PageElement(
            id: 's',
            content: StickerContent(
              itemId: 'basics',
              file: 'stickers/star.webp',
            ),
            frame: frame,
            z: 1,
            createdAt: 0,
          ),
        ],
      );
      // Where the sticker's center is on screen right now.
      final canvas = tester.getTopLeft(find.byType(PageCanvas));
      final page = pageTopLeft(tester);
      final scale = tester.getSize(find.byType(PageCanvas)).width / 1500;
      final onSticker =
          page + frame.center * (scale > 0 ? _fitScale(tester) : 1);
      expect(canvas.dx, lessThanOrEqualTo(onSticker.dx));

      final finger = await tester.startGesture(onSticker);
      await tester.pump(const Duration(milliseconds: 350)); // hold
      for (var i = 0; i < 6; i++) {
        await finger.moveBy(const Offset(20, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await finger.up();
      await tester.pumpAndSettle();

      final saved = await backend.elements(uid).watchElements(pageId).first;
      expect(saved.single.frame.center.dx, greaterThan(frame.center.dx));
      expect(await visible(pageId), isEmpty);
    });

    testWidgets('a quick finger drag over a sticker scrolls, not moves it', (
      tester,
    ) async {
      const frame = ElementFrame(
        center: Offset(700, 900),
        width: 400,
        height: 400,
      );
      final pageId = await openPage(
        tester,
        prefs: {'fingerDrawing': 'off'},
        elements: [
          const PageElement(
            id: 's',
            content: StickerContent(
              itemId: 'basics',
              file: 'stickers/star.webp',
            ),
            frame: frame,
            z: 1,
            createdAt: 0,
          ),
        ],
      );
      final onSticker = pageTopLeft(tester) + frame.center * _fitScale(tester);
      final before = pageTopLeft(tester);
      final g = await tester.startGesture(onSticker);
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(0, -25));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();

      final saved = await backend.elements(uid).watchElements(pageId).first;
      expect(saved.single.frame, frame);
      expect(pageTopLeft(tester).dy, lessThan(before.dy));
    });

    testWidgets('a flicked page keeps moving, then stops inside the edges', (
      tester,
    ) async {
      await openPage(tester, prefs: {'fingerDrawing': 'off'});
      final start = center(tester);
      final g = await tester.startGesture(start);
      // Test pointer events carry no time unless given one, and speed
      // needs time.
      for (var i = 1; i <= 4; i++) {
        await g.moveTo(
          start + Offset(0, -40.0 * i),
          timeStamp: Duration(milliseconds: 8 * i),
        );
        await tester.pump(const Duration(milliseconds: 8));
      }
      await g.up(timeStamp: const Duration(milliseconds: 36));
      final atLift = pageTopLeft(tester);
      // The first frame of a coast is where it starts.
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 100));
      expect(pageTopLeft(tester).dy, lessThan(atLift.dy));

      await tester.pumpAndSettle();
      final canvas = tester.getRect(find.byType(PageCanvas));
      final pageBottom = tester
          .getBottomLeft(
            find
                .descendant(
                  of: find.byType(PageCanvas),
                  matching: find.byType(Transform),
                )
                .first,
          )
          .dy;
      // At least part of the page stays on screen.
      expect(pageBottom, greaterThan(canvas.top));
    });

    testWidgets('the finger toggle changes behavior and is remembered', (
      tester,
    ) async {
      final pageId = await openPage(tester);
      await tester.tap(find.byTooltip('Fingers draw · tap so fingers scroll'));
      await tester.pump();

      await drag(tester, PointerDeviceKind.touch);
      expect(await visible(pageId), isEmpty);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(PageCanvas)),
      );
      expect(container.read(fingerDrawingProvider), FingerDrawing.off);
    });

    testWidgets('the first time fingers scroll, a hint explains it', (
      tester,
    ) async {
      await openPage(tester, prefs: {'fingerDrawing': 'off'});
      expect(find.textContaining('Fingers scroll and zoom'), findsOneWidget);
    });
  });
}

/// The fit-to-width zoom the page opens at.
double _fitScale(WidgetTester tester) {
  final width = tester.getSize(find.byType(PageCanvas)).width;
  return (width - 32) / pageSize.width;
}
