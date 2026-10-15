import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/paper/basic_papers.dart';
import 'package:notely/core/paper/paper_style.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/notebooks/data/cover_photos.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';
import 'package:notely/features/notebooks/notes_providers.dart';
import 'package:notely/features/shelf/cover_designs.dart';
import 'package:notely/features/shelf/cover_view.dart';

import '../../helpers.dart';

/// A 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAj'
  'CB0C8AAAAASUVORK5CYII=',
);

class _FailingPhotoStore implements CoverPhotoStore {
  @override
  Future<String> upload(String uid, Uint8List jpeg) =>
      Future.error(Exception('offline'));

  @override
  Future<ImageProvider> image(String path) => Future.error(Exception('none'));
}

void main() {
  late List<SkinManifest> skins;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    skins = await loadTestSkins();
  });

  // Tall enough that the whole editor fits without scrolling.
  const size = Size(900, 2600);

  late InMemoryNotesBackend backend;
  late String uid;

  Future<void> pump(
    WidgetTester tester, {
    CoverPhotoStore? photos,
    Uint8List? photo,
  }) async {
    backend = InMemoryNotesBackend();
    final auth = await pumpApp(
      tester,
      skins,
      size: size,
      overrides: [
        notesBackendProvider.overrideWithValue(backend),
        coverPhotoStoreProvider.overrideWithValue(
          photos ?? InMemoryCoverPhotoStore(),
        ),
        photoPickerProvider.overrideWithValue(() async => photo),
      ],
    );
    uid = auth.currentUser!.uid;
  }

  Future<Notebook> onlyNotebook() async =>
      (await backend.notebooks(uid).watchNotebooks().first).single;

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  Future<void> tapLabel(WidgetTester tester, String label) async {
    await tester.tap(find.bySemanticsLabel(label).last);
    await tester.pumpAndSettle();
  }

  /// Creates a notebook with the editor's defaults and opens it.
  Future<void> createDefault(WidgetTester tester, String title) async {
    await tapText(tester, 'New notebook');
    await tester.enterText(find.byType(TextField), title);
    await tapText(tester, 'Create');
  }

  testWidgets('a new notebook gets the chosen cover, paper, size and style', (
    tester,
  ) async {
    await pump(tester);

    await tapText(tester, 'New notebook');
    await tester.enterText(find.byType(TextField), 'Trip');
    await tapText(tester, 'Designs');
    await tapLabel(tester, 'Dots design');
    await tapText(tester, 'Kraft Paper');
    await tapText(tester, 'Cream');
    await tapLabel(tester, 'Grid paper');
    await tapText(tester, 'Wide');
    await tapText(tester, 'A5');
    await tapText(tester, 'Landscape');
    await tapText(tester, 'Create');

    final nb = await onlyNotebook();
    expect(nb.title, 'Trip');
    expect(nb.cover.kind, CoverKind.art);
    expect(nb.cover.coverId, CoverDesign.dots.id);
    expect(nb.collectionId, 'kraft');
    expect(nb.paper!.pattern, PaperPattern.grid);
    expect(nb.paper!.color, BasicPaperColor.cream.color);
    expect(nb.paper!.spacing, greaterThan(defaultSpacing(PaperPattern.grid)));
    expect(nb.paperSize, PaperSize.a5);
    expect(nb.orientation, PaperOrientation.landscape);
    // The new notebook opens.
    expect(find.widgetWithText(AppBar, 'Trip'), findsOneWidget);
  });

  testWidgets("picking a style uses its paper unless paper was chosen", (
    tester,
  ) async {
    await pump(tester);

    await tapText(tester, 'New notebook');
    await tapText(tester, 'Pastel');
    await tapText(tester, 'Create');

    final pastel = skinById(skins, 'pastel');
    expect((await onlyNotebook()).paper, pastel.paper.style);
  });

  testWidgets('a photo can be used as a cover', (tester) async {
    await pump(tester, photo: _png);

    await tapText(tester, 'New notebook');
    await tapText(tester, 'Photo');
    await tapText(tester, 'Choose a photo');
    expect(find.text('Choose another photo'), findsOneWidget);
    await tapText(tester, 'Create');

    final cover = (await onlyNotebook()).cover;
    expect(cover.kind, CoverKind.photo);
    expect(cover.photoPath, startsWith('users/$uid/covers/'));

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(CoverView), matching: find.byType(Image)),
      findsOneWidget,
    );
  });

  testWidgets('a photo that cannot be saved explains why', (tester) async {
    await pump(tester, photo: _png, photos: _FailingPhotoStore());

    await tapText(tester, 'New notebook');
    await tapText(tester, 'Photo');
    await tapText(tester, 'Choose a photo');

    expect(find.textContaining('Could not save the photo'), findsOneWidget);
    expect(find.text('Choose a photo'), findsOneWidget);
  });

  testWidgets('editing a notebook changes its cover and paper, not its size', (
    tester,
  ) async {
    await pump(tester);
    await createDefault(tester, 'Work');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Notebook options'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Cover, paper & style');

    expect(find.text('Edit notebook'), findsOneWidget);
    expect(find.text('Page size'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Cover color').at(3));
    await tester.pumpAndSettle();
    await tapText(tester, 'Dark');
    await tapText(tester, 'Save');

    final nb = await onlyNotebook();
    expect(nb.title, 'Work');
    expect(nb.cover.color, coverColors[3]);
    expect(nb.paper!.color, BasicPaperColor.dark.color);
    expect(nb.paperSize, PaperSize.letter);
  });

  testWidgets('a page can have its own paper and go back to the notebook '
      'paper', (tester) async {
    await pump(tester);
    await createDefault(tester, 'Ideas');
    await tapText(tester, 'New page');

    Future<NotePage> page() async {
      final nb = await onlyNotebook();
      final section =
          (await backend.notebooks(uid).watchSections(nb.id).first).single;
      return (await backend.notebooks(uid).watchPages(nb.id, section.id).first)
          .single;
    }

    await tester.tap(find.byTooltip('Page paper'));
    await tester.pumpAndSettle();
    await tapLabel(tester, 'Dot paper');
    await tapText(tester, 'Use this paper');
    expect((await page()).paper!.pattern, PaperPattern.dot);

    await tester.tap(find.byTooltip('Page paper'));
    await tester.pumpAndSettle();
    await tapText(tester, "Use the notebook's paper");
    expect((await page()).paper, isNull);
  });

  testWidgets('a page can be added with different paper', (tester) async {
    await pump(tester);
    await createDefault(tester, 'Music');

    await tester.tap(find.byTooltip('Notebook options'));
    await tester.pumpAndSettle();
    await tapText(tester, 'New page with different paper');
    await tapLabel(tester, 'Music paper');
    await tapText(tester, 'Add page');

    final nb = await onlyNotebook();
    final section =
        (await backend.notebooks(uid).watchSections(nb.id).first).single;
    final pages = await backend
        .notebooks(uid)
        .watchPages(nb.id, section.id)
        .first;
    expect(pages.single.paper!.pattern, PaperPattern.music);
  });

  testWidgets('papers can be starred as favorites', (tester) async {
    await pump(tester);
    await tapText(tester, 'New notebook');

    await tester.tap(find.byTooltip('Add to favorites'));
    await tester.pumpAndSettle();

    final favorites = await backend
        .favoritePapers(uid)
        .watchFavoritePapers()
        .first;
    expect(favorites, hasLength(1));
    expect(find.byTooltip('Remove from favorites'), findsOneWidget);
    expect(find.bySemanticsLabel('Favorite paper'), findsOneWidget);
  });

  testWidgets('any paper color can be chosen', (tester) async {
    await pump(tester);
    await tapText(tester, 'New notebook');

    await tapText(tester, 'Custom');
    await tester.drag(find.byType(Slider).at(2), const Offset(-60, 0));
    await tester.pumpAndSettle();
    await tapText(tester, 'Use color');
    await tapText(tester, 'Create');

    final paper = (await onlyNotebook()).paper!;
    expect(
      BasicPaperColor.values.map((b) => b.color),
      isNot(contains(paper.color)),
    );
  });
}
