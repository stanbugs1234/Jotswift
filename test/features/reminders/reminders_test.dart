import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/app/app.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/auth/auth_repository.dart';
import 'package:notely/features/calendar/calendar_providers.dart';
import 'package:notely/features/calendar/domain/event.dart';
import 'package:notely/features/reminders/reminders.dart';
import 'package:notely/features/tasks/domain/task.dart';
import 'package:notely/features/tasks/task_providers.dart';

import '../../helpers.dart';

/// Records what would be scheduled.
class FakeReminders implements ReminderService {
  final scheduled = <List<Reminder>>[];
  final tapController = StreamController<Day>.broadcast();
  int permissionRequests = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> schedule(List<Reminder> reminders) async =>
      scheduled.add(reminders);

  @override
  Stream<Day> get taps => tapController.stream;
}

final now = DateTime(2026, 10, 14, 8);
const today = Day(2026, 10, 14);

String fmt(DateTime t) => '${t.hour}:${t.minute.toString().padLeft(2, '0')}';

Task task(String id, {Day? due, int? remindAt, bool done = false}) => Task(
  id: id,
  title: id,
  order: 0,
  createdAt: 0,
  due: due,
  remindAt: remindAt,
  done: done,
);

CalendarEvent event(
  String id,
  DateTime start, {
  bool allDay = false,
  List<int> alerts = const [],
  Recurrence? repeat,
}) => CalendarEvent(
  id: id,
  title: id,
  allDay: allDay,
  start: start,
  end: allDay ? start : start.add(const Duration(hours: 1)),
  color: 0,
  reminderMinutes: alerts,
  recurrence: repeat,
);

void main() {
  group('upcomingReminders', () {
    List<Reminder> remind({
      List<Task> tasks = const [],
      List<CalendarEvent> events = const [],
    }) => upcomingReminders(
      tasks: tasks,
      events: events,
      now: now,
      formatTime: fmt,
    );

    test('tasks: at their time on the due day, not done, not past', () {
      final r = remind(
        tasks: [
          task('call', due: today, remindAt: 9 * 60 + 30),
          task('early', due: today, remindAt: 7 * 60),
          task('done', due: today, remindAt: 10 * 60, done: true),
          task('no reminder', due: today),
          task('far', due: today.addDays(30), remindAt: 9 * 60),
        ],
      );
      expect(r.map((x) => x.title), ['call']);
      expect(r.single.at, DateTime(2026, 10, 14, 9, 30));
      expect(r.single.day, today);
    });

    test('events: before the start; all-day at 9 AM', () {
      final r = remind(
        events: [
          event('standup', DateTime(2026, 10, 14, 10), alerts: [15]),
          event(
            'birthday',
            today.addDays(1).toDateTime(),
            allDay: true,
            alerts: [-540, 900],
          ),
          event('quiet', DateTime(2026, 10, 14, 11)),
        ],
      );
      expect(r.map((x) => (x.title, x.at)), [
        ('birthday', DateTime(2026, 10, 14, 9)),
        ('standup', DateTime(2026, 10, 14, 9, 45)),
        ('birthday', DateTime(2026, 10, 15, 9)),
      ]);
      expect(r[1].body, '10:00 – 11:00');
      expect(r.first.body, 'All day');
    });

    test('a repeating event reminds for each repeat in the next two weeks', () {
      final r = remind(
        events: [
          event(
            'gym',
            DateTime(2026, 10, 1, 18),
            alerts: [30],
            repeat: const Recurrence(Frequency.weekly),
          ),
        ],
      );
      expect(r.map((x) => x.day), [
        const Day(2026, 10, 15),
        const Day(2026, 10, 22),
      ]);
      expect(r.map((x) => x.id).toSet(), hasLength(2), reason: 'unique ids');
    });

    test('at most $maxReminders, soonest first', () {
      final r = remind(
        events: [
          event(
            'pills',
            DateTime(2026, 10, 1, 8, 30),
            alerts: [0, 5, 10, 15, 20],
            repeat: const Recurrence(Frequency.daily),
          ),
        ],
      );
      expect(r, hasLength(maxReminders));
      for (var i = 1; i < r.length; i++) {
        expect(r[i].at.isBefore(r[i - 1].at), isFalse);
      }
    });

    test('ids stay the same for the same reminder', () {
      final a = remind(tasks: [task('x', due: today, remindAt: 600)]);
      final b = remind(tasks: [task('x', due: today, remindAt: 600)]);
      expect(a.single.id, b.single.id);
    });
  });

  group('keeping reminders scheduled', () {
    late List<SkinManifest> skins;

    setUpAll(() async {
      skins = await loadTestSkins();
    });

    test('reschedules after changes, and clears on sign-out', () async {
      final fake = FakeReminders();
      final auth = DevAuthRepository();
      await auth.signInWithEmail('sam@example.com', 'secret1');
      final container = await makeContainer(
        skins,
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          reminderServiceProvider.overrideWithValue(fake),
        ],
      );
      final sub = container.listen(reminderSyncProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(fake.scheduled.last, isEmpty);

      final tomorrow = Day.today().addDays(1);
      await container
          .read(taskRepositoryProvider)
          .saveTask(task('dentist', due: tomorrow, remindAt: 9 * 60));
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(fake.scheduled.last.single.title, 'dentist');

      sub.close();
      container.dispose();
      expect(fake.scheduled.last, isEmpty);
    });

    testWidgets('a task reminder is set in the editor', (tester) async {
      final fake = FakeReminders();
      await pumpApp(
        tester,
        skins,
        overrides: [
          todayProvider.overrideWithValue(today),
          reminderServiceProvider.overrideWithValue(fake),
        ],
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NotelyApp)),
      );
      await container
          .read(taskRepositoryProvider)
          .createTask('Water plants', due: today);
      await tester.tap(find.widgetWithText(NavigationDestination, 'To-do'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Water plants'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remind me'));
      await tester.pumpAndSettle();
      expect(find.text('9:00 AM'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved =
          (await container.read(taskRepositoryProvider).watchTasks().first)
              .single;
      expect(saved.remindAt, 9 * 60);
      expect(fake.permissionRequests, 1);
      expect(find.byIcon(Icons.alarm), findsOneWidget);
      // Let the sync timer finish before the test ends.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('an event alert is set in the editor', (tester) async {
      final fake = FakeReminders();
      await pumpApp(
        tester,
        skins,
        size: const Size(400, 1000),
        overrides: [
          todayProvider.overrideWithValue(today),
          reminderServiceProvider.overrideWithValue(fake),
        ],
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NotelyApp)),
      );
      await tester.tap(find.widgetWithText(NavigationDestination, 'Calendar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New event'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Dentist');
      await tester.tap(find.text('None').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('15 minutes before').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved =
          (await container.read(eventRepositoryProvider).watchEvents().first)
              .single;
      expect(saved.reminderMinutes, [15]);
      expect(fake.permissionRequests, 1);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('tapping a reminder opens its day in the Planner', (
      tester,
    ) async {
      final fake = FakeReminders();
      await pumpApp(
        tester,
        skins,
        overrides: [
          todayProvider.overrideWithValue(today),
          reminderServiceProvider.overrideWithValue(fake),
        ],
      );
      fake.tapController.add(const Day(2026, 10, 20));
      await tester.pumpAndSettle();
      expect(find.text('Tue, Oct 20'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
