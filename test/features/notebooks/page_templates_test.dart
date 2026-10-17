import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/app/router.dart';
import 'package:notely/core/catalog/catalog_providers.dart';
import 'package:notely/core/catalog/pack_cache.dart';
import 'package:notely/core/catalog/pack_disk_memory.dart';
import 'package:notely/core/paper/paper_style.dart';
import 'package:notely/core/pdf/pdf_renderer.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/imports/document_import.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';
import 'package:notely/features/notebooks/my_templates.dart';
import 'package:notely/features/notebooks/notes_providers.dart';

import '../../core/catalog/catalog_test.dart' show FakeDownloader;
import '../../helpers.dart';
import '../canvas/templates_test.dart' show FakePdfRenderer;
import '../imports/document_import_test.dart' show pdfBytes;

void main() {
  late List<SkinManifest> skins;
  late InMemoryNotesBackend backend;
  late String uid;

  setUpAll(() async => skins = await loadTestSkins());
  setUp(() => backend = InMemoryNotesBackend());

  const grid = PaperStyle(
    color: Color(0xFFFFFFFF),
    lineColor: Color(0xFFB0C4DE),
    pattern: PaperPattern.grid,
    spacing: 24,
  );

  List<Override> overrides() => [
    notesBackendProvider.overrideWithValue(backend),
    documentStoreProvider.overrideWithValue(InMemoryDocumentStore()),
    packCacheProvider.overrideWithValue(
      PackCache(FakeDownloader(), MemoryPackDisk()),
    ),
    pdfRendererProvider.overrideWithValue(FakePdfRenderer()),
    importFilesPickerProvider.overrideWithValue(
      () async => [ImportFile('Bought planner.pdf', pdfBytes)],
    ),
  ];

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }
  }

  void go(WidgetTester tester, String path) =>
      ProviderScope.containerOf(tester.element(find.byType(Navigator).first))
          .read(routerProvider)
          .go(path);

  /// Notebook Bio with pages One and Two on grid paper, open on One.
  Future<(String, List<String>)> pumpNotebook(WidgetTester tester) async {
    final auth = await pumpApp(
      tester,
      skins,
      size: const Size(1000, 1000),
      overrides: overrides(),
    );
    uid = auth.currentUser!.uid;
    final repo = backend.notebooks(uid);
    final nb = await repo.createNotebook(
      const NewNotebook(title: 'Bio', cover: NotebookCover.color(1)),
    );
    final section = (await repo.watchSections(nb.id).first).single;
    final ids = [
      for (final t in ['One', 'Two'])
        (await repo.createPage(nb.id, section.id, title: t, paper: grid)).id,
    ];
    go(tester, '/notebooks/${nb.id}/pages/${ids[0]}');
    await settle(tester);
    return (nb.id, ids);
  }

  Future<void> saveOpenPage(WidgetTester tester, String name) async {
    await tester.tap(find.byTooltip('Page options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save page as template…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, name);
    await tester.tap(find.text('Save'));
    await settle(tester);
  }

  testWidgets('a page saved as a template can be added after another', (
    tester,
  ) async {
    final (notebookId, ids) = await pumpNotebook(tester);
    await saveOpenPage(tester, 'Lab report');
    expect(find.textContaining('Saved "Lab report"'), findsOneWidget);

    final repo = backend.notebooks(uid);
    // Kept off the shelf and out of the notebook templates.
    expect(
      (await repo.watchNotebooks().first).where((n) => n.pageTemplates),
      hasLength(1),
    );

    await tester.tap(find.byTooltip('Add page after this'));
    await settle(tester);
    expect(find.text('My pages'), findsOneWidget);
    await tester.tap(find.text('Lab report'));
    await settle(tester);

    final pages = (await repo.watchNotebookPages(notebookId).first).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    expect(pages.map((p) => p.title), ['One', 'Lab report', 'Two']);
    expect(pages[1].paper, grid);
    expect(pages[1].id, isNot(anyOf(ids)));
  });

  testWidgets('saved pages are listed in My templates, apart from notebooks', (
    tester,
  ) async {
    await pumpNotebook(tester);
    await saveOpenPage(tester, 'Lab report');
    go(tester, myTemplatesPath);
    await settle(tester);
    expect(find.text('Pages'), findsOneWidget);
    expect(find.text('Lab report'), findsOneWidget);
    expect(find.text('Notebooks'), findsNothing);
    expect(find.text('My pages'), findsNothing, reason: 'its holder is hidden');
  });

  testWidgets('a PDF can be imported as a template', (tester) async {
    final auth = await pumpApp(
      tester,
      skins,
      size: const Size(1000, 1000),
      overrides: overrides(),
    );
    go(tester, myTemplatesPath);
    await settle(tester);
    await tester.tap(find.text('Import PDF or images'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('From Files'));
    await settle(tester);

    final repo = backend.notebooks(auth.currentUser!.uid);
    final made = (await repo.watchNotebooks().first).single;
    expect(made.title, 'Bought planner');
    expect(made.isTemplate, isTrue);
    expect(await repo.watchNotebookPages(made.id).first, hasLength(3));
    expect(find.text('Bought planner'), findsOneWidget);
    expect(find.text('Notebooks'), findsOneWidget);
  });

  testWidgets("a plain page keeps its notebook's paper as a template", (
    tester,
  ) async {
    final auth = await pumpApp(
      tester,
      skins,
      size: const Size(1000, 1000),
      overrides: overrides(),
    );
    uid = auth.currentUser!.uid;
    final repo = backend.notebooks(uid);
    final nb = await repo.createNotebook(
      const NewNotebook(
        title: 'Grid book',
        cover: NotebookCover.color(1),
        paper: grid,
      ),
    );
    final section = (await repo.watchSections(nb.id).first).single;
    final page = await repo.createPage(nb.id, section.id, title: 'Plain');
    go(tester, '/notebooks/${nb.id}/pages/${page.id}');
    await settle(tester);
    await saveOpenPage(tester, 'Plain grid');

    final holder = (await repo.watchNotebooks().first).singleWhere(
      (n) => n.pageTemplates,
    );
    final saved = (await repo.watchNotebookPages(holder.id).first).single;
    expect(saved.title, 'Plain grid');
    expect(saved.paper, grid);
  });
}
