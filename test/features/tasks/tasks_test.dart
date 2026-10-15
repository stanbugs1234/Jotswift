import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/tasks/data/task_repository.dart';
import 'package:notely/features/tasks/domain/task.dart';
import 'package:notely/features/tasks/task_providers.dart';

import '../../helpers.dart';

const today = Day(2026, 10, 14);

Task task(
  String id, {
  Day? due,
  bool done = false,
  double order = 0,
  TaskPriority priority = TaskPriority.none,
  String? listId,
  int? completedAt,
}) => Task(
  id: id,
  title: id,
  order: order,
  createdAt: 0,
  due: due,
  done: done,
  priority: priority,
  listId: listId,
  completedAt: completedAt,
);

void main() {
  group('Day', () {
    test('reads and writes YYYY-MM-DD', () {
      expect(Day.tryParse('2026-10-14'), today);
      expect(today.toString(), '2026-10-14');
      expect(Day.tryParse('2026-02-30'), isNull);
      expect(Day.tryParse('14/10/2026'), isNull);
      expect(Day.tryParse(20261014), isNull);
    });

    test('counts days across months and years', () {
      expect(today.addDays(18), const Day(2026, 11, 1));
      expect(const Day(2026, 12, 31).addDays(1), const Day(2027, 1, 1));
      expect(today.daysUntil(const Day(2027, 1, 1)), 79);
      expect(today.daysUntil(const Day(2026, 10, 13)), -1);
      expect(const Day(2026, 9, 30).isBefore(today), isTrue);
    });
  });

  test('a task keeps every field through storage', () {
    final t = task(
      'a',
      due: today,
      done: true,
      priority: TaskPriority.high,
      listId: 'l',
      completedAt: 5,
    ).copyWith(notes: 'n');
    expect(Task.fromMap('a', t.toMap()), t);
    expect(
      t.copyWith(clearDue: true, toInbox: true).toMap().keys,
      isNot(anyOf(contains('due'), contains('listId'))),
    );
  });

  group('views', () {
    final tasks = [
      task('later', due: today.addDays(3)),
      task('today low', due: today, priority: TaskPriority.low, order: 2),
      task('today high', due: today, priority: TaskPriority.high, order: 3),
      task('overdue', due: today.addDays(-2)),
      task('done today', due: today, done: true),
      task('tomorrow', due: today.addDays(1)),
      task('no date', order: 1),
    ];

    test('Today: overdue first, then by priority', () {
      expect(tasksForToday(tasks, today).map((t) => t.id), [
        'overdue',
        'today high',
        'today low',
      ]);
    });

    test('Upcoming: grouped by day', () {
      final days = upcomingTasks(tasks, today);
      expect(days.map((d) => d.$1), [today.addDays(1), today.addDays(3)]);
      expect(days.first.$2.single.id, 'tomorrow');
    });

    test('a list: open in order, done newest first', () {
      final list = tasksInList([
        task('b', order: 2),
        task('a', order: 1),
        task('old', done: true, completedAt: 1),
        task('new', done: true, completedAt: 2),
        task('other', listId: 'x'),
      ], null);
      expect(list.open.map((t) => t.id), ['a', 'b']);
      expect(list.done.map((t) => t.id), ['new', 'old']);
    });

    test('dragging picks an order between neighbours', () {
      final open = [task('a', order: 1), task('b', order: 2)];
      expect(orderAt(open, 0), 0);
      expect(orderAt(open, 1), 1.5);
      expect(orderAt(open, 2), 3);
      expect(orderAt(const [], 0), 0);
    });
  });

  for (final (name, make) in <(String, TasksBackend Function())>[
    ('in memory', InMemoryTasksBackend.new),
    ('Firestore', () => FirestoreTasksBackend(FakeFirebaseFirestore())),
  ]) {
    group('$name backend', () {
      test('creates, saves and deletes tasks', () async {
        final repo = make().tasks('sam');
        final a = await repo.createTask('A', due: today);
        final b = await repo.createTask('B');
        expect(b.order, greaterThan(a.order), reason: 'added at the end');

        await repo.saveTask(a.copyWith(done: true, clearDue: true));
        var stored = await repo.watchTasks().first;
        final savedA = stored.firstWhere((t) => t.id == a.id);
        expect(savedA.done, isTrue);
        expect(savedA.due, isNull);

        await repo.deleteTask(b.id);
        stored = await repo.watchTasks().first;
        expect(stored.map((t) => t.id), [a.id]);
      });

      test('deleting a list deletes its tasks', () async {
        final repo = make().tasks('sam');
        final list = await repo.createList('Groceries', color: 0xFF00FF00);
        await repo.createTask('Milk', listId: list.id);
        final inbox = await repo.createTask('Call mum');
        await repo.saveList(list.copyWith(title: 'Shopping'));
        expect((await repo.watchLists().first).single.title, 'Shopping');

        await repo.deleteList(list.id);
        await pumpEventQueue();
        expect(await repo.watchLists().first, isEmpty);
        expect((await repo.watchTasks().first).map((t) => t.id), [inbox.id]);
      });

      test('users don\'t see each other\'s tasks', () async {
        final backend = make();
        await backend.tasks('sam').createTask('Mine');
        expect(await backend.tasks('alex').watchTasks().first, isEmpty);
      });
    });
  }

  group('To-do screen', () {
    late List<SkinManifest> skins;

    setUpAll(() async {
      skins = await loadTestSkins();
    });

    Future<void> openTodo(WidgetTester tester, {Size? size}) async {
      await pumpApp(
        tester,
        skins,
        size: size ?? const Size(400, 800),
        overrides: [todayProvider.overrideWithValue(today)],
      );
      if (size == null) {
        await tester.tap(find.widgetWithText(NavigationDestination, 'To-do'));
      } else {
        await tester.tap(find.text('To-do').last);
      }
      await tester.pumpAndSettle();
    }

    Future<void> add(WidgetTester tester, String title) async {
      await tester.enterText(find.byType(TextField).first, title);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    testWidgets('a task added in Today is due today and can be ticked off', (
      tester,
    ) async {
      await openTodo(tester);
      expect(find.text('Nothing due today.'), findsOneWidget);

      await add(tester, 'Water plants');
      expect(find.text('Water plants'), findsOneWidget);
      expect(find.text('Today'), findsWidgets);

      await tester.tap(find.bySemanticsLabel('Complete Water plants'));
      await tester.pumpAndSettle();
      expect(find.text('Water plants'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Inbox'));
      await tester.pumpAndSettle();
      expect(find.text('Completed (1)'), findsOneWidget);
    });

    testWidgets('editing a task\'s due day moves it to Upcoming', (
      tester,
    ) async {
      await openTodo(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Inbox'));
      await tester.pumpAndSettle();
      await add(tester, 'Book dentist');

      await tester.tap(find.text('Book dentist'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tomorrow'));
      await tester.tap(find.text('High'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Tomorrow'), findsOneWidget, reason: 'its due day');
      expect(find.byIcon(Icons.flag), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Upcoming'));
      await tester.pumpAndSettle();
      expect(find.text('Book dentist'), findsOneWidget);
      expect(find.text('Tomorrow'), findsOneWidget, reason: 'day heading');
    });

    testWidgets('lists: create, add to, delete with their tasks', (
      tester,
    ) async {
      await openTodo(tester);
      await tester.drag(find.text('Inbox'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New list'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Groceries');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Groceries'))
            .selected,
        isTrue,
      );
      await add(tester, 'Milk');
      expect(find.text('Milk'), findsOneWidget);

      await tester.tap(find.byTooltip('List options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete list'));
      await tester.pumpAndSettle();
      expect(find.text('Its 1 task will be deleted too.'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ChoiceChip, 'Groceries'), findsNothing);
      expect(find.widgetWithText(AppBar, 'Nothing due today.'), findsNothing);
      expect(find.text('Nothing due today.'), findsOneWidget);
    });

    testWidgets('swiping deletes, and Undo brings it back', (tester) async {
      await openTodo(tester);
      await add(tester, 'Pay rent');
      await tester.drag(find.text('Pay rent'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('Pay rent'), findsNothing);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Pay rent'), findsOneWidget);
    });

    testWidgets('wide screens show the views in a side pane', (tester) async {
      await openTodo(tester, size: const Size(1366, 1024));
      expect(find.byType(ChoiceChip), findsNothing);
      await add(tester, 'Plan trip');
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Today'),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
    });
  });
}
