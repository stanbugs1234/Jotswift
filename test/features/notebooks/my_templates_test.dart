import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/app/router.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/canvas/domain/page_element.dart';
import 'package:notely/features/canvas/domain/stroke.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';
import 'package:notely/features/notebooks/my_templates.dart';
import 'package:notely/features/notebooks/notebook_editor.dart';
import 'package:notely/features/notebooks/notes_providers.dart';

import '../../helpers.dart';

void main() {
  late List<SkinManifest> skins;
  late InMemoryNotesBackend backend;

  setUpAll(() async {
    skins = await loadTestSkins();
  });

  setUp(() => backend = InMemoryNotesBackend());

  Stroke line(String id) => Stroke(
    id: id,
    tool: InkTool.pen,
    color: 0xFF000000,
    width: 3,
    points: const [InkPoint(0, 0), InkPoint(10, 10)],
    createdAt: 1,
  );

  /// A project notebook: sections Dashboard and Scope, a page in each,
  /// ink on the dashboard and a link from it to the scope page.
  Future<(ProviderContainer, Notebook, List<String>)> project() async {
    final container = await makeContainer(
      skins,
      overrides: [
        notesBackendProvider.overrideWithValue(backend),
        currentUidProvider.overrideWithValue('sam'),
      ],
    );
    final repo = container.read(notebookRepositoryProvider);
    final nb = await repo.createNotebook(
      const NewNotebook(title: 'Hospital bid', cover: NotebookCover.color(1)),
    );
    final first = (await repo.watchSections(nb.id).first).single;
    await repo.renameSection(nb.id, first.id, '00 - Dashboard');
    final scope = await repo.createSection(nb.id, '01 - Scope');
    final dash = await repo.createPage(nb.id, first.id, title: 'Dashboard');
    final scopePage = await repo.createPage(nb.id, scope.id, title: 'Scope');
    await container
        .read(strokeRepositoryProvider)
        .addStroke(dash.id, line('a'));
    await container
        .read(elementRepositoryProvider)
        .addElement(
          dash.id,
          PageElement(
            id: 'link',
            content: LinkContent(scopePage.id),
            frame: const ElementFrame(
              center: Offset(50, 50),
              width: 40,
              height: 20,
            ),
            z: 1,
            createdAt: 0,
          ),
        );
    await pumpEventQueue();
    return (container, nb, [dash.id, scopePage.id]);
  }

  NewNotebook from(Notebook nb, String title, {bool template = false}) =>
      NewNotebook(
        title: title,
        cover: nb.cover,
        paperSize: nb.paperSize,
        orientation: nb.orientation,
        isTemplate: template,
      );

  test('a copy has the same sections, pages, ink and items', () async {
    final (container, nb, source) = await project();
    final copy = await container.read(copyNotebookProvider)(
      nb.id,
      from(nb, 'Clinic bid'),
    );
    await pumpEventQueue();
    final repo = container.read(notebookRepositoryProvider);

    final sections = await repo.watchSections(copy.id).first;
    expect(sections.map((s) => s.title), ['00 - Dashboard', '01 - Scope']);
    final dash = (await repo.watchPages(copy.id, sections[0].id).first).single;
    final scope = (await repo.watchPages(copy.id, sections[1].id).first).single;
    expect(dash.title, 'Dashboard');
    expect(dash.id, isNot(source[0]));
    expect(
      await container
          .read(strokeRepositoryProvider)
          .watchStrokes(dash.id)
          .first,
      hasLength(1),
    );

    // The link opens the copy's own page, not the original's.
    final link =
        (await container
                .read(elementRepositoryProvider)
                .watchElements(dash.id)
                .first)
            .single;
    expect((link.content as LinkContent).pageId, scope.id);
  });

  test('templates stay off the shelf and are listed apart', () async {
    final (container, nb, _) = await project();
    final sub = container.listen(notebooksProvider, (_, _) {});
    final mine = container.listen(myTemplatesProvider, (_, _) {});
    await container.read(copyNotebookProvider)(
      nb.id,
      from(nb, 'Precon', template: true),
    );
    await pumpEventQueue();

    expect(sub.read().value!.map((n) => n.title), ['Hospital bid']);
    expect(mine.read().value!.map((n) => n.title), ['Precon']);
    expect(mine.read().value!.single.isTemplate, isTrue);
  });

  test('changing a template leaves notebooks made from it alone', () async {
    final (container, nb, _) = await project();
    final repo = container.read(notebookRepositoryProvider);
    final template = await container.read(copyNotebookProvider)(
      nb.id,
      from(nb, 'Precon', template: true),
    );
    final made = await container.read(copyNotebookProvider)(
      template.id,
      from(nb, 'School bid'),
    );
    await pumpEventQueue();

    final section = (await repo.watchSections(template.id).first).first;
    final page = (await repo.watchPages(template.id, section.id).first).first;
    await container
        .read(strokeRepositoryProvider)
        .addStroke(page.id, line('b'));
    await pumpEventQueue();

    final madeSection = (await repo.watchSections(made.id).first).first;
    final madePage =
        (await repo.watchPages(made.id, madeSection.id).first).first;
    expect(
      await container
          .read(strokeRepositoryProvider)
          .watchStrokes(madePage.id)
          .first,
      hasLength(1),
    );
  });

  testWidgets('Save as template from a notebook, then start from it', (
    tester,
  ) async {
    final auth = await pumpApp(
      tester,
      skins,
      size: const Size(1000, 900),
      overrides: [notesBackendProvider.overrideWithValue(backend)],
    );
    final repo = backend.notebooks(auth.currentUser!.uid);
    final nb = await repo.createNotebook(
      const NewNotebook(title: 'Hospital bid', cover: NotebookCover.color(1)),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Navigator).first),
    );
    container.read(routerProvider).go('/notebooks/${nb.id}');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Notebook options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save as template'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'My Precon Project');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Saved "My Precon Project"'), findsOneWidget);

    container.listen(myTemplatesProvider, (_, _) {});
    await tester.pump();
    final templates = container.read(myTemplatesProvider).value!;
    expect(templates.single.title, 'My Precon Project');

    // It's offered when making a notebook.
    final context = tester.element(find.byType(Scaffold).first);
    final result = NotebookEditor.show(
      context,
      initial: const NewNotebook(title: '', cover: NotebookCover.color(2)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('My Precon Project'));
    await tester.pumpAndSettle();
    expect(find.textContaining('A copy of your template'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Clinic bid');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    final chosen = await result;
    expect(chosen!.mine!.id, templates.single.id);
    expect(chosen.notebook.title, 'Clinic bid');

    // Managed in Settings.
    container.read(routerProvider).go(myTemplatesPath);
    await tester.pumpAndSettle();
    expect(find.text('My Precon Project'), findsOneWidget);
    await tester.tap(find.byTooltip('Template options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete').last);
    await tester.pumpAndSettle();
    expect(find.text('My Precon Project'), findsNothing);
  });
}
