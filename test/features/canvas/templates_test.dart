import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/catalog/catalog_item.dart';
import 'package:notely/core/catalog/catalog_providers.dart';
import 'package:notely/core/catalog/catalog_repository.dart';
import 'package:notely/core/catalog/pack_cache.dart';
import 'package:notely/core/catalog/pack_disk_memory.dart';
import 'package:notely/core/catalog/template_spec.dart';
import 'package:notely/core/paper/paper_style.dart';
import 'package:notely/core/pdf/pdf_renderer.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/core/skins/widgets/paper.dart';
import 'package:notely/features/auth/auth_repository.dart';
import 'package:notely/features/canvas/page_canvas.dart';
import 'package:notely/features/canvas/templates.dart';
import 'package:notely/features/notebooks/data/firestore_notes_backend.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/data/notes_repository.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';
import 'package:notely/features/notebooks/notes_providers.dart';

import '../../core/catalog/catalog_test.dart' show FakeDownloader, zip;
import '../../helpers.dart';

/// A PDF of [pageCount] Letter pages. Page 1 links its top-left quarter to
/// page 2.
class FakePdfFile implements PdfFile {
  FakePdfFile(this.pageCount);

  @override
  final int pageCount;

  @override
  ui.Size pageSize(int page) => const ui.Size(612, 792);

  @override
  Future<List<PdfPageLink>> links(int page) async => page == 1
      ? const [PdfPageLink(ui.Rect.fromLTRB(0, 0, 0.5, 0.5), 2)]
      : const [];

  @override
  Future<ui.Image> render(int page, {required int width}) {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 20, 26),
      Paint()..color = const Color(0xFF2C4A7C),
    );
    return recorder.endRecording().toImage(20, 26);
  }
}

class FakePdfRenderer implements PdfRenderer {
  final opened = <String>[];

  @override
  Future<PdfFile> open(Uint8List bytes, {required String name}) async {
    opened.add(name);
    return FakePdfFile(3);
  }
}

const plannerJson = {
  'mode': 'notebook',
  'sections': [
    {
      'title': '2027',
      'pages': [
        {'pdfPage': 1, 'title': '2027'},
      ],
    },
    {
      'title': 'Months',
      'pages': [
        {'pdfPage': 2, 'title': 'January'},
        {'pdfPage': 3, 'title': 'February'},
      ],
    },
  ],
};

const pagesJson = {
  'mode': 'pages',
  'pages': [
    {'pdfPage': 1, 'title': 'To-do list'},
    {'pdfPage': 2, 'title': 'Meeting notes'},
  ],
};

/// Publishes a template to [downloader] and returns its listing.
CatalogItem template(
  FakeDownloader downloader,
  String id,
  Map<String, Object?> spec, {
  int version = 1,
  List<String> extraPdfs = const [],
}) {
  final pack = zip({
    'template.pdf': utf8.encode('%PDF-$version'),
    'template.json': utf8.encode(jsonEncode(spec)),
    for (final f in extraPdfs) f: utf8.encode('%PDF-$version-$f'),
  });
  final path = 'catalog/$id/$version/pack.zip';
  downloader.files[path] = pack;
  return CatalogItem.fromMap(id, {
    'kind': 'template',
    'name': id == 'planner' ? '2027 Weekly Planner' : 'Essentials',
    'version': version,
    'visibility': 'public',
    'unlock': {'free': true},
    'templateMode': spec['mode'],
    'pageCount': 3,
    'files': {
      'pack': path,
      'sha256': sha256.convert(pack).toString(),
      'bytes': pack.length,
    },
  })!;
}

const colourPlannerJson = {
  ...plannerJson,
  'variants': [
    {'name': 'Classic', 'file': 'template.pdf', 'color': '#2C3E66'},
    {'name': 'Pastel', 'file': 'template_pastel.pdf', 'color': '#7E6AAE'},
  ],
};

void main() {
  test('colourways are read from template.json', () {
    final spec = TemplateSpec.fromJson(
      Uint8List.fromList(utf8.encode(jsonEncode(colourPlannerJson))),
    );
    expect(spec.variants.map((v) => v.file), [
      'template.pdf',
      'template_pastel.pdf',
    ]);
    expect(spec.variants.last.color, 0xFF7E6AAE);
    final plain = TemplateSpec.fromJson(
      Uint8List.fromList(utf8.encode(jsonEncode(plannerJson))),
    );
    expect(plain.variants, isEmpty);
  });

  test('a page remembers its colourway; older pages use template.pdf', () {
    const pastel = PageTemplate(
      itemId: 'p',
      version: 1,
      pdfPage: 2,
      pack: 'x',
      sha256: 'y',
      bytes: 3,
      file: 'template_pastel.pdf',
    );
    expect(PageTemplate.fromMap(pastel.toMap()), pastel);
    final old = {...pastel.toMap()}..remove('file');
    expect(PageTemplate.fromMap(old)!.file, 'template.pdf');
    expect(
      const PageTemplate(
        itemId: 'p',
        version: 1,
        pdfPage: 2,
        pack: 'x',
        sha256: 'y',
        bytes: 3,
      ).toMap().containsKey('file'),
      isFalse,
    );
  });

  test('template.json is read for planners and single pages', () {
    final planner = TemplateSpec.fromJson(
      Uint8List.fromList(utf8.encode(jsonEncode(plannerJson))),
    );
    expect(planner.mode, TemplateMode.notebook);
    expect(planner.sections.map((s) => s.title), ['2027', 'Months']);
    expect(planner.pages.map((p) => p.pdfPage), [1, 2, 3]);

    final pages = TemplateSpec.fromJson(
      Uint8List.fromList(utf8.encode(jsonEncode(pagesJson))),
    );
    expect(pages.mode, TemplateMode.pages);
    expect(pages.pages.map((p) => p.title), ['To-do list', 'Meeting notes']);
  });

  test('a PDF page gets the closest page size and orientation', () {
    expect(closestPaperSize(const Size(612, 792)), (
      PaperSize.letter,
      PaperOrientation.portrait,
    ));
    expect(closestPaperSize(const Size(842, 595)), (
      PaperSize.a4,
      PaperOrientation.landscape,
    ));
  });

  final backends = <String, NotesBackend Function()>{
    'in memory': InMemoryNotesBackend.new,
    'Firestore': () => FirestoreNotesBackend(FakeFirebaseFirestore()),
  };
  for (final MapEntry(key: name, value: make) in backends.entries) {
    test('many pages are added in order, with templates ($name)', () async {
      final repo = make().notebooks('sam');
      final nb = await repo.createNotebook(
        const NewNotebook(title: 'P', cover: NotebookCover.color(1)),
      );
      await pumpEventQueue();
      final section = (await repo.watchSections(nb.id).first).single;
      const t = PageTemplate(
        itemId: 'planner',
        version: 1,
        pdfPage: 7,
        pack: 'p',
        sha256: 's',
        bytes: 1,
      );

      await repo.createPages(nb.id, section.id, [
        for (var i = 0; i < 500; i++)
          (title: 'Page $i', paper: null, template: i == 0 ? t : null),
      ]);
      await pumpEventQueue();

      final pages = await repo.watchPages(nb.id, section.id).first;
      expect(pages, hasLength(500));
      expect(pages.first.title, 'Page 0');
      expect(pages.first.template, t);
      expect(pages.last.title, 'Page 499');
      expect(await repo.watchNotebookPages(nb.id).first, hasLength(500));
    });
  }

  group('in the app', () {
    late List<SkinManifest> skins;
    late InMemoryNotesBackend backend;
    late FakeDownloader downloader;
    late FakePdfRenderer renderer;
    late String uid;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      skins = await loadTestSkins();
    });

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
      }
    }

    List<Override> overrides(List<CatalogItem> items) => [
      notesBackendProvider.overrideWithValue(backend),
      catalogRepositoryProvider.overrideWithValue(
        InMemoryCatalogRepository(items),
      ),
      packCacheProvider.overrideWithValue(
        PackCache(downloader, MemoryPackDisk()),
      ),
      pdfRendererProvider.overrideWithValue(renderer),
    ];

    setUp(() {
      backend = InMemoryNotesBackend();
      downloader = FakeDownloader();
      renderer = FakePdfRenderer();
    });

    testWidgets('a notebook can start from a planner', (tester) async {
      final planner = template(downloader, 'planner', plannerJson);
      final auth = await pumpApp(
        tester,
        skins,
        size: const Size(900, 2600),
        overrides: overrides([planner]),
      );
      uid = auth.currentUser!.uid;

      await tester.tap(find.text('New notebook').last);
      await settle(tester);
      await tester.tap(find.text('2027 Weekly Planner'));
      await settle(tester);
      expect(find.text('Page size'), findsNothing);
      await tester.tap(find.text('Create'));
      await settle(tester);

      final repo = backend.notebooks(uid);
      final nb = (await repo.watchNotebooks().first).single;
      expect(nb.title, '2027 Weekly Planner');
      expect(nb.paperSize, PaperSize.letter);
      final sections = await repo.watchSections(nb.id).first;
      expect(sections.map((s) => s.title), ['2027', 'Months']);
      final months = await repo.watchPages(nb.id, sections[1].id).first;
      expect(months.map((p) => p.title), ['January', 'February']);
      expect(months.map((p) => p.template!.pdfPage), [2, 3]);
    });

    testWidgets('a planner can start in another colourway', (tester) async {
      final planner = template(
        downloader,
        'planner',
        colourPlannerJson,
        extraPdfs: ['template_pastel.pdf'],
      );
      final auth = await pumpApp(
        tester,
        skins,
        size: const Size(900, 2600),
        overrides: overrides([planner]),
      );
      uid = auth.currentUser!.uid;

      await tester.tap(find.text('New notebook').last);
      await settle(tester);
      await tester.tap(find.text('2027 Weekly Planner'));
      await settle(tester);
      expect(find.text('Colours'), findsOneWidget);
      // ("Pastel" is also a notebook style; pick the colourway.)
      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('Colours'),
            matching: find.byType(Wrap),
          ),
          matching: find.text('Pastel'),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Create'));
      await settle(tester);

      final repo = backend.notebooks(uid);
      final nb = (await repo.watchNotebooks().first).single;
      final sections = await repo.watchSections(nb.id).first;
      final pages = await repo.watchPages(nb.id, sections[1].id).first;
      expect(pages.map((p) => p.template!.file), [
        'template_pastel.pdf',
        'template_pastel.pdf',
      ]);
      expect(renderer.opened, contains('planner@1/template_pastel.pdf'));
    });

    testWidgets('planners with one look show no colour choice', (tester) async {
      final planner = template(downloader, 'planner', plannerJson);
      await pumpApp(
        tester,
        skins,
        size: const Size(900, 2600),
        overrides: overrides([planner]),
      );
      await tester.tap(find.text('New notebook').last);
      await settle(tester);
      await tester.tap(find.text('2027 Weekly Planner'));
      await settle(tester);
      expect(find.text('Colours'), findsNothing);
    });

    Future<(ProviderContainer, String, Map<int, String>)> pumpPlannerPage(
      WidgetTester tester, {
      required CatalogItem made,
      List<CatalogItem>? published,
      ValueChanged<String>? onOpenPage,
    }) async {
      tester.view
        ..physicalSize = const Size(800, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = DevAuthRepository();
      await auth.signInWithEmail('sam@example.com', 'secret1');
      uid = auth.currentUser!.uid;
      final repo = backend.notebooks(uid);
      final nb = await repo.createNotebook(
        const NewNotebook(title: 'P', cover: NotebookCover.color(1)),
      );
      final section = (await repo.watchSections(nb.id).first).single;
      await repo.createPages(nb.id, section.id, [
        for (var n = 1; n <= 3; n++)
          (title: 'Page $n', paper: null, template: templatePage(made, n)),
      ]);
      final pages = {
        for (final p in await repo.watchPages(nb.id, section.id).first)
          p.template!.pdfPage: p.id,
      };
      final container = await makeContainer(
        skins,
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          ...overrides(published ?? [made]),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: themed(
            skinById(skins, 'classic'),
            PageCanvas(pageId: pages[1]!, onOpenPage: onOpenPage),
          ),
        ),
      );
      await settle(tester);
      return (container, pages[1]!, pages);
    }

    testWidgets('a template page shows its PDF page instead of paper', (
      tester,
    ) async {
      await pumpPlannerPage(
        tester,
        made: template(downloader, 'planner', plannerJson),
      );

      expect(find.byType(RawImage), findsOneWidget);
      expect(
        tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .where((p) => p.painter is PaperPainter),
        isEmpty,
      );
    });

    testWidgets('tapping a link opens the page it points to', (tester) async {
      String? opened;
      final (_, _, pages) = await pumpPlannerPage(
        tester,
        made: template(downloader, 'planner', plannerJson),
        onOpenPage: (id) => opened = id,
      );

      // The link covers the top-left quarter of the PDF page.
      final canvas = tester.getRect(find.byType(PageCanvas));
      await tester.tapAt(canvas.topLeft + const Offset(150, 150));
      await settle(tester);
      expect(opened, pages[2]);

      // A tap outside the link does nothing.
      opened = null;
      await tester.tapAt(canvas.topLeft + const Offset(700, 900));
      await settle(tester);
      expect(opened, isNull);
    });

    testWidgets('a pencil tap on a link writes instead of jumping', (
      tester,
    ) async {
      String? opened;
      final (_, pageId, _) = await pumpPlannerPage(
        tester,
        made: template(downloader, 'planner', plannerJson),
        onOpenPage: (id) => opened = id,
      );

      final canvas = tester.getRect(find.byType(PageCanvas));
      final pencil = await tester.startGesture(
        canvas.topLeft + const Offset(150, 150),
        kind: PointerDeviceKind.stylus,
      );
      await pencil.up();
      await settle(tester);

      expect(opened, isNull);
      expect(
        await backend.strokes(uid).watchStrokes(pageId).first,
        hasLength(1),
      );
    });

    testWidgets('pages keep the template version they were made with', (
      tester,
    ) async {
      final v1 = template(downloader, 'planner', plannerJson);
      final v2 = template(downloader, 'planner', plannerJson, version: 2);

      await pumpPlannerPage(tester, made: v1, published: [v2]);

      expect(downloader.requested, contains('catalog/planner/1/pack.zip'));
      expect(
        downloader.requested,
        isNot(contains('catalog/planner/2/pack.zip')),
      );
      expect(renderer.opened, ['planner@1']);
    });

    testWidgets('a single template page can be added to a notebook', (
      tester,
    ) async {
      final essentials = template(downloader, 'essentials', pagesJson);
      final auth = await pumpApp(
        tester,
        skins,
        size: const Size(900, 1600),
        overrides: overrides([essentials]),
      );
      uid = auth.currentUser!.uid;
      await tester.tap(find.text('New notebook').last);
      await settle(tester);
      await tester.tap(find.text('Create'));
      await settle(tester);

      await tester.tap(find.byTooltip('Notebook options'));
      await settle(tester);
      await tester.tap(find.text('New page from template'));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Meeting notes template'));
      await settle(tester);

      final repo = backend.notebooks(uid);
      final nb = (await repo.watchNotebooks().first).single;
      final page = (await repo.watchNotebookPages(nb.id).first).single;
      expect(page.title, 'Meeting notes');
      expect(page.template!.itemId, 'essentials');
      expect(page.template!.pdfPage, 2);
    });
  });
}
