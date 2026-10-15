import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notebooks/notes_providers.dart' show currentUidProvider;
import '../tasks/task_providers.dart' show todayProvider;
import 'data/calendar_repository.dart';
import 'data/event_repository.dart';
import 'domain/event.dart';

/// Overridden in `main()` with Firestore when Firebase is set up.
final eventsBackendProvider = Provider<EventsBackend>(
  (ref) => InMemoryEventsBackend(),
);

final eventRepositoryProvider = Provider<EventRepository>(
  (ref) =>
      ref.watch(eventsBackendProvider).events(ref.watch(currentUidProvider)),
);

final eventsProvider = StreamProvider<List<CalendarEvent>>(
  (ref) => ref.watch(eventRepositoryProvider).watchEvents(),
);

/// Overridden in `main()` with Firestore when Firebase is set up.
final calendarsBackendProvider = Provider<CalendarsBackend>(
  (ref) => InMemoryCalendarsBackend(),
);

final calendarRepositoryProvider = Provider<CalendarRepository>(
  (ref) => ref
      .watch(calendarsBackendProvider)
      .calendars(ref.watch(currentUidProvider)),
);

/// Every calendar, Personal first, in order.
final calendarsProvider = StreamProvider<List<CalendarInfo>>(
  (ref) => ref.watch(calendarRepositoryProvider).watchCalendars(),
);

/// Calendars by id, with Personal always present.
final calendarsByIdProvider = Provider<Map<String, CalendarInfo>>((ref) {
  final list = ref.watch(calendarsProvider).value ?? const [];
  return {
    personalCalendarId: CalendarInfo.personal,
    for (final c in list) c.id: c,
  };
});

/// The calendar [event] shows in: its own, or Personal if that was
/// deleted.
CalendarInfo calendarOf(Map<String, CalendarInfo> byId, CalendarEvent event) =>
    byId[event.calendarId] ?? byId[personalCalendarId]!;

/// The occurrences touching the days `from` to `to` (inclusive) from
/// calendars that are shown, each in its calendar's colour unless the
/// event has its own.
final occurrencesProvider =
    Provider.family<List<Occurrence>, ({Day from, Day to})>((ref, range) {
      final byId = ref.watch(calendarsByIdProvider);
      return [
        for (final o in occurrencesBetween(
          ref.watch(eventsProvider).value ?? const [],
          range.from,
          range.to,
        ))
          if (calendarOf(byId, o.event) case final c when c.visible)
            o.withColor(c.color),
      ];
    });

/// Deletes [calendar], moving its events to Personal or deleting them
/// ([deleteEvents]). Personal can't be deleted.
Future<void> deleteCalendar(
  WidgetRef ref,
  CalendarInfo calendar, {
  required bool deleteEvents,
}) async {
  if (calendar.id == personalCalendarId) return;
  final events = ref.read(eventRepositoryProvider);
  for (final e in ref.read(eventsProvider).value ?? const <CalendarEvent>[]) {
    if (e.calendarId != calendar.id) continue;
    if (deleteEvents) {
      await events.deleteEvent(e.id);
    } else {
      await events.saveEvent(e.copyWith(calendarId: personalCalendarId));
    }
  }
  await ref.read(calendarRepositoryProvider).deleteCalendar(calendar.id);
}

enum CalendarMode { month, week, day }

/// What the Calendar tab shows: a mode and the chosen day.
typedef CalendarState = ({CalendarMode mode, Day day});

class CalendarController extends Notifier<CalendarState> {
  @override
  CalendarState build() =>
      (mode: CalendarMode.month, day: ref.read(todayProvider));

  void setMode(CalendarMode mode) => state = (mode: mode, day: state.day);

  void select(Day day) => state = (mode: state.mode, day: day);

  /// Shows [day] in the day view.
  void openDay(Day day) => state = (mode: CalendarMode.day, day: day);

  void today() => select(ref.read(todayProvider));

  /// Moves a month, week or day forward ([step] 1) or back (-1).
  void move(int step) {
    final d = state.day;
    select(switch (state.mode) {
      CalendarMode.month => _addMonths(d, step),
      CalendarMode.week => d.addDays(7 * step),
      CalendarMode.day => d.addDays(step),
    });
  }

  static Day _addMonths(Day d, int months) {
    final m = d.month - 1 + months;
    final year = d.year + (m / 12).floor();
    final month = m % 12 + 1;
    // Keep the day of the month where possible (Jan 31 -> Feb 28).
    final daysInMonth = DateTime(year, month + 1, 0).day;
    return Day(year, month, min(d.day, daysInMonth));
  }
}

final calendarProvider = NotifierProvider<CalendarController, CalendarState>(
  CalendarController.new,
);

/// The first day of the week containing [day], with weeks starting on
/// [firstWeekday] (0 Sunday, 1 Monday, ... as in MaterialLocalizations).
Day startOfWeek(Day day, int firstWeekday) {
  final weekday = day.weekday % 7; // Sunday 0
  return day.addDays(-((weekday - firstWeekday) % 7));
}
