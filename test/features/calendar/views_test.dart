import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/app/app.dart';
import 'package:notely/core/motion/directional_switcher.dart';
import 'package:notely/core/motion/period_transition.dart';
import 'package:notely/core/settings/synced_setting.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/calendar/calendar_providers.dart';
import 'package:notely/features/calendar/data/event_repository.dart';
import 'package:notely/features/calendar/domain/event.dart';
import 'package:notely/features/calendar/views/agenda_view.dart';
import 'package:notely/features/calendar/views/month_view.dart';
import 'package:notely/features/tasks/task_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// A Wednesday.
const today = Day(2026, 10, 14);

CalendarEvent allDay(String title, Day from, [Day? to, Recurrence? repeat]) =>
    CalendarEvent(
      id: title,
      title: title,
      allDay: true,
      start: from.toDateTime(),
      end: (to ?? from).toDateTime(),
      recurrence: repeat,
    );

void main() {
  group('moving', () {
    Future<ProviderContainer> container() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          todayProvider.overrideWithValue(today),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('each view moves by its own step', () async {
      final c = await container();
      final calendar = c.read(calendarProvider.notifier);
      final steps = {
        CalendarMode.year: const Day(2027, 10, 14),
        CalendarMode.month: const Day(2026, 11, 14),
        CalendarMode.week: const Day(2026, 10, 21),
        CalendarMode.threeDay: const Day(2026, 10, 17),
        CalendarMode.day: const Day(2026, 10, 15),
      };
      for (final MapEntry(key: mode, value: next) in steps.entries) {
        calendar
          ..setMode(mode)
          ..today()
          ..move(1);
        expect(c.read(calendarProvider).day, next, reason: '$mode');
      }
    });

    test('the last view is remembered on the device', () async {
      final c = await container();
      c.read(calendarProvider.notifier).setMode(CalendarMode.agenda);
      final again = ProviderContainer(
        overrides: [
          todayProvider.overrideWithValue(today),
          sharedPreferencesProvider.overrideWithValue(
            c.read(sharedPreferencesProvider),
          ),
        ],
      );
      addTearDown(again.dispose);
      expect(again.read(calendarProvider).mode, CalendarMode.agenda);
    });
  });

  test('the agenda groups days, repeats and long events', () {
    final events = [
      allDay('Trip', const Day(2026, 10, 14), const Day(2026, 10, 16)),
      allDay(
        'Gym',
        const Day(2026, 10, 15),
        null,
        const Recurrence(Frequency.weekly),
      ),
    ];
    const from = Day(2026, 10, 14);
    const to = Day(2026, 10, 31);
    final byDay = groupByDay(occurrencesBetween(events, from, to), from, to);
    String titles(Day d) => byDay[d]!.map((o) => o.event.title).join(',');
    expect(byDay.keys.first, from);
    expect(titles(const Day(2026, 10, 15)), 'Trip,Gym');
    expect(titles(const Day(2026, 10, 16)), 'Trip');
    expect(titles(const Day(2026, 10, 22)), 'Gym');
    expect(byDay.containsKey(const Day(2026, 10, 17)), isFalse);
  });

  group('Calendar screen', () {
    late List<SkinManifest> skins;

    setUpAll(() async {
      skins = await loadTestSkins();
    });

    Future<void> open(
      WidgetTester tester, {
      Size size = const Size(1024, 900),
      List<CalendarEvent> events = const [],
    }) async {
      await pumpApp(
        tester,
        skins,
        size: size,
        overrides: [
          todayProvider.overrideWithValue(today),
          eventsBackendProvider.overrideWithValue(InMemoryEventsBackend()),
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
    }

    testWidgets('the year shows twelve months; a month opens it', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Year'));
      await tester.pumpAndSettle();
      expect(find.text('2026'), findsWidgets);
      expect(find.bySemanticsLabel('March 2026'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('March 2026'));
      await tester.pumpAndSettle();
      expect(find.text('March 2026'), findsOneWidget);
    });

    testWidgets('three days side by side', (tester) async {
      await open(
        tester,
        events: [
          CalendarEvent(
            id: 'x',
            title: 'Lunch',
            start: DateTime(2026, 10, 16, 12),
            end: DateTime(2026, 10, 16, 13),
          ),
        ],
      );
      await tester.tap(find.text('3 days'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('^Lunch')), findsOneWidget);
      await tester.tap(find.byTooltip('Next'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('^Lunch')), findsNothing);
    });

    testWidgets('the agenda lists days with events and the gaps', (
      tester,
    ) async {
      await open(
        tester,
        size: const Size(400, 800),
        events: [
          allDay('Dentist', today),
          allDay('Party', const Day(2026, 10, 20)),
          allDay('Past', const Day(2026, 10, 1)),
        ],
      );
      await tester.tap(find.byTooltip('View'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agenda'));
      await tester.pumpAndSettle();

      expect(find.text('Today · Wed, Oct 14'), findsOneWidget);
      expect(find.text('Dentist'), findsOneWidget);
      expect(find.text('No events · Oct 15 – Oct 19'), findsOneWidget);
      expect(find.text('Party'), findsOneWidget);
      // Earlier days are above, off screen until scrolled to.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(find.text('Past'), findsOneWidget);
    });

    testWidgets('tapping the chosen day zooms in; zoom out goes back up', (
      tester,
    ) async {
      await open(tester);
      // Today is chosen; a second tap opens it.
      await tester.tap(
        find.bySemanticsLabel('Wednesday, October 14, 2026, 0 events'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Wednesday, October 14, 2026'), findsOneWidget);

      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);
      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pumpAndSettle();
      expect(find.text('2026'), findsWidgets);
      expect(find.byTooltip('Zoom out'), findsNothing);
    });

    testWidgets('spreading two fingers zooms from the year into a month', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Year'));
      await tester.pumpAndSettle();
      final center = tester.getCenter(find.byType(GridView));
      final a = await tester.startGesture(center - const Offset(20, 0));
      final b = await tester.startGesture(
        center + const Offset(20, 0),
        pointer: 2,
      );
      for (var i = 1; i <= 5; i++) {
        await a.moveTo(center - Offset(20.0 + i * 20, 0));
        await b.moveTo(center + Offset(20.0 + i * 20, 0));
      }
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);
    });

    testWidgets('months use the chosen animation; weeks slide', (tester) async {
      await open(tester);
      PeriodAnimation monthAnimation() => tester
          .widget<PeriodTransition<Day>>(find.byType(PeriodTransition<Day>))
          .animation;
      expect(monthAnimation(), PeriodAnimation.slide, reason: "Classic's");

      final container = ProviderScope.containerOf(
        tester.element(find.byType(NotelyApp)),
      );
      await container
          .read(monthAnimationSettingProvider.notifier)
          .set(PeriodAnimation.wallFlip);
      await tester.pumpAndSettle();
      expect(monthAnimation(), PeriodAnimation.wallFlip);

      await tester.tap(find.byTooltip('Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(MonthView), findsNWidgets(2), reason: 'flipping');
      await tester.pumpAndSettle();
      expect(find.text('November 2026'), findsOneWidget);
      expect(find.byType(MonthView), findsOneWidget);

      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();
      expect(find.byType(PeriodTransition<Day>), findsNothing);
      expect(find.byType(DirectionalSwitcher<Day>), findsOneWidget);
    });
  });
}
