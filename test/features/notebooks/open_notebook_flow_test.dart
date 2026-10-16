import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/app/app.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/notebooks/data/notes_repository.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';
import 'package:notely/features/notebooks/notebook_screen.dart';
import 'package:notely/features/notebooks/notes_providers.dart';
import 'package:notely/features/notebooks/page_screen.dart';

import '../../helpers.dart';

void main() {
  late List<SkinManifest> skins;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    skins = await loadTestSkins();
  });

  const tablet = Size(1366, 1024);

  /// A planner made the way templates make one: a year page, this week,
  /// last week, and a notes page with no date.
  Future<NotebookRepository> makePlanner(WidgetTester tester) async {
    final repo = ProviderScope.containerOf(
      tester.element(find.byType(NotelyApp)),
    ).read(notebookRepositoryProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final nb = await repo.createNotebook(
      const NewNotebook(title: 'Week planner', cover: NotebookCover.color(0)),
    );
    final section = (await repo.watchSections(nb.id).first).single;
    await repo.createPages(
      nb.id,
      section.id,
      [
        for (final title in ['The year', 'Last week', 'This week', 'Notes'])
          (title: title, paper: null, template: null),
      ],
      periods: [
        PagePeriod.dates(DateTime(now.year), DateTime(now.year, 12, 31)),
        PagePeriod.dates(
          monday.subtract(const Duration(days: 7)),
          monday.subtract(const Duration(days: 1)),
        ),
        PagePeriod.dates(monday, monday.add(const Duration(days: 6))),
        null,
      ],
    );
    await tester.pumpAndSettle();
    return repo;
  }

  /// The title of the open page.
  // A page shows its notebook above its title; other screens just a title.
  String openTitle(WidgetTester tester) {
    final page = find.byKey(const Key('page-title'));
    return tester
        .widget<Text>(
          page.evaluate().isNotEmpty
              ? page
              : find
                    .descendant(
                      of: find.byType(AppBar),
                      matching: find.byType(Text),
                    )
                    .first,
        )
        .data!;
  }

  Future<void> openFromHome(WidgetTester tester) async {
    await tester.tap(find.text('Week planner'));
    await tester.pumpAndSettle();
  }

  Future<void> goTo(WidgetTester tester, String title) async {
    await tester.tap(find.byTooltip('Go to page'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, title).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a planner opens on this week; Back shows its sections, then Home',
    (tester) async {
      await pumpApp(tester, skins, size: tablet);
      await makePlanner(tester);

      await openFromHome(tester);
      expect(find.byType(PageScreen), findsOneWidget);
      expect(openTitle(tester), 'This week');

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(PageScreen), findsNothing);
      expect(find.byType(NotebookScreen), findsOneWidget);
      expect(find.byTooltip('Add a section'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(NotebookScreen), findsNothing);
    },
  );

  testWidgets('the same day, it reopens where you left off', (tester) async {
    await pumpApp(tester, skins, size: tablet);
    await makePlanner(tester);

    await openFromHome(tester);
    await goTo(tester, 'Notes');
    expect(openTitle(tester), 'Notes');
    // Moving between pages keeps Back going to the sections, then Home.
    await tester.tap(find.byTooltip('Previous page'));
    await tester.pumpAndSettle();
    expect(openTitle(tester), 'This week');
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(NotebookScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Continue · Notes'), findsOneWidget);

    await openFromHome(tester);
    expect(openTitle(tester), 'Notes');
  });

  testWidgets('Today jumps to this week; bookmarks are listed', (tester) async {
    await pumpApp(tester, skins, size: tablet);
    await makePlanner(tester);
    await openFromHome(tester);
    await goTo(tester, 'Last week');

    await tester.tap(find.byTooltip('Bookmark page'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove bookmark'), findsOneWidget);

    await tester.tap(find.byTooltip('Today'));
    await tester.pumpAndSettle();
    expect(openTitle(tester), 'This week');

    await tester.tap(find.byTooltip('Go to page'));
    await tester.pumpAndSettle();
    expect(find.text('Bookmarks'), findsOneWidget);
    // Today's page, the bookmark, and its place in the section.
    expect(find.widgetWithText(ListTile, 'This week'), findsNWidgets(2));
    expect(find.widgetWithText(ListTile, 'Last week'), findsNWidgets(2));

    await tester.tap(find.text('All pages'));
    await tester.pumpAndSettle();
    expect(find.byType(NotebookScreen), findsOneWidget);
  });

  testWidgets('a long notebook folds its sections, and pages can be searched', (
    tester,
  ) async {
    await pumpApp(tester, skins, size: tablet);
    final repo = ProviderScope.containerOf(
      tester.element(find.byType(NotelyApp)),
    ).read(notebookRepositoryProvider);
    final nb = await repo.createNotebook(
      const NewNotebook(title: 'Long book', cover: NotebookCover.color(0)),
    );
    final first = (await repo.watchSections(nb.id).first).single;
    await repo.renameSection(nb.id, first.id, 'Spring');
    final second = await repo.createSection(nb.id, 'Autumn');
    for (final (section, name) in [(first, 'Spring'), (second, 'Autumn')]) {
      await repo.createPages(nb.id, section.id, [
        for (var i = 1; i <= 25; i++)
          (title: '$name $i', paper: null, template: null),
      ]);
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('Long book'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Go to page'));
    await tester.pumpAndSettle();
    // Only the open page's section is unfolded.
    expect(find.widgetWithText(ListTile, 'Spring 2'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Autumn 2'), findsNothing);
    await tester.dragUntilVisible(
      find.text('Autumn'),
      find.byType(ListView).last,
      const Offset(0, -300),
    );
    await tester.tap(find.text('Autumn'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.widgetWithText(ListTile, 'Autumn 2'),
      find.byType(ListView).last,
      const Offset(0, -300),
    );
    expect(find.widgetWithText(ListTile, 'Autumn 2'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'autumn 17');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Autumn 17'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Spring 2'), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, 'Autumn 17'));
    await tester.pumpAndSettle();
    expect(openTitle(tester), 'Autumn 17');
  });
}
