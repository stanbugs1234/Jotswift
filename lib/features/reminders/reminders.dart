import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../calendar/calendar_providers.dart';
import '../calendar/domain/event.dart';
import '../tasks/domain/task.dart';
import '../tasks/task_providers.dart';

/// One notification to show at [at].
@immutable
class Reminder {
  const Reminder({
    required this.key,
    required this.title,
    required this.body,
    required this.at,
    required this.day,
  });

  /// Says what it's for, such as "task:abc" or "event:xyz@...".
  final String key;
  final String title;
  final String body;
  final DateTime at;

  /// The day it's about; tapping the notification opens it in the Planner.
  final Day day;

  /// A stable notification id for [key] (FNV-1a, 31 bits).
  int get id {
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }

  @override
  bool operator ==(Object other) =>
      other is Reminder &&
      other.key == key &&
      other.title == title &&
      other.body == body &&
      other.at == at;

  @override
  int get hashCode => Object.hash(key, title, body, at);
}

/// iOS keeps at most 64 pending notifications; leave room.
const maxReminders = 60;

/// The reminders due after [now] and within [horizon], soonest first,
/// at most [maxReminders]. The app reschedules whenever tasks or events
/// change and each time it starts, so a short horizon is enough.
List<Reminder> upcomingReminders({
  required Iterable<Task> tasks,
  required Iterable<CalendarEvent> events,
  required DateTime now,
  required String Function(DateTime) formatTime,
  Duration horizon = const Duration(days: 14),
}) {
  final end = now.add(horizon);
  bool inWindow(DateTime t) => t.isAfter(now) && !t.isAfter(end);
  final result = <Reminder>[];

  for (final t in tasks) {
    final at = t.reminderTime;
    if (t.done || at == null || !inWindow(at)) continue;
    result.add(
      Reminder(
        key: 'task:${t.id}',
        title: t.title,
        body: 'To-do',
        at: at,
        day: t.due!,
      ),
    );
  }

  // Occurrences can be reminded up to a few days ahead of their start.
  final withReminders = [
    for (final e in events)
      if (e.reminderMinutes.isNotEmpty) e,
  ];
  if (withReminders.isNotEmpty) {
    final lead = withReminders
        .expand((e) => e.reminderMinutes)
        .fold(0, (a, b) => a > b ? a : b);
    for (final o in occurrencesBetween(
      withReminders,
      Day.of(now),
      Day.of(end.add(Duration(minutes: lead))),
    )) {
      for (final minutes in o.event.reminderMinutes) {
        final at = o.start.subtract(Duration(minutes: minutes));
        if (!inWindow(at)) continue;
        result.add(
          Reminder(
            key: 'event:${o.event.id}@${o.start.toIso8601String()}/$minutes',
            title: o.event.title,
            body: o.allDay
                ? 'All day'
                : '${formatTime(o.start)} – ${formatTime(o.end)}',
            at: at,
            day: Day.of(o.start),
          ),
        );
      }
    }
  }

  result.sort((a, b) => a.at.compareTo(b.at));
  return result.take(maxReminders).toList();
}

/// Shows reminders as local notifications.
abstract interface class ReminderService {
  /// Asks to show notifications (once; later calls return the answer).
  Future<bool> requestPermission();

  /// Replaces every scheduled reminder with [reminders].
  Future<void> schedule(List<Reminder> reminders);

  /// Days whose reminder was tapped (including the one that opened the
  /// app).
  Stream<Day> get taps;
}

/// No notifications: the web, tests, and platforms without support.
class NoReminders implements ReminderService {
  const NoReminders();

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> schedule(List<Reminder> reminders) async {}

  @override
  Stream<Day> get taps => const Stream.empty();
}

/// Overridden in `main()` on iOS and Android.
final reminderServiceProvider = Provider<ReminderService>(
  (ref) => const NoReminders(),
);

/// How times read in notification text, such as "9:30 AM".
final reminderTimeFormatProvider = Provider<String Function(DateTime)>(
  (ref) => (t) {
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${t.hour < 12 ? 'AM' : 'PM'}';
  },
);

/// Keeps scheduled reminders matching the user's tasks and events while
/// signed in. Watched by the app shell.
final reminderSyncProvider = Provider<void>((ref) {
  final service = ref.watch(reminderServiceProvider);
  // Nothing to keep in sync without notifications (web, tests).
  if (service is NoReminders) return;
  Timer? pending;
  List<Reminder>? last;

  void reschedule() {
    pending?.cancel();
    // Several changes in a row (a sync burst) schedule once.
    pending = Timer(const Duration(milliseconds: 500), () {
      final tasks = ref.read(tasksProvider).value;
      final events = ref.read(eventsProvider).value;
      if (tasks == null || events == null) return;
      final next = upcomingReminders(
        tasks: tasks,
        events: events,
        now: DateTime.now(),
        formatTime: ref.read(reminderTimeFormatProvider),
      );
      if (last != null && listEquals(last, next)) return;
      last = next;
      service.schedule(next);
    });
  }

  ref.listen(tasksProvider, (_, _) => reschedule(), fireImmediately: true);
  ref.listen(eventsProvider, (_, _) => reschedule(), fireImmediately: true);
  ref.onDispose(() {
    pending?.cancel();
    // Signed out: no reminders for the old account.
    service.schedule(const []);
  });
});

/// Taps on reminders, as the day to open.
final reminderTapsProvider = StreamProvider<Day>(
  (ref) => ref.watch(reminderServiceProvider).taps,
);
