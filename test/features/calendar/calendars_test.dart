import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/app/app.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/calendar/calendar_providers.dart';
import 'package:notely/features/calendar/data/calendar_repository.dart';
import 'package:notely/features/calendar/data/event_repository.dart';
import 'package:notely/features/calendar/domain/event.dart';
import 'package:notely/features/tasks/task_providers.dart';

import '../../helpers.dart';

/// A Wednesday.
const today = Day(2026, 10, 14);

CalendarEvent event(String title, {String calendar = personalCalendarId}) =>
    CalendarEvent(
      id: title,
      title: title,
      allDay: true,
      start: today.toDateTime(),
      end: today.toDateTime(),
      calendarId: calendar,
    );

const work = CalendarInfo(id: 'work', name: 'Work', color: 0xFF1F8A99);

/// On phones the Calendars sheet is in the More menu.
Future<void> openCalendarsSheet(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Calendars'));
  await tester.pumpAndSettle();
}

void main() {
  group('saved events', () {
    test('older events keep their own colour unless it was the default', () {
      final old = CalendarEvent.fromMap('a', {
        'title': 'a',
        'allDay': true,
        'startDay': '2026-10-14',
        'color': 0xFF3F51B5,
      })!;
      expect(old.color, isNull, reason: 'the old default follows Personal');
      expect(old.calendarId, personalCalendarId);

      final brick = CalendarEvent.fromMap('b', {
        'title': 'b',
        'allDay': true,
        'startDay': '2026-10-14',
        'color': 0xFFC8553D,
      })!;
      expect(brick.color, 0xFFC8553D);
    });

    test('an event without its own colour saves none', () {
      final map = event('x', calendar: 'work').toMap();
      expect(map.containsKey('color'), isFalse);
      expect(map['calendarId'], 'work');
      expect(CalendarEvent.fromMap('x', map), event('x', calendar: 'work'));
    });
  });

  for (final (name, make) in <(String, CalendarsBackend Function())>[
    ('in memory', InMemoryCalendarsBackend.new),
    ('Firestore', () => FirestoreCalendarsBackend(FakeFirebaseFirestore())),
  ]) {
    test('$name: Personal is always there, others are saved', () async {
      final repo = make().calendars('sam');
      expect((await repo.watchCalendars().first).map((c) => c.name), [
        'Personal',
      ]);
      final saved = await repo.saveCalendar(
        const CalendarInfo(id: '', name: 'Work', color: 0xFF1F8A99, order: 1),
      );
      await pumpEventQueue();
      final list = await repo.watchCalendars().first;
      expect(list.map((c) => c.name), ['Personal', 'Work']);
      expect(list.last, saved);
      await repo.deleteCalendar(saved.id);
      await pumpEventQueue();
      expect(await repo.watchCalendars().first, [CalendarInfo.personal]);
    });
  }

  group('Calendar screen', () {
    late List<SkinManifest> skins;

    setUpAll(() async {
      skins = await loadTestSkins();
    });

    Future<ProviderContainer> openCalendar(
      WidgetTester tester, {
      List<CalendarInfo> calendars = const [],
      List<CalendarEvent> events = const [],
      Size size = const Size(400, 800),
    }) async {
      await pumpApp(
        tester,
        skins,
        size: size,
        overrides: [
          todayProvider.overrideWithValue(today),
          eventsBackendProvider.overrideWithValue(InMemoryEventsBackend()),
          calendarsBackendProvider.overrideWithValue(
            InMemoryCalendarsBackend(),
          ),
        ],
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NotelyApp)),
      );
      for (final c in calendars) {
        await container.read(calendarRepositoryProvider).saveCalendar(c);
      }
      for (final e in events) {
        await container.read(eventRepositoryProvider).saveEvent(e);
      }
      await tester.tap(find.text('Calendar').last);
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('events take their calendar\'s colour; hidden ones vanish', (
      tester,
    ) async {
      final container = await openCalendar(
        tester,
        calendars: [work],
        events: [
          event('Standup', calendar: 'work'),
          event('Dentist'),
        ],
      );
      final shown = container.read(
        occurrencesProvider((from: today, to: today)),
      );
      expect(
        {for (final o in shown) o.event.title: o.color},
        {'Standup': work.color, 'Dentist': CalendarInfo.personal.color},
      );
      expect(find.text('Standup'), findsOneWidget);

      await openCalendarsSheet(tester);
      await tester.tap(find.bySemanticsLabel('Show Work'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(200, 40)); // close the sheet
      await tester.pumpAndSettle();

      expect(find.text('Standup'), findsNothing);
      expect(find.text('Dentist'), findsOneWidget);
    });

    testWidgets('a calendar is added from a suggestion', (tester) async {
      final container = await openCalendar(tester);
      await openCalendarsSheet(tester);
      await tester.tap(find.text('New calendar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Family'));
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      final names = container
          .read(calendarsProvider)
          .value!
          .map((c) => c.name)
          .toList();
      expect(names, ['Personal', 'Family']);
      expect(find.text('Family'), findsOneWidget);
    });

    testWidgets('a new event can go in another calendar', (tester) async {
      final container = await openCalendar(tester, calendars: [work]);
      await tester.tap(find.text('New event'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Review');
      await tester.ensureVisible(find.text('Personal'));
      await tester.tap(find.text('Personal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Work').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = container.read(eventsProvider).value!.single;
      expect(saved.calendarId, 'work');
      expect(saved.color, isNull, reason: 'uses the calendar\'s colour');
    });

    testWidgets('deleting a calendar can keep its events in Personal', (
      tester,
    ) async {
      final container = await openCalendar(
        tester,
        calendars: [work],
        events: [event('Standup', calendar: 'work')],
      );
      await openCalendarsSheet(tester);
      await tester.tap(find.byTooltip('Edit Work'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to Personal'));
      await tester.pumpAndSettle();

      expect(container.read(calendarsProvider).value, [CalendarInfo.personal]);
      expect(
        container.read(eventsProvider).value!.single.calendarId,
        personalCalendarId,
      );
    });

    testWidgets('wide screens keep the calendars beside the calendar', (
      tester,
    ) async {
      await openCalendar(tester, size: const Size(1400, 900));
      expect(find.text('Calendars'), findsOneWidget);
      expect(find.byTooltip('Calendars'), findsNothing);
      expect(find.byTooltip('More'), findsNothing);
    });
  });
}
