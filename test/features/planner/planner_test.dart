import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/app/app.dart';
import 'package:notely/core/input/finger_drawing.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/calendar/calendar_providers.dart';
import 'package:notely/features/calendar/domain/event.dart';
import 'package:notely/features/canvas/page_canvas.dart';
import 'package:notely/features/notebooks/data/firestore_notes_backend.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/data/notes_repository.dart';
import 'package:notely/features/notebooks/notes_providers.dart';
import 'package:notely/features/planner/planner_screen.dart';
import 'package:notely/features/tasks/domain/task.dart';
import 'package:notely/features/tasks/task_providers.dart';

import '../../helpers.dart';

const today = Day(2026, 10, 14);

Task task(String id, {Day? due, TaskPriority p = TaskPriority.none}) =>
    Task(id: id, title: id, order: 0, createdAt: 0, due: due, priority: p);

void main() {
  test('a day\'s tasks: due that day, plus overdue on today', () {
    final tasks = [
      task('overdue', due: today.addDays(-1)),
      task('today', due: today),
      task('urgent', due: today, p: TaskPriority.high),
      task('tomorrow', due: today.addDays(1)),
      task('undated'),
    ];
    expect(plannerTasks(tasks, today, today).map((t) => t.id), [
      'urgent',
      'overdue',
      'today',
    ]);
    expect(plannerTasks(tasks, today.addDays(1), today).map((t) => t.id), [
      'tomorrow',
    ]);
  });

  for (final (name, make) in <(String, NotesBackend Function())>[
    ('in memory', InMemoryNotesBackend.new),
    ('Firestore', () => FirestoreNotesBackend(FakeFirebaseFirestore())),
  ]) {
    test(
      '$name: a planner page is made once and stays off the shelf',
      () async {
        final repo = make().notebooks('sam');
        for (var i = 0; i < 2; i++) {
          await repo.ensurePage(
            plannerPageId(today),
            notebookId: plannerNotebookId,
            title: '2026-10-14',
          );
        }
        await pumpEventQueue();
        final page = await repo.watchPage('planner-2026-10-14').first;
        expect(page?.notebookId, plannerNotebookId);
        expect(await repo.watchNotebooks().first, isEmpty);
      },
    );
  }

  group('Planner screen', () {
    late List<SkinManifest> skins;

    setUpAll(() async {
      skins = await loadTestSkins();
    });

    Future<ProviderContainer> openPlanner(
      WidgetTester tester, {
      Size size = const Size(400, 800),
      Map<String, Object> prefs = const {},
    }) async {
      await pumpApp(
        tester,
        skins,
        size: size,
        prefs: prefs,
        overrides: [todayProvider.overrideWithValue(today)],
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NotelyApp)),
      );
      await container
          .read(eventRepositoryProvider)
          .saveEvent(
            CalendarEvent(
              id: '',
              title: 'Standup',
              start: DateTime(2026, 10, 14, 9),
              end: DateTime(2026, 10, 14, 9, 15),
              color: CalendarEvent.defaultEventColor,
            ),
          );
      final tasks = container.read(taskRepositoryProvider);
      await tasks.createTask('Send invoice', due: today);
      await tasks.createTask('Buy flowers', due: today.addDays(1));
      if (size.width < 600) {
        await tester.tap(find.widgetWithText(NavigationDestination, 'Planner'));
      } else {
        await tester.tap(find.text('Planner').last);
      }
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('shows the day\'s schedule and tasks', (tester) async {
      await openPlanner(tester);
      expect(find.text('Wed, Oct 14'), findsOneWidget);
      expect(find.text('Standup'), findsOneWidget);
      expect(find.text('Send invoice'), findsOneWidget);
      expect(find.text('Buy flowers'), findsNothing);

      await tester.tap(find.byTooltip('Next day'));
      await tester.pumpAndSettle();
      expect(find.text('Thu, Oct 15'), findsOneWidget);
      expect(find.text('Buy flowers'), findsOneWidget);
      expect(find.text('Nothing scheduled.'), findsOneWidget);

      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(find.text('Standup'), findsOneWidget);
    });

    testWidgets('tasks added here are due that day; ticking one off', (
      tester,
    ) async {
      final container = await openPlanner(tester);
      await tester.tap(find.byTooltip('Next day'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Call the bank');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final added =
          (await container.read(taskRepositoryProvider).watchTasks().first)
              .firstWhere((t) => t.title == 'Call the bank');
      expect(added.due, today.addDays(1));

      await tester.tap(find.bySemanticsLabel('Complete Call the bank'));
      await tester.pumpAndSettle();
      expect(find.text('Call the bank'), findsNothing);
    });

    testWidgets('each day has its own page to write on', (tester) async {
      final container = await openPlanner(tester);
      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<PageCanvas>(find.byType(PageCanvas)).pageId,
        'planner-2026-10-14',
      );
      final page = await container
          .read(notebookRepositoryProvider)
          .watchPage('planner-2026-10-14')
          .first;
      expect(page, isNotNull);
    });

    testWidgets("with the iPad set to Pencil-only, a finger on a day's page "
        "scrolls instead of drawing", (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            DevicePencilController.channel,
            (call) async => true,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(DevicePencilController.channel, null),
      );
      final container = await openPlanner(tester);
      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();

      final start = tester.getCenter(find.byType(PageCanvas));
      final g = await tester.startGesture(start);
      for (var i = 1; i <= 6; i++) {
        await g.moveTo(start + Offset(0, -20.0 * i));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();
      // Let the one-time hint finish showing.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      final strokes = await container
          .read(strokeRepositoryProvider)
          .watchStrokes('planner-2026-10-14')
          .first;
      expect(strokes, isEmpty);
      // The Pencil still writes there.
      final pen = await tester.startGesture(
        start,
        kind: PointerDeviceKind.stylus,
      );
      await pen.moveBy(const Offset(60, 10));
      await pen.up();
      await tester.pumpAndSettle();
      expect(
        await container
            .read(strokeRepositoryProvider)
            .watchStrokes('planner-2026-10-14')
            .first,
        hasLength(1),
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('wide screens show the plan and the page side by side', (
      tester,
    ) async {
      await openPlanner(tester, size: const Size(1366, 1024));
      expect(find.byType(TabBar), findsNothing);
      expect(find.text('Standup'), findsOneWidget);
      expect(find.byType(PageCanvas), findsOneWidget);
    });

    testWidgets('the Calendar opens a day in the Planner', (tester) async {
      await openPlanner(tester);
      await tester.tap(find.widgetWithText(NavigationDestination, 'Calendar'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel(RegExp('October 20, 2026')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Planner'));
      await tester.pumpAndSettle();
      expect(find.text('Tue, Oct 20'), findsOneWidget);
    });
  });
}
