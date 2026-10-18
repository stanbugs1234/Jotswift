import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/catalog/catalog_item.dart';
import 'package:notely/core/catalog/catalog_providers.dart';
import 'package:notely/core/catalog/catalog_repository.dart';
import 'package:notely/core/catalog/pack_cache.dart';
import 'package:notely/core/catalog/pack_disk_memory.dart';
import 'package:notely/core/entitlements/entitlements.dart';
import 'package:notely/core/pdf/pdf_renderer.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/imports/document_import.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/domain/page_template.dart';
import 'package:notely/features/notebooks/notes_providers.dart';

import '../../core/catalog/catalog_test.dart' show FakeDownloader;
import '../../helpers.dart';
import '../canvas/templates_test.dart' show FakePdfRenderer, template;
import 'planner_editions_test.dart' show datedPlanner;

void main() {
  late List<SkinManifest> skins;
  late InMemoryNotesBackend backend;
  late FakeDownloader downloader;
  late InMemoryDocumentStore documents;

  setUpAll(() async => skins = await loadTestSkins());
  setUp(() {
    backend = InMemoryNotesBackend();
    downloader = FakeDownloader();
    documents = InMemoryDocumentStore();
  });

  Future<void> settle(WidgetTester tester, [int rounds = 3]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }
  }

  List<Override> overrides({bool pro = true}) {
    final now = DateTime.now();
    final List<CatalogItem> items = [
      template(
        downloader,
        'weekly_planner_${now.year}',
        datedPlanner([DateTime(now.year, now.month)]),
        name: '${now.year} Weekly Planner',
      ),
    ];
    return [
      notesBackendProvider.overrideWithValue(backend),
      catalogRepositoryProvider.overrideWithValue(
        InMemoryCatalogRepository(items),
      ),
      packCacheProvider.overrideWithValue(
        PackCache(downloader, MemoryPackDisk()),
      ),
      pdfRendererProvider.overrideWithValue(FakePdfRenderer(landscape: true)),
      documentStoreProvider.overrideWithValue(documents),
      entitlementsProvider.overrideWithValue(Entitlements(pro: pro)),
    ];
  }

  Future<void> openBuilder(WidgetTester tester) async {
    await tester.tap(find.text('New notebook').last);
    await settle(tester);
    await tester.tap(find.text('Build your own'));
    await settle(tester);
    expect(find.text('Build your planner'), findsOneWidget);
  }

  testWidgets('a planner built from kinds of pages becomes a notebook', (
    tester,
  ) async {
    final auth = await pumpApp(
      tester,
      skins,
      size: const Size(1200, 1600),
      overrides: overrides(),
    );
    await openBuilder(tester);

    // No day pages; a reading log section.
    await tester.ensureVisible(find.byTooltip('Remove Day'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove Day'));
    await settle(tester);
    expect(find.byTooltip('Remove Day'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Add a section'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Add a section'));
    await settle(tester);
    await tester.scrollUntilVisible(
      find.text('Reading logs'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Reading logs'));
    await settle(tester);
    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(find.textContaining('Your own planner'), findsOneWidget);

    await tester.tap(find.text('Create'));
    final repo = backend.notebooks(auth.currentUser!.uid);
    // The progress bar moves until the planner is made.
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.textContaining('Setting up').evaluate().isEmpty &&
          (await repo.watchNotebooks().first).isNotEmpty) {
        break;
      }
    }
    await settle(tester);

    final nb = (await repo.watchNotebooks().first).single;
    expect(nb.title, 'My Planner');
    final pages = await repo.watchNotebookPages(nb.id).first;
    expect(pages.length, greaterThan(60));
    expect(
      pages.every(
        (p) => p.template!.itemId.startsWith(PageTemplate.importPrefix),
      ),
      isTrue,
    );
    final titles = {for (final p in pages) p.title};
    expect(titles, containsAll(['Home', 'Week 1', 'Reading log', 'Notes']));
    // No day pages: none is a single day.
    expect(
      pages.where((p) => p.period != null && p.period!.from == p.period!.to),
      isEmpty,
    );
    final sections = await repo.watchSections(nb.id).first;
    expect(
      sections.map((s) => s.title),
      containsAll(['Start', 'Reading logs', 'Notes', 'Lists']),
    );
    expect(documents.documents, hasLength(1));
  });

  testWidgets('a catalog planner can be customised', (tester) async {
    await pumpApp(
      tester,
      skins,
      size: const Size(1200, 1600),
      overrides: overrides(),
    );
    await tester.tap(find.text('New notebook').last);
    await settle(tester);
    await tester.tap(find.text('Weekly Planner'));
    await settle(tester);
    await tester.tap(find.text('Customize: choose every page'));
    await settle(tester);
    expect(find.text('Build your planner'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Weekly Planner',
    );
    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(find.textContaining('Your own planner'), findsOneWidget);
    expect(find.text("Change what's inside"), findsOneWidget);
  });

  testWidgets('making one needs Pro', (tester) async {
    final auth = await pumpApp(
      tester,
      skins,
      size: const Size(1200, 1600),
      overrides: overrides(pro: false),
    );
    await openBuilder(tester);
    await tester.tap(find.text('Done'));
    await settle(tester);
    await tester.tap(find.text('Create'));
    await settle(tester);
    expect(find.textContaining('included in Jotswift Pro'), findsOneWidget);
    expect(
      await backend.notebooks(auth.currentUser!.uid).watchNotebooks().first,
      isEmpty,
    );
  });

  testWidgets("a page's parts can be switched off", (tester) async {
    await pumpApp(
      tester,
      skins,
      size: const Size(1200, 1600),
      overrides: overrides(),
    );
    await openBuilder(tester);
    final tune = find.byTooltip("Choose what's on Day");
    await tester.ensureVisible(tune);
    await tester.pumpAndSettle();
    await tester.tap(tune);
    await settle(tester);
    expect(find.text("What's on Day"), findsOneWidget);
    final schedule = find.widgetWithText(SwitchListTile, 'Schedule');
    expect(tester.widget<SwitchListTile>(schedule).value, isTrue);
    await tester.tap(schedule);
    await settle(tester);
    expect(tester.widget<SwitchListTile>(schedule).value, isFalse);
  });
}
