import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/app/router.dart';
import 'package:notely/core/catalog/catalog_item.dart';
import 'package:notely/core/catalog/catalog_providers.dart';
import 'package:notely/core/catalog/catalog_repository.dart';
import 'package:notely/core/catalog/pack_cache.dart';
import 'package:notely/core/catalog/pack_disk_memory.dart';
import 'package:notely/core/catalog/planner_series.dart';
import 'package:notely/core/pdf/pdf_renderer.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/domain/notebook_cover.dart';
import 'package:notely/features/notebooks/notes_providers.dart';

import '../../core/catalog/catalog_test.dart' show FakeDownloader;
import '../../helpers.dart';
import '../canvas/templates_test.dart' show FakePdfRenderer, template;
import 'catalog_picker_test.dart' show cover;

String _day(DateTime d) =>
    '${d.year}-${'${d.month}'.padLeft(2, '0')}-${'${d.day}'.padLeft(2, '0')}';

const _abbr = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// A dated planner with a month page and a goals page for each of
/// [months], in one section, and a Notes section.
Map<String, Object?> datedPlanner(List<DateTime> months) => {
  'mode': 'notebook',
  'sections': [
    {
      'title': 'Months',
      'pages': [
        for (final (i, m) in months.indexed) ...[
          {
            'pdfPage': 2 * i + 1,
            'title': monthYear(m),
            'from': _day(m),
            'to': _day(DateTime(m.year, m.month + 1, 0)),
          },
          {'pdfPage': 2 * i + 2, 'title': '${monthYear(m)} goals'},
        ],
      ],
    },
    {
      'title': 'Notes',
      'pages': [
        {'pdfPage': 99, 'title': 'Notes'},
      ],
    },
  ],
};

void main() {
  late List<SkinManifest> skins;
  late InMemoryNotesBackend backend;
  late FakeDownloader downloader;

  setUpAll(() async => skins = await loadTestSkins());
  setUp(() {
    backend = InMemoryNotesBackend();
    downloader = FakeDownloader();
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
    pdfRendererProvider.overrideWithValue(FakePdfRenderer()),
  ];

  // An edition running from last month to next month (so it's the one to
  // start today), and next year's.
  final now = DateTime.now();
  final thisMonth = DateTime(now.year, now.month);
  final months = [
    DateTime(now.year, now.month - 1),
    thisMonth,
    DateTime(now.year, now.month + 1),
  ];
  final range =
      '${_abbr[months.first.month - 1]} ${months.first.year} - '
      '${_abbr[months.last.month - 1]} ${months.last.year}';
  final nextYear = now.year + 1;

  List<CatalogItem> editions({bool nextFree = true}) => [
    template(
      downloader,
      'weekly_${nextYear}_01',
      datedPlanner(months),
      name: 'Weekly Planner $range',
    ),
    template(
      downloader,
      'weekly_$nextYear',
      datedPlanner([DateTime(nextYear), DateTime(nextYear, 2)]),
      name: '$nextYear Weekly Planner',
      free: nextFree,
    ),
  ];

  testWidgets('a planner shows once, and starts on this month', (tester) async {
    final auth = await pumpApp(
      tester,
      skins,
      size: const Size(900, 2600),
      overrides: overrides(editions()),
    );
    await tester.tap(find.text('New notebook').last);
    await settle(tester);
    expect(find.text('Weekly Planner'), findsOneWidget);
    expect(find.text('Pick your dates'), findsOneWidget);

    await tester.tap(find.text('Weekly Planner'));
    await settle(tester);
    expect(find.text('Dates'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(
            find.ancestor(
              of: find.text(range.replaceFirst(' - ', ' – ')),
              matching: find.byType(ChoiceChip),
            ),
          )
          .selected,
      isTrue,
    );
    expect(find.text('Starts'), findsOneWidget);
    expect(find.text(monthYear(thisMonth)), findsOneWidget);
    expect(find.text('2 months'), findsOneWidget);
    await tester.tap(find.text('Create'));
    await settle(tester);

    final repo = backend.notebooks(auth.currentUser!.uid);
    final nb = (await repo.watchNotebooks().first).single;
    expect(nb.title, 'Weekly Planner');
    final pages = await repo.watchNotebookPages(nb.id).first;
    expect(
      pages.map((p) => p.title),
      unorderedEquals([
        for (final m in months.skip(1)) ...[
          monthYear(m),
          '${monthYear(m)} goals',
        ],
        'Notes',
      ]),
      reason: 'last month and its goals are left out',
    );
  });

  testWidgets('another edition can be chosen, or started earlier', (
    tester,
  ) async {
    final auth = await pumpApp(
      tester,
      skins,
      size: const Size(900, 2600),
      overrides: overrides(editions()),
    );
    await tester.tap(find.text('New notebook').last);
    await settle(tester);
    await tester.tap(find.text('Weekly Planner'));
    await settle(tester);

    // Start a month earlier, on the planner's first month.
    await tester.tap(find.text(monthYear(thisMonth)));
    await settle(tester);
    await tester.tap(find.text(monthYear(months.first)).last);
    await settle(tester);
    expect(find.text('3 months'), findsOneWidget);

    await tester.tap(find.text('$nextYear'));
    await settle(tester);
    expect(find.text(monthYear(DateTime(nextYear))), findsOneWidget);
    await tester.tap(find.text('Create'));
    await settle(tester);

    final repo = backend.notebooks(auth.currentUser!.uid);
    final nb = (await repo.watchNotebooks().first).single;
    final pages = await repo.watchNotebookPages(nb.id).first;
    expect(pages.map((p) => p.template!.itemId).toSet(), {'weekly_$nextYear'});
    expect(pages, hasLength(5));
  });

  testWidgets('an edition not unlocked yet shows a lock', (tester) async {
    await pumpApp(
      tester,
      skins,
      size: const Size(900, 2600),
      overrides: overrides(editions(nextFree: false)),
    );
    await tester.tap(find.text('New notebook').last);
    await settle(tester);
    await tester.tap(find.text('Weekly Planner'));
    await settle(tester);
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('$nextYear'),
          matching: find.byType(ChoiceChip),
        ),
        matching: find.byIcon(Icons.lock_outline),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a locked planner shows in New notebook, after the others', (
    tester,
  ) async {
    await pumpApp(
      tester,
      skins,
      size: const Size(900, 2600),
      overrides: overrides([
        template(
          downloader,
          'life_planner_$nextYear',
          datedPlanner([DateTime(nextYear)]),
          name: 'Life Planner $nextYear',
          free: false,
        ),
        ...editions(),
      ]),
    );
    await tester.tap(find.text('New notebook').last);
    await settle(tester);
    expect(find.bySemanticsLabel(RegExp('Life Planner.*locked')), findsOne);
    expect(
      tester.getTopLeft(find.text('Life Planner')).dy,
      greaterThan(tester.getTopLeft(find.text('Weekly Planner')).dy - 1),
    );
    await tester.tap(find.text('Life Planner'));
    await settle(tester);
    // Its store page, to unlock it.
    expect(find.text('Included in Jotswift Pro'), findsOneWidget);
  });

  testWidgets("a planner's collection gives the notebook its cover and theme", (
    tester,
  ) async {
    final planner = template(
      downloader,
      'kraft_planner',
      datedPlanner([thisMonth]),
      name: 'Kraft Planner',
    );
    final withCollection = CatalogItem(
      id: planner.id,
      kind: planner.kind,
      name: planner.name,
      version: planner.version,
      unlock: planner.unlock,
      visibility: planner.visibility,
      templateMode: planner.templateMode,
      files: planner.files,
      collectionId: 'kraft',
    );
    final art = cover('kraft_cover', downloader);
    final kraftCover = CatalogItem(
      id: art.id,
      kind: art.kind,
      name: art.name,
      version: art.version,
      unlock: art.unlock,
      visibility: art.visibility,
      files: art.files,
      color: art.color,
      collectionId: 'kraft',
    );
    final auth = await pumpApp(
      tester,
      skins,
      size: const Size(900, 2600),
      overrides: overrides([withCollection, kraftCover]),
    );
    await tester.tap(find.text('New notebook').last);
    await settle(tester);
    await tester.tap(find.text('Kraft Planner'));
    await settle(tester);
    expect(find.text('Theme'), findsOneWidget);
    await tester.tap(find.text('Create'));
    await settle(tester);

    final repo = backend.notebooks(auth.currentUser!.uid);
    final nb = (await repo.watchNotebooks().first).single;
    expect(nb.cover.kind, CoverKind.art);
    expect(nb.cover.coverId, 'kraft_cover');
    expect(nb.collectionId, 'kraft');
  });

  testWidgets('a dated planner continues into its next edition', (
    tester,
  ) async {
    final auth = await pumpApp(
      tester,
      skins,
      size: const Size(900, 2600),
      overrides: overrides(editions()),
    );
    await tester.tap(find.text('New notebook').last);
    await settle(tester);
    await tester.tap(find.text('Weekly Planner'));
    await settle(tester);
    await tester.tap(find.text('Create'));
    await settle(tester);
    final repo = backend.notebooks(auth.currentUser!.uid);
    final nb = (await repo.watchNotebooks().first).single;
    ProviderScope.containerOf(tester.element(find.byType(Navigator).first))
        .read(routerProvider)
        .go('/notebooks/${nb.id}');
    await settle(tester);

    await tester.tap(find.byTooltip('Notebook options'));
    await settle(tester);
    await tester.tap(
      // The listing runs to December.
      find.text('Continue to ${monthYear(DateTime(nextYear, 12))}…'),
    );
    await settle(tester);
    await tester.tap(find.text('Add months'));
    await settle(tester);

    final next = DateTime(months.last.year, months.last.month + 1);
    final added = [
      for (final m in [DateTime(nextYear), DateTime(nextYear, 2)])
        if (!m.isBefore(next)) m,
    ];
    final pages = await repo.watchNotebookPages(nb.id).first;
    expect(
      [
        for (final p in pages)
          if (p.template!.itemId == 'weekly_$nextYear') p.title,
      ],
      unorderedEquals([
        for (final m in added) ...[monthYear(m), '${monthYear(m)} goals'],
      ]),
      reason: 'its months, without another Notes section',
    );
    final sections = await repo.watchSections(nb.id).first;
    expect(sections.map((s) => s.title), [
      'Months',
      'Notes',
      'Months $nextYear',
    ]);
  });
}
