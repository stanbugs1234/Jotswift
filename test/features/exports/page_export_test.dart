import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:notely/core/skins/skin_providers.dart';
import 'package:notely/features/exports/export_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/canvas/domain/stroke.dart';
import 'package:notely/features/exports/page_export.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';
import 'package:notely/features/notebooks/notes_providers.dart';

import '../../helpers.dart';

void main() {
  late List<SkinManifest> skins;

  setUpAll(() async {
    skins = await loadTestSkins();
  });

  test('file names keep only safe characters', () {
    expect(exportFileName('Biology: week 3/4', 'pdf'), 'Biology week 34.pdf');
    expect(exportFileName('  ', 'png'), 'Jotswift.png');
  });

  /// The app with one notebook and one page holding a thick black line
  /// across its middle. Returns the page's id.
  Future<String> pumpPage(
    WidgetTester tester,
    InMemoryNotesBackend backend,
  ) async {
    final auth = await pumpApp(
      tester,
      skins,
      size: const Size(900, 1200),
      overrides: [notesBackendProvider.overrideWithValue(backend)],
    );
    final uid = auth.currentUser!.uid;
    final repo = backend.notebooks(uid);
    final nb = await repo.createNotebook(
      const NewNotebook(title: 'Bio', cover: NotebookCover.color(1)),
    );
    final section = (await repo.watchSections(nb.id).first).single;
    final page = await repo.createPage(nb.id, section.id);
    await backend
        .strokes(uid)
        .addStroke(
          page.id,
          Stroke(
            id: 's1',
            tool: InkTool.pen,
            color: 0xFF000000,
            width: 20,
            points: [for (var x = 200.0; x <= 1200; x += 50) InkPoint(x, 936)],
            createdAt: 1,
          ),
        );
    await tester.pumpAndSettle();
    return page.id;
  }

  testWidgets('a page is drawn with its ink, at print size', (tester) async {
    final backend = InMemoryNotesBackend();
    final pageId = await pumpPage(tester, backend);
    final context = tester.element(find.byType(Scaffold).first);

    final (width, height, ink, blank) = (await tester.runAsync(() async {
      final image = await PageRenderer(context).render(pageId);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      int pixel(double x, double y) {
        final i =
            ((y * exportPixelRatio).round() * image.width +
                (x * exportPixelRatio).round()) *
            4;
        return data!.getUint8(i); // red
      }

      return (image.width, image.height, pixel(700, 936), pixel(700, 300));
    }))!;

    expect((width, height), (2106, 2808));
    expect(ink, lessThan(60), reason: 'the line is dark');
    expect(blank, greaterThan(150), reason: 'paper above it is light');
  });

  testWidgets('pages become a PDF, a Letter page each', (tester) async {
    final backend = InMemoryNotesBackend();
    final pageId = await pumpPage(tester, backend);
    final context = tester.element(find.byType(Scaffold).first);

    final done = <int>[];
    final pdf = (await tester.runAsync(
      () => pagesToPdf(
        PageRenderer(context),
        [pageId, pageId],
        title: 'Bio',
        progress: done.add,
      ),
    ))!;
    final text = latin1.decode(pdf);

    expect(text, startsWith('%PDF'));
    expect(RegExp(r'/Type\s*/Page\b').allMatches(text), hasLength(2));
    expect(text, contains('612'));
    expect(text, contains('816'));
    expect(done, [1, 2]);
  });

  testWidgets('pages become PNGs', (tester) async {
    final backend = InMemoryNotesBackend();
    final pageId = await pumpPage(tester, backend);
    final context = tester.element(find.byType(Scaffold).first);

    final pngs = (await tester.runAsync(
      () => pagesToPng(PageRenderer(context), [pageId]),
    ))!;

    expect(pngs, hasLength(1));
    expect(pngs.single.sublist(1, 4), utf8.encode('PNG'));
  });

  group('the share button', () {
    late InMemoryNotesBackend backend;
    late List<List<SharedFile>> shared;
    late List<String> printed;
    late String notebookId, sectionId;
    late List<String> pageIds;

    Future<void> pumpButton(WidgetTester tester, {String? pageId}) async {
      tester.view
        ..physicalSize = const Size(900, 1200)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = await makeContainer(
        skins,
        overrides: [
          notesBackendProvider.overrideWithValue(backend),
          currentUidProvider.overrideWithValue('sam'),
          shareFilesProvider.overrideWithValue((files, _) async {
            shared.add(files);
          }),
          printPdfProvider.overrideWithValue((pdf, name) async {
            printed.add(name);
          }),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: container.read(lightThemeProvider),
            home: Scaffold(
              appBar: AppBar(
                actions: [ExportButton(notebookId: notebookId, pageId: pageId)],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> choose(WidgetTester tester, String scope, String how) async {
      await tester.tap(find.byTooltip('Share or print'));
      await tester.pumpAndSettle();
      if (scope.isNotEmpty) {
        await tester.tap(find.text(scope));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text(how));
      // The progress spinner never settles, so pump until it's gone.
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        if (find.textContaining('Preparing').evaluate().isEmpty && i > 2) {
          break;
        }
      }
      await tester.pumpAndSettle();
    }

    setUp(() async {
      backend = InMemoryNotesBackend();
      shared = [];
      printed = [];
      final repo = backend.notebooks('sam');
      final nb = await repo.createNotebook(
        const NewNotebook(title: 'Bio', cover: NotebookCover.color(1)),
      );
      notebookId = nb.id;
      sectionId = (await repo.watchSections(nb.id).first).single.id;
      await repo.renameSection(nb.id, sectionId, 'Cells');
      final other = await repo.createSection(nb.id, 'Plants');
      pageIds = [
        (await repo.createPage(nb.id, sectionId, title: 'One')).id,
        (await repo.createPage(nb.id, sectionId, title: 'Two')).id,
        (await repo.createPage(nb.id, other.id, title: 'Three')).id,
      ];
    });

    testWidgets('shares this page as a PDF', (tester) async {
      await pumpButton(tester, pageId: pageIds.first);
      await choose(tester, '', 'Share as PDF');

      final file = shared.single.single;
      expect(file.name, 'Bio - One.pdf');
      expect(file.mimeType, 'application/pdf');
      expect(
        RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(file.bytes)),
        hasLength(1),
      );
      expect(find.textContaining('Preparing'), findsNothing);
    });

    testWidgets('shares a section as images, a PNG a page', (tester) async {
      await pumpButton(tester, pageId: pageIds.first);
      await choose(tester, 'Section', 'Share as image');

      expect(shared.single.map((f) => f.name), [
        'Bio - Cells 1.png',
        'Bio - Cells 2.png',
      ]);
    });

    testWidgets('prints the whole notebook', (tester) async {
      await pumpButton(tester);
      await choose(tester, '', 'Print');

      expect(printed, ['Bio']);
      expect(shared, isEmpty);
    });
  });
}
