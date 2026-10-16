import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/app/router.dart';
import 'package:notely/core/catalog/catalog_item.dart';
import 'package:notely/core/catalog/catalog_providers.dart';
import 'package:notely/core/catalog/pack_cache.dart';
import 'package:notely/core/catalog/pack_disk_memory.dart';
import 'package:notely/core/paper/paper_style.dart';
import 'package:notely/core/pdf/pdf_renderer.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/imports/document_import.dart';
import 'package:notely/features/imports/open_in.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';
import 'package:notely/features/notebooks/notes_providers.dart';

import '../../core/catalog/catalog_test.dart' show FakeDownloader;
import '../../helpers.dart';
import '../canvas/templates_test.dart' show FakePdfRenderer;

/// A PNG [width] by [height] pixels.
Future<Uint8List> png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF2C4A7C),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

final pdfBytes = Uint8List.fromList(utf8.encode('%PDF-1.7 fake'));

/// A renderer that can't open anything (a damaged or locked PDF).
class BrokenPdfRenderer implements PdfRenderer {
  @override
  Future<PdfFile> open(Uint8List bytes, {required String name}) =>
      Future.error(StateError('password'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('images become a PDF with a page each, shaped like the image', () async {
    final pdf = await imagesToPdf([
      ImportFile('a.png', await png(40, 60)),
      ImportFile('b.png', await png(80, 40)),
    ]);
    final text = latin1.decode(pdf);
    expect(text, startsWith('%PDF'));
    expect(RegExp(r'/Type\s*/Page\b').allMatches(text), hasLength(2));
    // Letter-wide, as tall as the shape needs: 612 x 918, then 612 x 306.
    expect(text, contains('918'));
    expect(text, contains('306'));
  });

  test('a file that is not an image is refused with a reason', () async {
    expect(
      () => imagesToPdf([ImportFile('notes.png', Uint8List(10))]),
      throwsA(
        isA<ImportException>().having(
          (e) => e.message,
          'message',
          contains('notes.png'),
        ),
      ),
    );
  });

  test('a file is a PDF by its name or by its first bytes', () {
    expect(ImportFile('A.PDF', Uint8List(0)).isPdf, isTrue);
    expect(ImportFile('scan', pdfBytes).isPdf, isTrue);
    expect(ImportFile('photo.jpg', Uint8List(8)).isPdf, isFalse);
    expect(ImportFile('Lecture 3.pdf', pdfBytes).title, 'Lecture 3');
  });

  group('DocumentImporter', () {
    late InMemoryDocumentStore store;
    late FakeDownloader downloader;
    late PackCache packs;

    DocumentImporter importer({PdfRenderer? renderer}) => DocumentImporter(
      uid: 'sam',
      store: store,
      packs: packs,
      renderer: renderer ?? FakePdfRenderer(),
    );

    setUp(() {
      store = InMemoryDocumentStore();
      downloader = FakeDownloader();
      packs = PackCache(downloader, MemoryPackDisk());
    });

    test('each PDF is kept on its own; runs of images together', () async {
      final docs = await importer().import([
        ImportFile('Syllabus.pdf', pdfBytes),
        ImportFile('one.png', await png(10, 10)),
        ImportFile('two.png', await png(10, 10)),
        ImportFile('Reading.pdf', pdfBytes),
      ]);

      expect(docs.map((d) => d.title), [
        'Syllabus',
        'Imported images',
        'Reading',
      ]);
      expect(store.documents, hasLength(3));
      final syllabus = docs.first.pages;
      expect(syllabus.map((p) => p.pdfPage), [1, 2, 3]);
      expect(syllabus.every((p) => p.isImported), isTrue);
      expect(syllabus.first.file, PageTemplate.importFile);
      expect(syllabus.first.pack, startsWith('users/sam/documents/'));
      expect(docs.first.firstPageSize, const Size(612, 792));
    });

    test('this device keeps the PDF; others download and check it', () async {
      final doc = (await importer().import([
        ImportFile('Syllabus.pdf', pdfBytes),
      ])).single;
      final page = doc.pages.first;
      final item = CatalogItem(
        id: page.itemId,
        kind: CatalogKind.template,
        name: page.itemId,
        version: page.version,
        unlock: const CatalogUnlock(),
        visibility: CatalogVisibility.retired,
        files: CatalogFiles(
          pack: page.pack,
          sha256: page.sha256,
          bytes: page.bytes,
        ),
      );

      expect((await packs.files(item))[PageTemplate.importFile], pdfBytes);
      expect(downloader.requested, isEmpty);

      downloader.files.addAll(store.documents);
      final elsewhere = PackCache(downloader, MemoryPackDisk());
      expect((await elsewhere.files(item))[PageTemplate.importFile], pdfBytes);
      expect(downloader.requested, [page.pack]);
    });

    test('a PDF that will not open is refused, and nothing is saved', () async {
      await expectLater(
        importer(renderer: BrokenPdfRenderer())
            .import([ImportFile('Locked.pdf', pdfBytes)]),
        throwsA(
          isA<ImportException>().having(
            (e) => e.message,
            'message',
            contains('password'),
          ),
        ),
      );
      expect(store.documents, isEmpty);
    });

    test('imported packs may be larger than catalog packs', () {
      expect(
        PackCache.maxBytesFor('import-abc'),
        greaterThan(PackCache.maxBytesFor('planner')),
      );
    });
  });

  group('in the app', () {
    late List<SkinManifest> skins;
    late InMemoryNotesBackend backend;
    late InMemoryDocumentStore store;
    late List<ImportFile> chosen;

    setUpAll(() async {
      skins = await loadTestSkins();
    });

    setUp(() {
      backend = InMemoryNotesBackend();
      store = InMemoryDocumentStore();
      chosen = [ImportFile('Biology notes.pdf', pdfBytes)];
    });

    List<Override> overrides({PdfRenderer? renderer}) => [
      notesBackendProvider.overrideWithValue(backend),
      documentStoreProvider.overrideWithValue(store),
      packCacheProvider.overrideWithValue(
        PackCache(FakeDownloader(), MemoryPackDisk()),
      ),
      pdfRendererProvider.overrideWithValue(renderer ?? FakePdfRenderer()),
      importFilesPickerProvider.overrideWithValue(() async => chosen),
    ];

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
      }
    }

    testWidgets('Import on Home makes a notebook of the PDF', (tester) async {
      final auth = await pumpApp(
        tester,
        skins,
        size: const Size(900, 1200),
        overrides: overrides(),
      );

      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('From Files'));
      await settle(tester);

      final repo = backend.notebooks(auth.currentUser!.uid);
      final nb = (await repo.watchNotebooks().first).single;
      expect(nb.title, 'Biology notes');
      expect(nb.paperSize, PaperSize.letter);
      expect(nb.orientation, PaperOrientation.portrait);
      final section = (await repo.watchSections(nb.id).first).single;
      final pages = await repo.watchPages(nb.id, section.id).first;
      expect(pages.map((p) => p.title), ['Page 1', 'Page 2', 'Page 3']);
      expect(pages.map((p) => p.template!.pdfPage), [1, 2, 3]);
      expect(pages.first.template!.isImported, isTrue);
      expect(store.documents, hasLength(1));
      // The notebook opened.
      expect(find.text('Biology notes'), findsWidgets);
      expect(find.text('Page 1'), findsOneWidget);
    });

    testWidgets('a damaged PDF says why and makes no notebook', (tester) async {
      final auth = await pumpApp(
        tester,
        skins,
        size: const Size(900, 1200),
        overrides: overrides(renderer: BrokenPdfRenderer()),
      );

      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('From Files'));
      await settle(tester);

      expect(find.textContaining('could not be opened'), findsOneWidget);
      expect(find.text('Importing…'), findsNothing);
      final repo = backend.notebooks(auth.currentUser!.uid);
      expect(await repo.watchNotebooks().first, isEmpty);
    });

    testWidgets('pages can be imported into a notebook', (tester) async {
      final auth = await pumpApp(
        tester,
        skins,
        size: const Size(900, 1200),
        overrides: overrides(),
      );
      final repo = backend.notebooks(auth.currentUser!.uid);
      final nb = await repo.createNotebook(
        const NewNotebook(title: 'Class', cover: NotebookCover.color(1)),
      );
      final section = (await repo.watchSections(nb.id).first).single;
      await repo.createPage(nb.id, section.id, title: 'My notes');
      chosen = [
        ImportFile(
          'handout.png',
          await tester.runAsync(() => png(30, 40)) as Uint8List,
        ),
      ];
      ProviderScope.containerOf(tester.element(find.byType(Navigator).first))
          .read(routerProvider)
          .go('/notebooks/${nb.id}');
      await settle(tester);

      await tester.tap(find.byTooltip('Notebook options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import PDF or images'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('From Files'));
      await settle(tester);

      final pages = await repo.watchPages(nb.id, section.id).first;
      // The fake PDF engine reads every PDF as three pages.
      expect(pages.map((p) => p.title), [
        'My notes',
        'Page 1',
        'Page 2',
        'Page 3',
      ]);
      expect(pages.last.template!.isImported, isTrue);
    });
    testWidgets('a PDF opened in Jotswift from another app is imported', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final auth = await pumpApp(
        tester,
        skins,
        size: const Size(900, 1200),
        overrides: overrides(),
      );

      const codec = StandardMethodCodec();
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'notely/open',
        codec.encodeMethodCall(
          MethodCall('open', [
            {'name': 'Field trip.pdf', 'data': pdfBytes},
          ]),
        ),
        (_) {},
      );
      await settle(tester);

      final repo = backend.notebooks(auth.currentUser!.uid);
      final nb = (await repo.watchNotebooks().first).single;
      expect(nb.title, 'Field trip');
      expect(find.text('Page 1'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    test('files from the platform are read as names and bytes', () {
      expect(incomingFilesFrom(null), isEmpty);
      final files = incomingFilesFrom([
        {'name': 'a.pdf', 'data': pdfBytes},
        {'name': 'broken'},
      ]);
      expect(files.single.name, 'a.pdf');
      expect(files.single.isPdf, isTrue);
    });
  });
}
