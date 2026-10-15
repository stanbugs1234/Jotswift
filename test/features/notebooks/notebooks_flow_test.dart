import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/canvas/ink_toolbar.dart';
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

  testWidgets('notebooks can be deleted from the shelf', (tester) async {
    await pumpApp(tester, skins);
    await createNotebook(tester, 'Temp');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Notebook options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.byType(CoverView), findsNothing);
    expect(find.text('No notebooks yet'), findsOneWidget);
  });
}
