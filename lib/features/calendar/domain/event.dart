import 'package:flutter/foundation.dart';

import '../../../core/day.dart';
import 'calendar_info.dart';

export '../../../core/day.dart';
export 'calendar_info.dart';

enum Frequency { daily, weekly, monthly, yearly }

/// How an event repeats: a small part of iCalendar's RRULE. Each
/// occurrence keeps the first one's wall-clock time, even across daylight
/// saving changes.
@immutable
class Recurrence {
  const Recurrence(
    this.frequency, {
    this.interval = 1,
    this.weekdays = const {},
    this.until,
    this.count,
  });

  static Recurrence? fromMap(Object? map) {
    if (map is! Map) return null;
    final frequency = Frequency.values
        .where((f) => f.name == map['freq'])
        .firstOrNull;
    if (frequency == null) return null;
    final interval = map['interval'];
    final count = map['count'];
    return Recurrence(
      frequency,
      interval: interval is int && interval > 0 ? interval : 1,
      weekdays: {
        for (final d in map['weekdays'] as List? ?? const [])
          if (d is int && d >= DateTime.monday && d <= DateTime.sunday) d,
      },
      until: Day.tryParse(map['until']),
      count: count is int && count > 0 ? count : null,
    );
  }

  final Frequency frequency;

  /// Every [interval] days, weeks, months or years.
  final int interval;

  /// Weekly only: which days ([DateTime.monday] to [DateTime.sunday]).
  /// Empty means the first occurrence's weekday.
  final Set<int> weekdays;

  /// The last day an occurrence may start on.
  final Day? until;

  /// How many occurrences in all.
  final int? count;

  Map<String, Object?> toMap() => {
    'freq': frequency.name,
    'interval': interval,
    if (weekdays.isNotEmpty) 'weekdays': weekdays.toList()..sort(),
    'until': ?until?.toString(),
    'count': ?count,
  };

  Recurrence copyWith({
    Frequency? frequency,
    Set<int>? weekdays,
    Day? until,
    bool clearUntil = false,
  }) => Recurrence(
    frequency ?? this.frequency,
    interval: interval,
    weekdays: weekdays ?? this.weekdays,
    until: clearUntil ? null : until ?? this.until,
    count: count,
  );

  @override
  bool operator ==(Object other) =>
      other is Recurrence &&
      other.frequency == frequency &&
      other.interval == interval &&
      setEquals(other.weekdays, weekdays) &&
      other.until == until &&
      other.count == count;

  @override
  int get hashCode => Object.hash(
    frequency,
    interval,
    Object.hashAllUnordered(weekdays),
    until,
    count,
  );
}

/// Something on the calendar.
///
/// Timed events store `start` and `end` as milliseconds since the epoch.
/// All-day events store `startDay` and `endDay` (inclusive) as
/// "YYYY-MM-DD", so they fall on the same days in every time zone.
@immutable
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.color,
    this.calendarId = personalCalendarId,
    this.allDay = false,
    this.notes = '',
    this.recurrence,
    this.reminderMinutes = const [],
  });

  static CalendarEvent? fromMap(String id, Map<String, dynamic> map) {
    final allDay = map['allDay'] == true;
    DateTime? start;
    DateTime? end;
    if (allDay) {
      start = Day.tryParse(map['startDay'])?.toDateTime();
      end = Day.tryParse(map['endDay'])?.toDateTime() ?? start;
    } else if (map['start'] case final int s) {
      start = DateTime.fromMillisecondsSinceEpoch(s);
      end = switch (map['end']) {
        final int e when e >= s => DateTime.fromMillisecondsSinceEpoch(e),
        _ => start,
      };
    }
    if (start == null || end == null) return null;
    return CalendarEvent(
      id: id,
      title: map['title'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
      allDay: allDay,
      start: start,
      end: end.isBefore(start) ? start : end,
      color: switch (map['color']) {
        // Events saved before calendars had a colour each; the old default
        // now means "the calendar's colour" (Personal starts with it).
        final int c
            when !map.containsKey('calendarId') && _oldDefaults.contains(c) =>
          null,
        final int c => c,
        _ => null,
      },
      calendarId: map['calendarId'] as String? ?? personalCalendarId,
      recurrence: Recurrence.fromMap(map['recurrence']),
      reminderMinutes: [
        for (final m in map['reminderMinutes'] as List? ?? const [])
          if (m is int && m.abs() <= 60 * 24 * 28) m,
      ],
    );
  }

  /// The colour used when neither the event nor its calendar has one.
  static const defaultEventColor = 0xFF2C4A7C;

  /// Colours older versions gave every new event.
  static const _oldDefaults = {0xFF3F51B5, 0xFF2C4A7C};

  final String id;
  final String title;
  final String notes;
  final bool allDay;

  /// When it starts. All-day events: midnight of the first day.
  final DateTime start;

  /// When it ends. All-day events: midnight of the last day (inclusive).
  final DateTime end;

  /// Its own colour (ARGB), or null to use its calendar's.
  final int? color;

  /// The [CalendarInfo] it belongs to.
  final String calendarId;
  final Recurrence? recurrence;

  /// Minutes before the start to send reminders. For all-day events the
  /// start is midnight, so -540 is 9 AM on the day and 900 is 9 AM the day
  /// before.
  final List<int> reminderMinutes;

  Day get startDay => Day.of(start);
  Day get endDay => Day.of(end);

  Map<String, Object?> toMap() => {
    'title': title,
    'notes': notes,
    'allDay': allDay,
    if (allDay) ...{
      'startDay': startDay.toString(),
      'endDay': endDay.toString(),
    } else ...{
      'start': start.millisecondsSinceEpoch,
      'end': end.millisecondsSinceEpoch,
    },
    'color': ?color,
    'calendarId': calendarId,
    'recurrence': ?recurrence?.toMap(),
    if (reminderMinutes.isNotEmpty) 'reminderMinutes': reminderMinutes,
  };

  CalendarEvent copyWith({
    String? title,
    String? notes,
    bool? allDay,
    DateTime? start,
    DateTime? end,
    int? color,
    bool clearColor = false,
    String? calendarId,
    Recurrence? recurrence,
    bool clearRecurrence = false,
    List<int>? reminderMinutes,
  }) => CalendarEvent(
    id: id,
    title: title ?? this.title,
    notes: notes ?? this.notes,
    allDay: allDay ?? this.allDay,
    start: start ?? this.start,
    end: end ?? this.end,
    color: clearColor ? null : color ?? this.color,
    calendarId: calendarId ?? this.calendarId,
    recurrence: clearRecurrence ? null : recurrence ?? this.recurrence,
    reminderMinutes: reminderMinutes ?? this.reminderMinutes,
  );

  @override
  bool operator ==(Object other) =>
      other is CalendarEvent &&
      other.id == id &&
      other.title == title &&
      other.notes == notes &&
      other.allDay == allDay &&
      other.start == start &&
      other.end == end &&
      other.color == color &&
      other.calendarId == calendarId &&
      other.recurrence == recurrence &&
      listEquals(other.reminderMinutes, reminderMinutes);

  @override
  int get hashCode => Object.hash(
    id,
    title,
    notes,
    allDay,
    start,
    end,
    color,
    calendarId,
    recurrence,
    Object.hashAll(reminderMinutes),
  );
}

/// One time an event happens.
@immutable
class Occurrence {
  const Occurrence(this.event, this.start, this.end, {this.calendarColor});

  final CalendarEvent event;

  /// Its calendar's colour, when known (see [withColor]).
  final int? calendarColor;

  /// The colour to draw it in: the event's own, else its calendar's, else
  /// the default.
  int get color =>
      event.color ?? calendarColor ?? CalendarEvent.defaultEventColor;

  /// This occurrence drawn in [calendarColor] unless the event has its own.
  Occurrence withColor(int calendarColor) =>
      Occurrence(event, start, end, calendarColor: calendarColor);
  final DateTime start;

  /// For all-day events, midnight of the last day (inclusive).
  final DateTime end;

  bool get allDay => event.allDay;

  /// Whether any part of it falls on [day].
  bool isOn(Day day) {
    if (allDay) {
      return !Day.of(start).isAfter(day) && !Day.of(end).isBefore(day);
    }
    final dayStart = day.toDateTime();
    final dayEnd = day.addDays(1).toDateTime();
    if (start == end) {
      return !start.isBefore(dayStart) && start.isBefore(dayEnd);
    }
    return start.isBefore(dayEnd) && end.isAfter(dayStart);
  }

  @override
  bool operator ==(Object other) =>
      other is Occurrence &&
      other.event.id == event.id &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(event.id, start, end);
}

/// Stops runaway expansion of a rule with no end.
const _maxSteps = 20000;

/// The days [event] starts on, from its first day on, in order.
Iterable<Day> _startDays(CalendarEvent event) sync* {
  final rule = event.recurrence;
  final first = event.startDay;
  if (rule == null) {
    yield first;
    return;
  }
  var produced = 0;
  bool allowed(Day d) =>
      (rule.until == null || !d.isAfter(rule.until!)) &&
      (rule.count == null || produced < rule.count!);

  switch (rule.frequency) {
    case Frequency.daily:
      for (var k = 0; k < _maxSteps; k++) {
        final d = first.addDays(k * rule.interval);
        if (!allowed(d)) return;
        produced++;
        yield d;
      }
    case Frequency.weekly:
      final days = rule.weekdays.isEmpty
          ? [first.weekday]
          : (rule.weekdays.toList()..sort());
      // Weeks start on Monday for counting the interval.
      final weekStart = first.addDays(1 - first.weekday);
      for (var w = 0; w < _maxSteps; w++) {
        final monday = weekStart.addDays(7 * w * rule.interval);
        for (final wd in days) {
          final d = monday.addDays(wd - 1);
          if (d.isBefore(first)) continue;
          if (!allowed(d)) return;
          produced++;
          yield d;
        }
      }
    case Frequency.monthly:
    case Frequency.yearly:
      final months = rule.frequency == Frequency.monthly ? 1 : 12;
      for (var k = 0; k < _maxSteps; k++) {
        final m = first.month - 1 + k * rule.interval * months;
        final year = first.year + m ~/ 12;
        final month = m % 12 + 1;
        final d = Day.tryParse(
          Day(year, month, first.day).toString(),
        ); // null when the month has no such day (e.g. the 31st)
        if (rule.until != null && Day(year, month, 1).isAfter(rule.until!)) {
          return;
        }
        if (d == null) continue;
        if (!allowed(d)) return;
        produced++;
        yield d;
      }
  }
}

/// Every occurrence of [events] that touches the days [from] to [to]
/// (inclusive), sorted by start.
List<Occurrence> occurrencesBetween(
  Iterable<CalendarEvent> events,
  Day from,
  Day to,
) {
  final result = <Occurrence>[];
  for (final e in events) {
    final length = e.end.difference(e.start);
    final spanDays = e.startDay.daysUntil(e.endDay);
    for (final day in _startDays(e)) {
      if (day.isAfter(to)) break;
      // Quick skip of occurrences that end well before the range.
      if (day.addDays(spanDays + 1).isBefore(from)) continue;
      final DateTime start;
      final DateTime end;
      if (e.allDay) {
        start = day.toDateTime();
        end = day.addDays(spanDays).toDateTime();
      } else {
        // Same wall-clock time on every occurrence.
        start = DateTime(
          day.year,
          day.month,
          day.day,
          e.start.hour,
          e.start.minute,
        );
        end = start.add(length);
      }
      final o = Occurrence(e, start, end);
      // Days of the range it may fall on; isOn() rules out a timed event
      // that only touches midnight.
      var d = Day.of(start).isBefore(from) ? from : Day.of(start);
      final last = Day.of(end).isAfter(to) ? to : Day.of(end);
      for (; !d.isAfter(last); d = d.addDays(1)) {
        if (o.isOn(d)) {
          result.add(o);
          break;
        }
      }
    }
  }
  result.sort((a, b) {
    if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
    final s = a.start.compareTo(b.start);
    return s != 0 ? s : b.end.compareTo(a.end);
  });
  return result;
}
