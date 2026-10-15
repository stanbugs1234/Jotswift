import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/auth/auth_repository.dart';
import 'package:notely/features/canvas/domain/page_element.dart';
import 'package:notely/features/canvas/ink_tools.dart';
import 'package:notely/features/canvas/page_items.dart';
import 'package:notely/features/notebooks/data/cover_photos.dart';
import 'package:notely/features/notebooks/data/firestore_notes_backend.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/data/notes_repository.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';
import 'package:notely/features/notebooks/notes_providers.dart';
import 'package:notely/features/notebooks/page_screen.dart';

import '../../helpers.dart';

/// A 2x1 PNG (a landscape photo).
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR4nGP4z8DwH4QBEfcD'
  '/ePF9e8AAAAASUVORK5CYII=',
);

class _OfflinePhotos implements CoverPhotoStore {
  @override
  Future<String> upload(String uid, Uint8List jpeg, {String folder = ''}) =>
      Future.error(Exception('offline'));

  @override
  Future<ImageProvider> image(String path) => Future.error(Exception('none'));
}

const _text = TextContent(
  text: 'Hello',
  fontSize: 40,
  color: 0xFF000000,
  layoutWidth: 300,
);

void main() {
  group('saved elements', () {
    test('photos and text boxes keep every field', () {
      for (final content in <ElementContent>[
        const ImageContent('users/sam/images/1.jpg'),
        _text,
        const StickerContent(itemId: 'basics', file: 'stickers/star.webp'),
      ]) {
        final e = PageElement(
          id: 'e',
          content: content,
          frame: const ElementFrame(
            center: Offset(10, 20),
            width: 30,
            height: 40,
          ),
          z: 1,
          createdAt: 0,
        );
        expect(PageElement.fromMap('e', e.toMap())!.content, content);
      }
      expect(
        PageElement.fromMap('x', {
          'kind': 'hologram',
          'x': 1,
          'y': 1,
          'w': 1,
          'h': 1,
        }),
        isNull,
        reason: 'kinds from newer versions are skipped',
      );
    });

    for (final (name, make) in <(String, NotesBackend Function())>[
      ('in memory', InMemoryNotesBackend.new),
      ('Firestore', () => FirestoreNotesBackend(FakeFirebaseFirestore())),
    ]) {
      test('$name: a text box\'s text can be changed', () async {
        final repo = make().elements('sam');
        final frame = const ElementFrame(
          center: Offset(100, 100),
          width: 300,
          height: 80,
        );
        await repo.addElement(
          'p',
          PageElement(
            id: 'e',
            content: _text,
            frame: frame,
            z: 1,
            createdAt: 0,
          ),
        );
        await repo.setElementContent(
          'p',
          'e',
          _text.copyWith(text: 'Bye'),
          frame.copyWith(height: 120),
        );
        await pumpEventQueue();
        final saved = (await repo.watchElements('p').first).single;
        expect((saved.content as TextContent).text, 'Bye');
        expect(saved.frame.height, 120);
      });
    }
  });

  test('edited text keeps its scale and top-left corner', () {
    final natural = textNaturalSize(_text);
    final frame = ElementFrame(
      center: Offset(200 + natural.width, 300 + natural.height),
      width: natural.width * 2,
      height: natural.height * 2,
    );
    final longer = _text.copyWith(text: 'Hello\nthere\nfriend');
    final next = reframeText(frame, _text, longer);
    expect(next.width, frame.width);
    expect(next.height, greaterThan(frame.height));
    final topLeft = next.center - Offset(next.width / 2, next.height / 2);
    expect(topLeft.dx, closeTo(200, 0.001));
    expect(topLeft.dy, closeTo(300, 0.001));
  });

  group('on a page', () {
    late List<SkinManifest> skins;
    late InMemoryNotesBackend backend;
    late String uid;
    late String pageId;

    setUpAll(() async {
      skins = await loadTestSkins();
    });

    Future<List<PageElement>> elements() async =>
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
      CoverPhotoStore? photos,
    }) async {
      tester.view
        ..physicalSize = const Size(1000, 1000)
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
      final container = await makeContainer(
        skins,
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          notesBackendProvider.overrideWithValue(backend),
          coverPhotoStoreProvider.overrideWithValue(
            photos ?? InMemoryCoverPhotoStore(),
          ),
          photoPickerProvider.overrideWithValue(
            ({maxSize = Size.zero}) async => Uint8List.fromList(_png),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: themed(skinById(skins, 'classic'), PageScreen(pageId: pageId)),
        ),
      );
      await settle(tester);
      return container;
    }

    testWidgets('a text box is typed, placed and selected', (tester) async {
      final container = await pumpPage(tester);
      await tester.tap(find.byTooltip('Text'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'Call Sam');
      await tester.tap(find.text('Large'));
      await tester.tap(find.text('Add'));
      await settle(tester);

      final placed = (await elements()).single;
      final content = placed.content as TextContent;
      expect(content.text, 'Call Sam');
      expect(content.fontSize, textSizes[2]);
      expect(find.byType(TextBoxView), findsOneWidget);
      expect(find.text('Call Sam'), findsOneWidget);
      expect(container.read(inkToolProvider).kind, InkToolKind.select);
    });

    testWidgets('tapping a selected text box edits it; undo restores', (
      tester,
    ) async {
      await pumpPage(tester);
      await tester.tap(find.byTooltip('Text'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'Draft');
      await tester.tap(find.text('Add'));
      await settle(tester);

      await tester.tap(find.text('Draft'), warnIfMissed: false);
      await settle(tester);
      expect(find.text('Edit text'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Final\nversion');
      await tester.tap(find.text('Done'));
      await settle(tester);
      final edited = (await elements()).single;
      expect((edited.content as TextContent).text, 'Final\nversion');

      await tester.ensureVisible(find.byTooltip('Undo'));
      await tester.tap(find.byTooltip('Undo'));
      await settle(tester);
      expect(((await elements()).single.content as TextContent).text, 'Draft');
    });

    testWidgets('emptying a text box removes it', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byTooltip('Text'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'Oops');
      await tester.tap(find.text('Add'));
      await settle(tester);
      await tester.tap(find.text('Oops'), warnIfMissed: false);
      await settle(tester);
      await tester.enterText(find.byType(TextField), '  ');
      await tester.tap(find.text('Done'));
      await settle(tester);
      expect(await elements(), isEmpty);
    });

    testWidgets('a photo is saved to the account and placed', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byTooltip('Photo'));
      await settle(tester);

      final placed = (await elements()).single;
      expect(placed.content, ImageContent('users/$uid/images/0.jpg'));
      expect(placed.frame.width / placed.frame.height, closeTo(2, 0.01));
      expect(find.byType(PageImageView), findsOneWidget);
    });

    testWidgets('a photo that can\'t be saved says so', (tester) async {
      await pumpPage(tester, photos: _OfflinePhotos());
      await tester.tap(find.byTooltip('Photo'));
      await settle(tester);
      expect(await elements(), isEmpty);
      expect(find.textContaining('Couldn\'t add the photo'), findsOneWidget);
    });
  });
}
