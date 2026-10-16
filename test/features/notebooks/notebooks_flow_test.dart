import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/app/app.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/canvas/ink_toolbar.dart';
import 'package:notely/features/notebooks/notebook_screen.dart';
import 'package:notely/features/notebooks/notes_providers.dart';
import 'package:notely/features/notebooks/page_screen.dart';
import 'package:notely/features/shelf/cover_view.dart';

import '../../helpers.dart';

void main() {
  late List<SkinManifest> skins;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    skins = await loadTestSkins();
  });

  Future<void> enterTextAndConfirm(
    WidgetTester tester,
    String text,
    String button,
  ) async {
    await tester.enterText(find.byType(TextField).last, text);
    await tester.tap(find.widgetWithText(FilledButton, button));
    await tester.pumpAndSettle();
  }

  Future<void> createNotebook(WidgetTester tester, String title) async {
    await tester.tap(find.text('New notebook'));
    await tester.pumpAndSettle();
    await enterTextAndConfirm(tester, title, 'Create');
  }

  testWidgets('the shelf starts empty and invites creating a notebook', (
    tester,
  ) async {
    await pumpApp(tester, skins);

    expect(find.text('No notebooks yet'), findsOneWidget);
  });

  testWidgets('create a notebook, add a page, write, and come back', (
    tester,
  ) async {
    await pumpApp(tester, skins);

    await createNotebook(tester, 'Biology');

    // The new notebook opens with its first section.
    expect(find.widgetWithText(AppBar, 'Biology'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Notes'), findsOneWidget);
    expect(find.text('No pages in Notes yet.'), findsOneWidget);

    await tester.tap(find.text('New page'));
    await tester.pumpAndSettle();

    // The page opens full screen with the drawing tools.
    expect(find.byType(InkToolbar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Untitled page'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(CoverView), findsOneWidget);
    expect(find.text('Biology'), findsOneWidget);
  });

  testWidgets('sections keep their own pages', (tester) async {
    await pumpApp(tester, skins);
    await createNotebook(tester, 'Work');

    await tester.tap(find.text('New page'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ActionChip, 'Section'));
    await tester.pumpAndSettle();
    await enterTextAndConfirm(tester, 'Meetings', 'Add');

    expect(find.text('No pages in Meetings yet.'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Notes'));
    await tester.pumpAndSettle();
    expect(find.text('Untitled page'), findsOneWidget);
  });

  testWidgets('pages can be renamed and deleted', (tester) async {
    await pumpApp(tester, skins);
    await createNotebook(tester, 'Ideas');
    await tester.tap(find.text('New page'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Page options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await enterTextAndConfirm(tester, 'App ideas', 'Rename');
    expect(find.text('App ideas'), findsOneWidget);

    await tester.tap(find.byTooltip('Page options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('App ideas'), findsNothing);
    expect(find.text('No pages in Notes yet.'), findsOneWidget);
  });

  testWidgets('notebooks go to the Trash, to be restored or deleted', (
    tester,
  ) async {
    await pumpApp(tester, skins);
    await createNotebook(tester, 'Temp');
    await tester.pageBack();
    await tester.pumpAndSettle();

    Future<void> moveToTrash() async {
      await tester.tap(find.byTooltip('Notebook options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to Trash'));
      await tester.pumpAndSettle();
    }

    Future<void> openPlace(String label) async {
      final chip = find.widgetWithText(ChoiceChip, label);
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
    }

    await moveToTrash();
    expect(find.byType(CoverView), findsNothing);
    expect(find.text('No notebooks yet'), findsOneWidget);
    expect(find.text('Moved "Temp" to the Trash'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Moved "Temp" to the Trash'), findsNothing);

    await openPlace('Trash');
    await tester.tap(find.text('Temp'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.text('The Trash is empty'), findsOneWidget);

    await openPlace('Home');
    expect(find.byType(CoverView), findsOneWidget);

    await moveToTrash();
    await openPlace('Trash');
    await tester.tap(find.text('Empty Trash'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Empty Trash'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('The Trash is empty'), findsOneWidget);
    expect(find.text('Trash emptied'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(NotelyApp)),
    );
    expect(container.read(notebooksProvider).value, isEmpty);
  });

  testWidgets('a starred notebook shows under Starred', (tester) async {
    await pumpApp(tester, skins);
    await createNotebook(tester, 'Fav');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Notebook options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Star'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Starred'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Starred'));
    await tester.pumpAndSettle();
    expect(find.text('Fav'), findsOneWidget);
  });

  testWidgets('Quick note opens a new page right away', (tester) async {
    await pumpApp(tester, skins);
    await tester.tap(find.text('Quick note'));
    await tester.pumpAndSettle();

    expect(find.byType(PageScreen), findsOneWidget);
    // Back shows the notebook's sections, then Home.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(PageScreen), findsNothing);
    expect(find.byType(NotebookScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Quick note'), findsWidgets);
    expect(find.byType(CoverView), findsOneWidget);
  });
}
