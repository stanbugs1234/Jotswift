import 'dart:io';
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
import 'package:notely/app/router.dart';
import 'package:notely/core/paper/paper_style.dart';
import 'package:notely/core/pdf/pdf_renderer.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/core/skins/widgets/paper.dart';
import 'package:notely/features/auth/auth_repository.dart';
import 'package:notely/core/motion/page_turn.dart';
import 'package:notely/features/canvas/page_canvas.dart';
import 'package:notely/features/canvas/templates.dart';
import 'package:notely/features/notebooks/data/firestore_notes_backend.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/data/notes_repository.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';
import 'package:notely/features/notebooks/notes_providers.dart';
import 'package:notely/features/notebooks/page_order.dart';

import '../../core/catalog/catalog_test.dart' show FakeDownloader, zip;
import '../../helpers.dart';

/// A PDF of [pageCount] Letter pages. Page 1 links its top-left quarter to
/// page 2, and a tab on its right edge to page 3.
class FakePdfFile implements PdfFile {
  FakePdfFile(this.pageCount, {this.landscape = false});

  @override
  final int pageCount;

  /// Landscape Letter pages, like the spread planners.
  final bool landscape;

  @override
  ui.Size pageSize(int page) =>
      landscape ? const ui.Size(792, 612) : const ui.Size(612, 792);

  @override
  Future<List<PdfPageLink>> links(int page) async => page == 1
      ? const [
          PdfPageLink(ui.Rect.fromLTRB(0, 0, 0.5, 0.5), 2),
          PdfPageLink(ui.Rect.fromLTRB(0.95, 0.6, 1.01, 0.7), 3),
        ]
      : const [];

  @override
  Future<ui.Image> render(int page, {required int width}) {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 26, 26),
      Paint()..color = const Color(0xFF2C4A7C),
    );
    return landscape
        ? recorder.endRecording().toImage(26, 20)
        : recorder.endRecording().toImage(20, 26);
  }

  @override
  Future<void> dispose() async {}
}

class FakePdfRenderer implements PdfRenderer {
  FakePdfRenderer({this.landscape = false});

  final opened = <String>[];
  final bool landscape;

  @override
  Future<PdfFile> open(Uint8List bytes, {required String name}) async {
    opened.add(name);
    return FakePdfFile(3, landscape: landscape);
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
  Map<String, Object> extraJson = const {},
  bool free = true,
  String? name,
  String? category,
  List<String> tags = const [],
}) {
  final pack = zip({
    'template.pdf': utf8.encode('%PDF-$version'),
    'template.json': utf8.encode(jsonEncode(spec)),
    for (final f in extraPdfs) f: utf8.encode('%PDF-$version-$f'),
    for (final MapEntry(:key, :value) in extraJson.entries)
      key: utf8.encode(jsonEncode(value)),
  });
  final path = 'catalog/$id/$version/pack.zip';
  downloader.files[path] = pack;
  return CatalogItem.fromMap(id, {
    'kind': 'template',
    'name': name ?? (id == 'planner' ? '2027 Weekly Planner' : 'Essentials'),
    'version': version,
    'visibility': 'public',
    'unlock': free ? {'free': true} : {'pro': true},
    'templateMode': spec['mode'],
    'category': ?category,
    'tags': tags,
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

/// A planner with a builder: layout and week start pick its PDF, and the
/// daily check-ins can be left out.
const builderJson = {
  'mode': 'notebook',
  'sections': [
    {
      'title': 'Start',
      'pages': [
        {'pdfPage': 1, 'title': 'Home'},
      ],
    },
    {
      'title': 'January',
      'pages': [
        {'pdfPage': 2, 'title': 'January'},
        {'pdfPage': 3, 'title': 'Jan 1 check-in', 'group': 'checkin'},
      ],
    },
  ],
  'options': [
    {
      'id': 'layout',
      'title': 'Layout',
      'choices': [
        {'id': 'landscape', 'name': 'Landscape'},
        {'id': 'portrait', 'name': 'Portrait'},
      ],
    },
    {
      'id': 'weekStart',
      'title': 'Week starts',
      'choices': [
        {'id': 'monday', 'name': 'Monday'},
        {'id': 'sunday', 'name': 'Sunday'},
      ],
    },
  ],
  'groups': [
    {'id': 'checkin', 'title': 'Daily check-ins', 'optional': true, 'on': true},
    {'id': 'extras', 'title': 'Extras', 'optional': true, 'on': false},
  ],
  'variants': [
    {
      'name': 'Landscape · Monday',
      'file': 'template.pdf',
      'options': {'layout': 'landscape', 'weekStart': 'monday'},
    },
    {
      'name': 'Landscape · Sunday',
      'file': 'template_sunday.pdf',
      'options': {'layout': 'landscape', 'weekStart': 'sunday'},
    },
    {
      'name': 'Portrait · Monday',
      'file': 'template_portrait.pdf',
      'options': {'layout': 'portrait', 'weekStart': 'monday'},
    },
    {
      'name': 'Portrait · Sunday',
      'file': 'template_portrait_sunday.pdf',
      'spec': 'template_portrait_sunday.json',
      'options': {'layout': 'portrait', 'weekStart': 'sunday'},
    },
  ],
};

/// The Portrait · Sunday variant's own page list.
const portraitSundayJson = {
  'sections': [
    {
      'title': 'Start',
      'pages': [
        {'pdfPage': 1, 'title': 'Home'},
      ],
    },
    {
      'title': 'January (Sun)',
      'pages': [
        {'pdfPage': 2, 'title': 'January'},
        {'pdfPage': 3, 'title': 'Jan 1 check-in', 'group': 'checkin'},
      ],
    },
  ],
};

void main() {
  test("a planner builder's options, groups and variants are read", () {
    final spec = TemplateSpec.fromJson(
      Uint8List.fromList(utf8.encode(jsonEncode(builderJson))),
    );
    expect(spec.options.map((o) => o.id), ['layout', 'weekStart']);
    expect(spec.options.first.choices.map((c) => c.name), [
      'Landscape',
      'Portrait',
    ]);
    expect(spec.variantFor({})!.file, 'template.pdf');
    expect(
      spec.variantFor({'layout': 'portrait', 'weekStart': 'sunday'})!.spec,
      'template_portrait_sunday.json',
    );
    expect(
      spec.variantFor({'weekStart': 'sunday'})!.file,
      'template_sunday.pdf',
    );
    expect(spec.pages.last.group, 'checkin');
    expect(spec.defaultSkipped, {'extras'});
    expect(spec.pageCount(), 3);
    expect(spec.pageCount(skip: {'checkin'}), 2);
    final sunday = spec.withSectionsFrom(
      Uint8List.fromList(utf8.encode(jsonEncode(portraitSundayJson))),
    );
    expect(sunday.sections.last.title, 'January (Sun)');
    expect(sunday.options, spec.options);

    // Older planners have none of this.
    final plain = TemplateSpec.fromJson(
      Uint8List.fromList(utf8.encode(jsonEncode(plannerJson))),
    );
    expect(plain.options, isEmpty);
    expect(plain.groups, isEmpty);
    expect(plain.variantFor({}), isNull);
    expect(plain.pages.first.group, isNull);
  });

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

  test('the Preconstruction Project has its 12 sections, in order', () {
    final spec = TemplateSpec.fromJson(
      File('catalog/precon_project/template.json').readAsBytesSync(),
    );
    expect(spec.mode, TemplateMode.notebook);
    expect(spec.sections.map((s) => s.title), [
      '00 - Dashboard', '01 - Scope', '02 - Key Dates', //
      '03 - Strategy Meeting', '04 - Site Visit', "05 - RFI's",
      '06 - Takeoff', '07 - Quotes', '08 - Risks', '09 - Bid Review',
      '10 - Bid Day', '11 - Post Bid',
    ]);
    expect(spec.sections.first.pages.single.pdfPage, 1);
    expect(spec.variants, hasLength(3));
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
      Map<String, Object> prefs = const {},
      bool turnable = false,
      List<int> madePages = const [1, 2, 3],
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
        for (final n in madePages)
          (title: 'Page $n', paper: null, template: templatePage(made, n)),
      ]);
      final pages = {
        for (final p in await repo.watchPages(nb.id, section.id).first)
          p.template!.pdfPage: p.id,
      };
      final container = await makeContainer(
        skins,
        prefs: prefs,
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          ...overrides(published ?? [made]),
        ],
      );
      final canvas = PageCanvas(pageId: pages[1]!, onOpenPage: onOpenPage);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: themed(
            skinById(skins, 'classic'),
            turnable
                // As in a notebook: the screen's edges turn the page.
                ? PageTurnSwitcher(
                    pageKey: pages[1]!,
                    order: [pages[1]!, pages[2]!, pages[3]!],
                    pageBuilder: (id) => PageCanvas(pageId: id as String),
                    onTurned: (_) {},
                    child: canvas,
                  )
                : canvas,
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

    testWidgets('a finger tap on a link at the screen edge opens it', (
      tester,
    ) async {
      String? opened;
      final (_, _, pages) = await pumpPlannerPage(
        tester,
        made: template(downloader, 'planner', plannerJson),
        onOpenPage: (id) => opened = id,
        prefs: {'fingerDrawing': 'off'},
        turnable: true,
      );

      // The tab's link runs to the page's right edge, in the strip that
      // turns pages when dragged.
      final link = tester.getRect(find.byType(RawImage));
      final y = link.top + link.height * 0.65;
      for (final x in [
        link.right - 4,
        link.right - 14,
        link.left + link.width * 0.96,
      ]) {
        opened = null;
        await tester.tapAt(Offset(x, y));
        await settle(tester);
        expect(opened, pages[3], reason: 'tap at x = $x');
      }
    });

    testWidgets('on an iPad, a finger tap on a side tab opens its page', (
      tester,
    ) async {
      renderer = FakePdfRenderer(landscape: true);
      final made = template(downloader, 'planner', plannerJson);
      final auth = await pumpApp(
        tester,
        skins,
        size: const Size(1180, 820),
        prefs: {'fingerDrawing': 'off'},
        overrides: overrides([made]),
      );
      final repo = backend.notebooks(auth.currentUser!.uid);
      final nb = await repo.createNotebook(
        const NewNotebook(
          title: 'Precon',
          cover: NotebookCover.color(1),
          orientation: PaperOrientation.landscape,
        ),
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
      final router = ProviderScope.containerOf(
        tester.element(find.byType(Navigator).first),
      ).read(routerProvider);
      router.go('/notebooks/${nb.id}/pages/${pages[1]}');
      await settle(tester);

      final link = tester.getRect(find.byType(RawImage));
      await tester.tapAt(
        Offset(link.left + link.width * 0.975, link.top + link.height * 0.65),
      );
      await settle(tester);
      expect(router.state.uri.path, endsWith(pages[3]!));
    });

    testWidgets('a link waits for its page when the list is still loading', (
      tester,
    ) async {
      String? opened;
      final (_, _, pages) = await pumpPlannerPage(
        tester,
        made: template(downloader, 'planner', plannerJson),
        onOpenPage: (id) => opened = id,
        prefs: {'fingerDrawing': 'off'},
      );
      // As if the device's cache didn't have page 3 yet.
      final repo = backend.notebooks(uid);
      final page3 = (await repo.watchPage(pages[3]!).first)!;
      await repo.deletePage(page3.id);
      await settle(tester);

      final link = tester.getRect(find.byType(RawImage));
      await tester.tapAt(
        Offset(link.left + link.width * 0.97, link.top + link.height * 0.65),
      );
      await settle(tester);
      expect(opened, isNull);

      // The full list arrives with it.
      await repo.createPages(page3.notebookId, page3.sectionId, [
        (title: 'Page 3', paper: null, template: page3.template),
      ]);
      await settle(tester);
      final arrived = (await repo.watchNotebookPages(page3.notebookId).first)
          .firstWhere((p) => p.template?.pdfPage == 3);
      expect(opened, arrived.id);
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

    testWidgets('a planner can be looked inside before choosing it', (
      tester,
    ) async {
      final planner = template(downloader, 'planner', plannerJson);
      final auth = await pumpApp(
        tester,
        skins,
        size: const Size(900, 1600),
        overrides: overrides([planner]),
      );
      uid = auth.currentUser!.uid;

      await tester.tap(find.text('New notebook').last);
      await settle(tester);
      await tester.tap(find.text('Look inside'));
      await settle(tester);
      expect(find.text('Months · 2 pages'), findsOneWidget);
      expect(find.text('February'), findsOneWidget);
      await tester.tap(find.text('Use this'));
      await settle(tester);
      await tester.tap(find.text('Create'));
      await settle(tester);

      final repo = backend.notebooks(uid);
      final nb = (await repo.watchNotebooks().first).single;
      expect(nb.title, '2027 Weekly Planner');
    });

    testWidgets('New notebook planners can be searched by name and tag', (
      tester,
    ) async {
      final auth = await pumpApp(
        tester,
        skins,
        size: const Size(900, 1600),
        overrides: overrides([
          for (final (id, name, category) in [
            ('p1', 'Kawaii Planner', 'planners'),
            ('p2', 'Ocean Planner', 'planners'),
            ('p3', 'Classic Diary', 'diaries'),
            ('p4', 'Modern Diary', 'diaries'),
            ('p5', 'Budget Planner', 'lifestyle'),
          ])
            template(
              downloader,
              id,
              plannerJson,
              name: name,
              category: category,
              tags: [if (id == 'p5') 'money'],
            ),
        ]),
      );
      uid = auth.currentUser!.uid;

      await tester.tap(find.text('New notebook').last);
      await settle(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Diaries'));
      await settle(tester);
      expect(find.text('Classic Diary'), findsOneWidget);
      expect(find.text('Modern Diary'), findsOneWidget);
      expect(find.text('Kawaii Planner'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Search templates'),
        'money',
      );
      await settle(tester);
      expect(find.text('Budget Planner'), findsOneWidget);
      expect(find.text('Ocean Planner'), findsNothing);

      await tester.tap(find.text('Budget Planner'));
      await settle(tester);
      await tester.tap(find.text('Create'));
      await settle(tester);
      final nb = (await backend.notebooks(uid).watchNotebooks().first).single;
      expect(nb.title, 'Budget Planner');
    });

    testWidgets('the planner builder picks a layout and leaves pages out', (
      tester,
    ) async {
      final planner = template(
        downloader,
        'focus',
        builderJson,
        name: 'Focus Planner',
        extraPdfs: [
          'template_sunday.pdf',
          'template_portrait.pdf',
          'template_portrait_sunday.pdf',
        ],
        extraJson: {'template_portrait_sunday.json': portraitSundayJson},
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
      await tester.tap(find.text('Focus Planner'));
      await settle(tester);
      expect(find.text('Colours'), findsNothing);
      expect(find.text('Daily check-ins'), findsOneWidget);
      // Off by default, with no pages: not offered.
      expect(find.text('Extras'), findsNothing);
      expect(find.textContaining('3 pages, with links'), findsOneWidget);

      await tester.tap(find.text('Portrait'));
      await tester.pump();
      await tester.tap(find.text('Sunday'));
      await settle(tester);
      await tester.tap(find.text('Daily check-ins'));
      await settle(tester);
      expect(find.textContaining('2 pages, with links'), findsOneWidget);
      await tester.tap(find.text('Create'));
      await settle(tester);

      final repo = backend.notebooks(uid);
      final nb = (await repo.watchNotebooks().first).single;
      final sections = await repo.watchSections(nb.id).first;
      expect(sections.map((s) => s.title), ['Start', 'January (Sun)']);
      final pages = await repo.watchNotebookPages(nb.id).first;
      expect(pages.map((p) => p.title), unorderedEquals(['Home', 'January']));
      expect(pages.map((p) => p.template!.file).toSet(), {
        'template_portrait_sunday.pdf',
      });
    });

    testWidgets('a link to a page left out offers to add it', (tester) async {
      String? opened;
      final (container, first, _) = await pumpPlannerPage(
        tester,
        made: template(downloader, 'planner', plannerJson),
        onOpenPage: (id) => opened = id,
        madePages: [1, 3],
      );

      final canvas = tester.getRect(find.byType(PageCanvas));
      await tester.tapAt(canvas.topLeft + const Offset(150, 150));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 1300));
      await settle(tester);
      expect(find.text("January isn't in this notebook."), findsOneWidget);

      await tester.tap(find.text('Add it'));
      await settle(tester);
      final repo = backend.notebooks(uid);
      final notebookId = container.read(pageProvider(first)).value!.notebookId;
      final all = await repo.watchNotebookPages(notebookId).first;
      final added = all.singleWhere((p) => p.template!.pdfPage == 2);
      expect(added.title, 'January');
      expect(opened, added.id);
      // In the planner's order: after page 1, before page 3.
      final sections = await repo.watchSections(notebookId).first;
      expect(sortPages(sections, all).map((p) => p.template!.pdfPage), [
        1,
        2,
        3,
      ]);
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

    Future<String> pumpNewPageSheet(
      WidgetTester tester,
      List<CatalogItem> items,
    ) async {
      final auth = await pumpApp(
        tester,
        skins,
        size: const Size(900, 1600),
        overrides: overrides(items),
      );
      uid = auth.currentUser!.uid;
      await tester.tap(find.text('New notebook').last);
      await settle(tester);
      await tester.tap(find.text('Blank pages'));
      await settle(tester);
      await tester.tap(find.text('Create'));
      await settle(tester);
      await tester.tap(find.text('New page'));
      await settle(tester);
      final repo = backend.notebooks(uid);
      return (await repo.watchNotebooks().first).single.id;
    }

    testWidgets('New page offers a blank page and every template', (
      tester,
    ) async {
      final notebookId = await pumpNewPageSheet(tester, [
        template(downloader, 'essentials', pagesJson),
        template(downloader, 'planner', plannerJson),
        template(
          downloader,
          'fancy',
          pagesJson,
          free: false,
          name: 'Fancy pages',
        ),
      ]);

      expect(find.bySemanticsLabel('Blank page'), findsOneWidget);
      expect(find.bySemanticsLabel('Meeting notes template'), findsOneWidget);
      expect(find.text('2027 Weekly Planner'), findsOneWidget);
      expect(find.text('More in the store'), findsOneWidget);
      expect(find.text('Fancy pages'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Blank page'));
      await settle(tester);
      final pages = await backend
          .notebooks(uid)
          .watchNotebookPages(notebookId)
          .first;
      expect(pages.single.template, isNull);
    });

    testWidgets('New page templates can be searched and filtered', (
      tester,
    ) async {
      await pumpNewPageSheet(tester, [
        template(downloader, 'essentials', pagesJson, category: 'pages'),
        template(
          downloader,
          'planner',
          plannerJson,
          category: 'planners',
          tags: ['weekly', '2027'],
        ),
      ]);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Planners'));
      await settle(tester);
      expect(find.text('2027 Weekly Planner'), findsOneWidget);
      expect(find.text('Essentials'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.enterText(find.byType(TextField), 'essen');
      await settle(tester);
      expect(find.text('Essentials'), findsOneWidget);
      expect(find.text('2027 Weekly Planner'), findsNothing);
      expect(find.bySemanticsLabel('Blank page'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'nothing like it');
      await settle(tester);
      expect(find.text('No templates match.'), findsOneWidget);
    });

    testWidgets('a planner section opens to pick any of its pages', (
      tester,
    ) async {
      final notebookId = await pumpNewPageSheet(tester, [
        template(downloader, 'planner', plannerJson),
      ]);

      await tester.tap(
        find.bySemanticsLabel('Months pages of 2027 Weekly Planner'),
      );
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('February template'));
      await settle(tester);

      final page =
          (await backend.notebooks(uid).watchNotebookPages(notebookId).first)
              .single;
      expect(page.title, 'February');
      expect(page.template!.itemId, 'planner');
      expect(page.template!.pdfPage, 3);
    });
  });
}
