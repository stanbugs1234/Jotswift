import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/skins/skin_manifest.dart';

import '../../helpers.dart';

void main() {
  late List<SkinManifest> skins;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    skins = await loadTestSkins();
  });

  const tablet = Size(1366, 1024);

  Future<void> confirmText(
    WidgetTester tester,
    String text,
    String button,
  ) async {
    await tester.enterText(find.byType(TextField).last, text);
    await tester.tap(find.widgetWithText(FilledButton, button));
    await tester.pumpAndSettle();
  }

  /// Creates a notebook where the shelf is, then returns to the shelf.
  Future<void> newNotebook(WidgetTester tester, String title) async {
    await tester.tap(find.text('New notebook'));
    await tester.pumpAndSettle();
    await confirmText(tester, title, 'Create');
    await tester.pageBack();
    await tester.pumpAndSettle();
  }

  Future<void> newGroup(WidgetTester tester, String title) async {
    await tester.tap(find.byTooltip('New group'));
    await tester.pumpAndSettle();
    await confirmText(tester, title, 'Create');
  }

  /// Picks [option] from the only notebook's or group's menu.
  Future<void> menu(WidgetTester tester, String tooltip, String option) async {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  String appBarTitle(WidgetTester tester) =>
      (tester.widget<AppBar>(find.byType(AppBar).last).title! as Text).data!;

  group('phone', () {
    testWidgets('a category keeps its own notebooks; All shows everything', (
      tester,
    ) async {
      await pumpApp(tester, skins);
      await newNotebook(tester, 'Ideas');

      await tester.tap(find.byTooltip('New category'));
      await tester.pumpAndSettle();
      await confirmText(tester, 'School', 'Create');
      expect(appBarTitle(tester), 'School');
      expect(find.text('Nothing here yet'), findsOneWidget);

      await newNotebook(tester, 'Biology');
      expect(find.text('Biology'), findsOneWidget);
      expect(find.text('Ideas'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pumpAndSettle();
      expect(find.text('Biology'), findsOneWidget);
      expect(find.text('Ideas'), findsOneWidget);
    });

    testWidgets('notebooks can be moved into a group and found there', (
      tester,
    ) async {
      await pumpApp(tester, skins);
      await newNotebook(tester, 'Chemistry');
      await newGroup(tester, 'Term 1');
      expect(find.text('0 notebooks'), findsOneWidget);

      await menu(tester, 'Notebook options', 'Move to…');
      await tester.tap(find.text('Term 1').last);
      await tester.pumpAndSettle();

      expect(find.text('Chemistry'), findsNothing);
      expect(find.text('1 notebook'), findsOneWidget);

      await tester.tap(find.text('Term 1'));
      await tester.pumpAndSettle();
      expect(appBarTitle(tester), 'Term 1');
      expect(find.text('Chemistry'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(appBarTitle(tester), 'Notebooks');
    });

    testWidgets('deleting a group keeps its notebooks', (tester) async {
      await pumpApp(tester, skins);
      await newGroup(tester, 'Trips');
      await tester.tap(find.text('Trips'));
      await tester.pumpAndSettle();
      await newNotebook(tester, 'Japan');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      await menu(tester, 'Group options', 'Delete group');
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Trips'), findsNothing);
      expect(find.text('Japan'), findsOneWidget);
    });

    testWidgets('Recent shows notebooks once they have been opened', (
      tester,
    ) async {
      await pumpApp(tester, skins);
      await newNotebook(tester, 'Opened');

      await tester.tap(find.widgetWithText(ChoiceChip, 'Recent'));
      await tester.pumpAndSettle();
      expect(find.text('Opened'), findsOneWidget);
      expect(find.text('Opened today'), findsOneWidget);
    });

    testWidgets('the shelf can be shown as a list', (tester) async {
      await pumpApp(tester, skins);
      await newNotebook(tester, 'Work');

      await tester.tap(find.byTooltip('View options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('List'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Work'), findsOneWidget);
    });

    testWidgets('dragging a notebook onto a group moves it in', (tester) async {
      await pumpApp(tester, skins);
      await newGroup(tester, 'Archive');
      await newNotebook(tester, 'Old notes');

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Old notes')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      final target = tester.getCenter(find.text('Archive'));
      await gesture.moveTo(target - const Offset(0, 20));
      await tester.pump();
      await gesture.moveTo(target);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Old notes'), findsNothing);
      expect(find.text('1 notebook'), findsOneWidget);
    });
  });

  group('tablet', () {
    testWidgets('categories are made and opened from the sidebar', (
      tester,
    ) async {
      await pumpApp(tester, skins, size: tablet);

      await tester.tap(find.text('New category'));
      await tester.pumpAndSettle();
      await confirmText(tester, 'Work', 'Create');

      expect(appBarTitle(tester), 'Work');
      final tile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Work'),
      );
      expect(tile.selected, isTrue);
      // No category chips next to the sidebar.
      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('deleting the open category goes back to All notebooks', (
      tester,
    ) async {
      await pumpApp(tester, skins, size: tablet);
      await tester.tap(find.text('New category'));
      await tester.pumpAndSettle();
      await confirmText(tester, 'Temp', 'Create');

      await tester.tap(find.byTooltip('Category options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete category'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(appBarTitle(tester), 'Notebooks');
      expect(find.widgetWithText(ListTile, 'Temp'), findsNothing);
    });
  });
}
