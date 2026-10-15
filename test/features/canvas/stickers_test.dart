import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/catalog/catalog_item.dart';
import 'package:notely/core/catalog/catalog_providers.dart';
import 'package:notely/core/catalog/catalog_repository.dart';
import 'package:notely/core/catalog/pack_cache.dart';
import 'package:notely/core/catalog/pack_disk_memory.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/auth/auth_repository.dart';
import 'package:notely/features/canvas/domain/page_element.dart';
import 'package:notely/features/canvas/ink_tools.dart';
import 'package:notely/features/canvas/page_canvas.dart';
import 'package:notely/features/canvas/stickers.dart';
import 'package:notely/features/notebooks/data/firestore_notes_backend.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/data/notes_repository.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';
import 'package:notely/features/notebooks/notes_providers.dart';
import 'package:notely/features/notebooks/page_screen.dart';

import '../../core/catalog/catalog_test.dart' show FakeDownloader, zip;
import '../../helpers.dart';

/// A 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAj'
  'CB0C8AAAAASUVORK5CYII=',
);

const _frame = ElementFrame(center: Offset(500, 400), width: 200, height: 100);

PageElement sticker(String id, {double z = 1, ElementFrame frame = _frame}) =>
    PageElement(
      id: id,
      content: const StickerContent(
        itemId: 'basics',
        file: 'stickers/star.webp',
      ),
      frame: frame,
      z: z,
      createdAt: 0,
    );

/// A free "Basics" pack with one sticker, published to [downloader].
CatalogItem basicsPack(FakeDownloader downloader) {
  final pack = zip({
    'stickers.json': utf8.encode(
      jsonEncode({
        'stickers': [
          {'file': 'stickers/star.webp', 'name': 'Star'},
          {'file': 'stickers/missing.webp', 'name': 'Missing'},
        ],
      }),
    ),
    'stickers/star.webp': _png,
  });
  downloader.files['catalog/basics/1/pack.zip'] = pack;
  return CatalogItem.fromMap('basics', {
    'kind': 'stickers',
    'name': 'Basics',
    'version': 1,
    'visibility': 'public',
    'unlock': {'free': true},
    'files': {
      'pack': 'catalog/basics/1/pack.zip',
      'sha256': sha256.convert(pack).toString(),
      'bytes': pack.length,
    },
  })!;
}

void main() {
  group('ElementFrame', () {
    test('page and local coordinates round-trip, rotated', () {
      const f = ElementFrame(
        center: Offset(100, 50),
        width: 40,
        height: 20,
        rotation: 0.7,
      );
      final p = f.toPage(const Offset(12, -5));
      final back = f.toLocal(p);
      expect(back.dx, closeTo(12, 1e-9));
      expect(back.dy, closeTo(-5, 1e-9));
    });

    test('contains follows the rotation', () {
      const f = ElementFrame(
        center: Offset.zero,
        width: 100,
        height: 10,
        rotation: math.pi / 2,
      );
      // Turned a quarter: tall and thin.
      expect(f.contains(const Offset(0, 45)), isTrue);
      expect(f.contains(const Offset(45, 0)), isFalse);
    });
  });

  group('PageElement', () {
    test('survives saving and loading', () {
      final e = sticker('a');
      final back = PageElement.fromMap('a', e.toMap())!;
      expect(back.frame, e.frame);
      expect(back.content, e.content);
    });

    test('kinds from newer apps are skipped', () {
      expect(
        PageElement.fromMap('a', {...sticker('a').toMap(), 'kind': 'video'}),
        isNull,
      );
    });
  });

  test('a sticker pack lists only stickers whose images it has', () {
    final d = FakeDownloader();
    final item = basicsPack(d);
    final pack = StickerPack.fromFiles(item, {
      'stickers.json': Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'stickers': [
              {'file': 'stickers/star.webp', 'name': 'Star'},
              {'file': 'stickers/missing.webp', 'name': 'Missing'},
            ],
          }),
        ),
      ),
      'stickers/star.webp': _png,
    });
    expect(pack.stickers.map((s) => s.name), ['Star']);
  });

  final backends = <String, NotesBackend Function()>{
    'in memory': InMemoryNotesBackend.new,
    'Firestore': () => FirestoreNotesBackend(FakeFirebaseFirestore()),
  };
  for (final MapEntry(key: name, value: make) in backends.entries) {
    group('elements ($name)', () {
      late NotesBackend backend;
      late ElementRepository elements;

      setUp(() {
        backend = make();
        elements = backend.elements('sam');
      });

      Future<List<PageElement>> read(String pageId) async {
        await pumpEventQueue();
        return elements.watchElements(pageId).first;
      }

      test('are listed bottom first and can be moved and removed', () async {
        await elements.addElement('p', sticker('top', z: 2));
        await elements.addElement('p', sticker('bottom'));
        expect((await read('p')).map((e) => e.id), ['bottom', 'top']);

        const moved = ElementFrame(
          center: Offset(1, 2),
          width: 3,
          height: 4,
          rotation: 0.5,
        );
        await elements.setElementFrame('p', 'top', moved);
        await elements.setElementDeleted('p', 'bottom', deleted: true);

        final after = {for (final e in await read('p')) e.id: e};
        expect(after['top']!.frame, moved);
        expect(after['bottom']!.deleted, isTrue);
      });

      test('go when their page is deleted', () async {
        final notebooks = backend.notebooks('sam');
        final nb = await notebooks.createNotebook(
          const NewNotebook(title: 'N', cover: NotebookCover.color(1)),
        );
        await pumpEventQueue();
        final section = (await notebooks.watchSections(nb.id).first).single;
        final page = await notebooks.createPage(nb.id, section.id);
        await pumpEventQueue();
        await elements.addElement(page.id, sticker('a'));

        await notebooks.deletePage(page.id);

        expect(await read(page.id), isEmpty);
      });
    });
  }

  group('on a page', () {
    late List<SkinManifest> skins;
    late InMemoryNotesBackend backend;
    late String uid;
    late String pageId;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      skins = await loadTestSkins();
    });

    Future<List<PageElement>> stickers() async =>
        (await backend.elements(uid).watchElements(pageId).first)
            .where((e) => !e.deleted)
            .toList();

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }

    Future<ProviderContainer> pumpPage(
      WidgetTester tester, {
      bool readOnly = false,
      bool inkEnabled = true,
    }) async {
      tester.view
        ..physicalSize = const Size(800, 1000)
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
      pageId = (await repo.createPage(nb.id, section.id)).id;
      final downloader = FakeDownloader();
      final container = await makeContainer(
        skins,
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          notesBackendProvider.overrideWithValue(backend),
          catalogRepositoryProvider.overrideWithValue(
            InMemoryCatalogRepository([basicsPack(downloader)]),
          ),
          packCacheProvider.overrideWithValue(
            PackCache(downloader, MemoryPackDisk()),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: themed(
            skinById(skins, 'classic'),
            PageScreen(
              pageId: pageId,
              readOnly: readOnly,
              inkEnabled: inkEnabled,
            ),
          ),
        ),
      );
      await settle(tester);
      return container;
    }

    /// Opens the tray and places the Star sticker.
    Future<void> placeStar(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Stickers'));
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Image),
        ),
      );
      await settle(tester);
    }

    /// Where a page point is on screen.
    Offset onScreen(WidgetTester tester, Offset page) {
      // The page surface, inside the zoom transform.
      final surface = find.descendant(
        of: find
            .descendant(
              of: find.byType(PageCanvas),
              matching: find.byType(Transform),
            )
            .first,
        matching: find.byType(Container),
      );
      final box = tester.renderObject<RenderBox>(surface.first);
      return box.localToGlobal(page);
    }

    Future<void> drag(
      WidgetTester tester,
      Offset from,
      Offset to, {
      PointerDeviceKind kind = PointerDeviceKind.touch,
    }) async {
      final g = await tester.startGesture(from, kind: kind);
      for (var i = 1; i <= 5; i++) {
        await g.moveTo(Offset.lerp(from, to, i / 5)!);
      }
      await g.up();
      await settle(tester);
    }

    testWidgets('a sticker from the tray lands on the page, selected', (
      tester,
    ) async {
      final container = await pumpPage(tester);

      await placeStar(tester);

      final placed = (await stickers()).single;
      expect(
        placed.content,
        const StickerContent(itemId: 'basics', file: 'stickers/star.webp'),
      );
      expect(placed.frame.width, 240);
      expect(container.read(inkToolProvider).kind, InkToolKind.select);
      expect(find.byType(StickerView), findsOneWidget);
    });

    testWidgets('a sticker can be moved, resized and rotated', (tester) async {
      await pumpPage(tester);
      await placeStar(tester);
      final start = (await stickers()).single.frame;

      // Move it.
      final center = onScreen(tester, start.center);
      await drag(tester, center, center + const Offset(60, 40));
      final moved = (await stickers()).single.frame;
      expect(moved.center.dx, greaterThan(start.center.dx));
      expect(moved.width, start.width);

      // Resize from the bottom-right corner; it keeps its shape.
      final corner = onScreen(
        tester,
        moved.toPage(Offset(moved.width / 2, moved.height / 2)),
      );
      await drag(tester, corner, corner + const Offset(40, 40));
      final resized = (await stickers()).single.frame;
      expect(resized.width, greaterThan(moved.width));
      expect(
        resized.width / resized.height,
        closeTo(moved.width / moved.height, 1e-6),
      );

      // Rotate with the handle above it, a quarter turn to the right.
      final top =
          onScreen(tester, resized.center) -
          Offset(0, (resized.height / 2) * 0.5 + 40);
      final right = onScreen(tester, resized.center) + const Offset(200, 0);
      await drag(tester, top, right);
      expect(
        (await stickers()).single.frame.rotation,
        closeTo(math.pi / 2, 0.01),
      );
    });

    testWidgets('the remove handle removes it, and undo brings it back', (
      tester,
    ) async {
      await pumpPage(tester);
      await placeStar(tester);
      final f = (await stickers()).single.frame;

      await tester.tapAt(
        onScreen(tester, f.toPage(Offset(-f.width / 2, -f.height / 2))),
      );
      await settle(tester);
      expect(await stickers(), isEmpty);

      await tester.ensureVisible(find.byTooltip('Undo'));
      await tester.tap(find.byTooltip('Undo'));
      await settle(tester);
      expect(await stickers(), hasLength(1));

      // Undo the placing too, then redo it.
      await tester.ensureVisible(find.byTooltip('Undo'));
      await tester.tap(find.byTooltip('Undo'));
      await settle(tester);
      expect(await stickers(), isEmpty);
      await tester.ensureVisible(find.byTooltip('Redo'));
      await tester.tap(find.byTooltip('Redo'));
      await settle(tester);
      expect(await stickers(), hasLength(1));
    });

    testWidgets('undo puts a moved sticker back', (tester) async {
      await pumpPage(tester);
      await placeStar(tester);
      final start = (await stickers()).single.frame;
      final center = onScreen(tester, start.center);
      await drag(tester, center, center + const Offset(80, 0));

      await tester.ensureVisible(find.byTooltip('Undo'));
      await tester.tap(find.byTooltip('Undo'));
      await settle(tester);

      expect((await stickers()).single.frame, start);
    });

    testWidgets("the select tool doesn't draw", (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byTooltip('Select'));
      await tester.pump();

      final c = tester.getCenter(find.byType(PageCanvas));
      await drag(
        tester,
        c,
        c + const Offset(100, 30),
        kind: PointerDeviceKind.stylus,
      );

      expect(await backend.strokes(uid).watchStrokes(pageId).first, isEmpty);
    });

    testWidgets('on the web, stickers move with any tool, and Delete '
        'removes them', (tester) async {
      final container = await pumpPage(tester, inkEnabled: false);
      await backend.elements(uid).addElement(pageId, sticker('s'));
      await settle(tester);
      // The pen is still the chosen tool, but the web can't draw.
      expect(container.read(inkToolProvider).kind, InkToolKind.pen);

      final center = onScreen(tester, _frame.center);
      await drag(
        tester,
        center,
        center + const Offset(80, 0),
        kind: PointerDeviceKind.mouse,
      );
      expect((await stickers()).single.frame.center.dx, greaterThan(500));

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await settle(tester);
      expect(await stickers(), isEmpty);
    });

    testWidgets('view-only pages show stickers but cannot change them', (
      tester,
    ) async {
      await backend.elements('x').addElement('y', sticker('unused'));
      final container = await pumpPage(tester, readOnly: true);
      await backend.elements(uid).addElement(pageId, sticker('s'));
      await settle(tester);
      expect(find.byType(StickerView), findsOneWidget);

      container.read(inkToolProvider.notifier).selectTool(InkToolKind.select);
      await tester.pump();
      final center = onScreen(tester, _frame.center);
      await drag(tester, center, center + const Offset(80, 0));

      expect((await stickers()).single.frame, _frame);
    });
  });
}
