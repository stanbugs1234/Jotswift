import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/app/app.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/calendar/calendar_providers.dart';
import 'package:notely/features/calendar/data/event_repository.dart';
import 'package:notely/features/calendar/domain/event.dart';
import 'package:notely/features/calendar/time_grid.dart';
import 'package:notely/features/tasks/task_providers.dart';

import '../../helpers.dart';

/// A Wednesday.
const today = Day(2026, 10, 14);

CalendarEvent timed(
  String title,
  DateTime start,
  Duration length, {
  Recurrence? repeat,
}) => CalendarEvent(
  id: title,
  title: title,
  start: start,
  end: start.add(length),
  color: CalendarEvent.defaultEventColor,
  recurrence: repeat,
);

CalendarEvent allDay(String title, Day from, Day to, {Recurrence? repeat}) =>
    CalendarEvent(
      id: title,
      title: title,
      allDay: true,
      start: from.toDateTime(),
      end: to.toDateTime(),
      color: CalendarEvent.defaultEventColor,
      recurrence: repeat,
    );

List<Day> startDays(CalendarEvent e, Day from, Day to) => [
  for (final o in occurrencesBetween([e], from, to)) Day.of(o.start),
];

void main() {
  group('repeats', () {
    test('every other day, three times', () {
      final e = allDay(
        'a',
        today,
        today,
        repeat: const Recurrence(Frequency.daily, interval: 2, count: 3),
      );
      expect(startDays(e, today, today.addDays(30)), [
        today,
        today.addDays(2),
        today.addDays(4),
      ]);
    });

    test('weekly on Monday, Wednesday and Friday until a day', () {
      final e = timed(
        'gym',
        DateTime(2026, 10, 14, 7),
        const Duration(hours: 1),
        repeat: const Recurrence(
          Frequency.weekly,
          weekdays: {DateTime.monday, DateTime.wednesday, DateTime.friday},
          until: Day(2026, 10, 23),
        ),
      );
      expect(startDays(e, const Day(2026, 10, 1), const Day(2026, 11, 30)), [
        const Day(2026, 10, 14),
        const Day(2026, 10, 16),
        const Day(2026, 10, 19),
        const Day(2026, 10, 21),
        const Day(2026, 10, 23),
      ]);
    });

    test('keeps the wall-clock time across a daylight saving change', () {
      final e = timed(
        'standup',
        DateTime(2026, 10, 26, 9),
        const Duration(minutes: 15),
        repeat: const Recurrence(Frequency.weekly),
      );
      final later = occurrencesBetween(
        [e],
        const Day(2026, 11, 9),
        const Day(2026, 11, 9),
      ).single;
      expect(later.start.hour, 9);
      expect(later.end.difference(later.start), const Duration(minutes: 15));
    });

    test('monthly on the 31st skips shorter months', () {
      final e = allDay(
        'rent',
        const Day(2026, 10, 31),
        const Day(2026, 10, 31),
        repeat: const Recurrence(Frequency.monthly),
      );
      expect(startDays(e, const Day(2026, 10, 1), const Day(2027, 1, 31)), [
        const Day(2026, 10, 31),
        const Day(2026, 12, 31),
        const Day(2027, 1, 31),
      ]);
    });

    test('yearly on February 29 only in leap years', () {
      final e = allDay(
        'leap',
        const Day(2028, 2, 29),
        const Day(2028, 2, 29),
        repeat: const Recurrence(Frequency.yearly),
      );
      expect(startDays(e, const Day(2028, 1, 1), const Day(2033, 1, 1)), [
        const Day(2028, 2, 29),
        const Day(2032, 2, 29),
      ]);
    });

    test('a daily event from long ago still shows today', () {
      final e = timed(
        'pills',
        DateTime(2000, 1, 1, 8),
        const Duration(minutes: 5),
        repeat: const Recurrence(Frequency.daily),
      );
      expect(startDays(e, today, today), [today]);
    });
  });

  group('which days an event is on', () {
    test('a trip spanning days shows on each of them', () {
      final trip = allDay('trip', today.addDays(-2), today.addDays(1));
      expect(occurrencesBetween([trip], today, today), hasLength(1));
      expect(
        occurrencesBetween([trip], today.addDays(2), today.addDays(9)),
        isEmpty,
      );
    });

    test('a timed event past midnight shows on both days', () {
      final party = timed(
        'party',
        DateTime(2026, 10, 14, 22),
        const Duration(hours: 4),
      );
      final o = occurrencesBetween([party], today, today.addDays(1)).single;
      expect(o.isOn(today), isTrue);
      expect(o.isOn(today.addDays(1)), isTrue);

      final untilMidnight = timed(
        'late',
        DateTime(2026, 10, 14, 23),
        const Duration(hours: 1),
      );
      expect(
        occurrencesBetween([untilMidnight], today.addDays(1), today.addDays(1)),
        isEmpty,
      );
    });

    test('all-day events come first, then by start', () {
      final list = occurrencesBetween(
        [
          timed('b', DateTime(2026, 10, 14, 9), const Duration(hours: 1)),
          timed('a', DateTime(2026, 10, 14, 8), const Duration(hours: 1)),
          allDay('c', today, today),
        ],
        today,
        today,
      );
      expect(list.map((o) => o.event.title), ['c', 'a', 'b']);
    });
  });

  test('overlapping events sit side by side', () {
    DateTime at(int h, [int m = 0]) => DateTime(2026, 10, 14, h, m);
    final slots = layoutDay(
      occurrencesBetween(
        [
          timed('A', at(9), const Duration(hours: 1)),
          timed('B', at(9, 30), const Duration(minutes: 90)),
          timed('C', at(10), const Duration(minutes: 30)),
          timed('D', at(14), const Duration(hours: 1)),
        ],
        today,
        today,
      ),
      today,
    );
    final byTitle = {for (final s in slots) s.occurrence.event.title: s};
    expect(byTitle['A']!.column, 0);
    expect(byTitle['B']!.column, 1);
    expect(byTitle['C']!.column, 0, reason: 'A has ended');
    expect(byTitle['A']!.columns, 2);
    expect(byTitle['D']!.columns, 1, reason: 'on its own');
    expect(byTitle['A']!.top, 9 * 60);
  });

  test('events keep every field through storage', () {
    final e = timed(
      't',
      DateTime(2026, 10, 14, 9, 30),
      const Duration(hours: 1),
      repeat: const Recurrence(
        Frequency.weekly,
        weekdays: {1, 3},
        until: Day(2026, 12, 1),
      ),
    ).copyWith(notes: 'n');
    expect(CalendarEvent.fromMap('t', e.toMap()), e);
    final d = allDay('d', today, today.addDays(2));
    expect(CalendarEvent.fromMap('d', d.toMap()), d);
    expect(d.toMap()['startDay'], '2026-10-14');
    expect(CalendarEvent.fromMap('x', {'title': 'no start'}), isNull);
  });

  for (final (name, make) in <(String, EventsBackend Function())>[
    ('in memory', InMemoryEventsBackend.new),
    ('Firestore', () => FirestoreEventsBackend(FakeFirebaseFirestore())),
  ]) {
    test('$name backend saves, changes and deletes events', () async {
      final repo = make().events('sam');
      final saved = await repo.saveEvent(
        timed('', DateTime(2026, 10, 14, 9), const Duration(hours: 1)),
      );
      expect(saved.id, isNotEmpty);
      await repo.saveEvent(saved.copyWith(title: 'Dentist'));
      expect((await repo.watchEvents().first).single.title, 'Dentist');
      await repo.deleteEvent(saved.id);
      await pumpEventQueue();
      expect(await repo.watchEvents().first, isEmpty);
    });
  }

  group('Calendar screen', () {
    late List<SkinManifest> skins;

    setUpAll(() async {
      skins = await loadTestSkins();
    });

    Future<ProviderContainer> openCalendar(
      WidgetTester tester, {
      Size size = const Size(400, 800),
      List<CalendarEvent> events = const [],
    }) async {
      final backend = InMemoryEventsBackend();
      await pumpApp(
        tester,
        skins,
        size: size,
        overrides: [
          todayProvider.overrideWithValue(today),
          eventsBackendProvider.overrideWithValue(backend),
        ],
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NotelyApp)),
      );
      for (final e in events) {
        await container.read(eventRepositoryProvider).saveEvent(e);
      }
      await tester.tap(find.text('Calendar').last);
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('a new event shows in the month and the day\'s agenda', (
      tester,
    ) async {
      await openCalendar(tester);
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('No events.'), findsOneWidget);

      await tester.tap(find.text('New event'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Dentist');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Dentist'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Wednesday, October 14, 2026, 1 event'),
        findsOneWidget,
      );
    });

    testWidgets('a weekly repeat fills the following weeks', (tester) async {
      await openCalendar(
        tester,
        events: [
          allDay(
            'Yoga',
            today,
            today,
            repeat: const Recurrence(Frequency.weekly),
          ),
        ],
      );
      for (final day in [14, 21, 28]) {
        expect(
          find.bySemanticsLabel(RegExp('October $day, 2026, 1 event')),
          findsOneWidget,
          reason: 'October $day',
        );
      }
      expect(
        find.bySemanticsLabel(RegExp('October 15, 2026, 0 events')),
        findsOneWidget,
      );
    });

    testWidgets('week and day views, and moving between weeks', (tester) async {
      await openCalendar(
        tester,
        size: const Size(1024, 900),
        events: [
          timed('Standup', DateTime(2026, 10, 14, 9), const Duration(hours: 1)),
        ],
      );
      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('^Standup, ')), findsOneWidget);

      await tester.tap(find.byTooltip('Next'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('^Standup')), findsNothing);

      await tester.tap(find.text('Today'));
      await tester.tap(find.text('Day'));
      await tester.pumpAndSettle();
      expect(find.text('Wednesday, October 14, 2026'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Standup, ')), findsOneWidget);
    });

    testWidgets('an event can be edited and deleted', (tester) async {
      await openCalendar(
        tester,
        events: [
          timed('Lunch', DateTime(2026, 10, 14, 12), const Duration(hours: 1)),
        ],
      );
      await tester.tap(find.text('Lunch'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Lunch with Kim');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Lunch with Kim'), findsOneWidget);

      await tester.tap(find.text('Lunch with Kim'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Delete event'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Delete event'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Lunch with Kim'), findsNothing);
      expect(find.text('No events.'), findsOneWidget);
    });
  });
}
