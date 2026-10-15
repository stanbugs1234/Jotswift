import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tasks/task_providers.dart' show todayProvider;
import 'calendar_providers.dart';
import 'domain/event.dart';
import 'event_editor.dart';

/// Where a timed occurrence sits in a day column: minutes from midnight,
/// and its column among events that overlap it.
typedef EventSlot = ({
  Occurrence occurrence,
  double top,
  double bottom,
  int column,
  int columns,
});

/// Lays out [day]'s timed occurrences side by side where they overlap.
List<EventSlot> layoutDay(Iterable<Occurrence> occurrences, Day day) {
  final dayStart = day.toDateTime();
  final items = <(Occurrence, double, double)>[];
  for (final o in occurrences) {
    if (o.allDay || !o.isOn(day)) continue;
    final top = max(0, o.start.difference(dayStart).inMinutes).toDouble();
    var bottom = min(24 * 60, o.end.difference(dayStart).inMinutes).toDouble();
    // Short events still get room for a line of text.
    bottom = max(bottom, min(24 * 60, top + 20));
    items.add((o, top, bottom));
  }
  items.sort((a, b) {
    final t = a.$2.compareTo(b.$2);
    return t != 0 ? t : b.$3.compareTo(a.$3);
  });

  final slots = <EventSlot>[];
  // Events in one cluster overlap each other directly or through others.
  var cluster = <(Occurrence, double, double, int)>[];
  var clusterEnd = -1.0;
  void flush() {
    final columns = cluster.fold(0, (n, c) => max(n, c.$4 + 1));
    for (final (o, top, bottom, column) in cluster) {
      slots.add((
        occurrence: o,
        top: top,
        bottom: bottom,
        column: column,
        columns: columns,
      ));
    }
    cluster = [];
  }

  for (final (o, top, bottom) in items) {
    if (top >= clusterEnd) flush();
    // The first column whose last event has ended.
    var column = 0;
    while (cluster.any((c) => c.$4 == column && c.$3 > top)) {
      column++;
    }
    cluster.add((o, top, bottom, column));
    clusterEnd = max(clusterEnd, bottom);
  }
  flush();
  return slots;
}

/// Hour rows for [days] (one day or a week): an all-day row, then events
/// placed by time. Tapping an empty hour adds an event there.
class TimeGrid extends ConsumerStatefulWidget {
  const TimeGrid({required this.days, super.key});

  final List<Day> days;

  static const hourHeight = 56.0;
  static const gutter = 52.0;

  @override
  ConsumerState<TimeGrid> createState() => _TimeGridState();
}

class _TimeGridState extends ConsumerState<TimeGrid> {
  // Opens at 7 am.
  final _scroll = ScrollController(
    initialScrollOffset: 7 * TimeGrid.hourHeight,
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final local = MaterialLocalizations.of(context);
    final days = widget.days;
    final today = ref.watch(todayProvider);
    final occurrences = ref.watch(
      occurrencesProvider((from: days.first, to: days.last)),
    );
    final allDay = [
      for (final o in occurrences)
        if (o.allDay) o,
    ];

    Widget dayHeader(Day day) {
      final isToday = day == today;
      return Expanded(
        child: InkWell(
          onTap: days.length == 1
              ? null
              : () => ref.read(calendarProvider.notifier).openDay(day),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Text(
                  local.narrowWeekdays[day.weekday % 7],
                  style: theme.textTheme.labelSmall,
                ),
                CircleAvatar(
                  radius: 15,
                  backgroundColor: isToday
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      color: isToday ? theme.colorScheme.onPrimary : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: TimeGrid.gutter),
            for (final d in days) dayHeader(d),
          ],
        ),
        if (allDay.isNotEmpty)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: TimeGrid.gutter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4),
                  child: Text('all-day', style: theme.textTheme.labelSmall),
                ),
              ),
              for (final d in days)
                Expanded(
                  child: Column(
                    children: [
                      for (final o in allDay)
                        if (o.isOn(d)) _EventBox(occurrence: o, compact: true),
                    ],
                  ),
                ),
            ],
          ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            child: SizedBox(
              height: 24 * TimeGrid.hourHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: TimeGrid.gutter,
                    child: Stack(
                      children: [
                        for (var h = 1; h < 24; h++)
                          Positioned(
                            top: h * TimeGrid.hourHeight - 7,
                            right: 6,
                            child: Text(
                              local.formatTimeOfDay(
                                TimeOfDay(hour: h, minute: 0),
                              ),
                              style: theme.textTheme.labelSmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (final d in days)
                    Expanded(
                      child: _DayColumn(
                        day: d,
                        slots: layoutDay(occurrences, d),
                        isToday: d == today,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.day,
    required this.slots,
    required this.isToday,
  });

  final Day day;
  final List<EventSlot> slots;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const perMinute = TimeGrid.hourHeight / 60;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final now = DateTime.now();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // An empty spot: a new hour-long event starting on that hour.
          onTapUp: (details) {
            final hour = (details.localPosition.dy / TimeGrid.hourHeight)
                .floor()
                .clamp(0, 23);
            showEventEditor(
              context,
              start: DateTime(day.year, day.month, day.day, hour),
            );
          },
          child: Stack(
            children: [
              for (var h = 0; h < 24; h++)
                Positioned(
                  top: h * TimeGrid.hourHeight,
                  left: 0,
                  right: 0,
                  child: Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                child: VerticalDivider(
                  width: 1,
                  color: theme.colorScheme.outlineVariant,
                ),
              ),
              for (final s in slots)
                Positioned(
                  top: s.top * perMinute,
                  height: (s.bottom - s.top) * perMinute,
                  left: width * s.column / s.columns + 1,
                  width: width / s.columns - 2,
                  child: _EventBox(occurrence: s.occurrence),
                ),
              if (isToday)
                Positioned(
                  top: (now.hour * 60 + now.minute) * perMinute,
                  left: 0,
                  right: 0,
                  child: Container(height: 2, color: theme.colorScheme.error),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// An event on the grid; tap to edit.
class _EventBox extends StatelessWidget {
  const _EventBox({required this.occurrence, this.compact = false});

  final Occurrence occurrence;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final event = occurrence.event;
    final color = Color(occurrence.color);
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;
    final local = MaterialLocalizations.of(context);
    final time = occurrence.allDay
        ? null
        : local.formatTimeOfDay(TimeOfDay.fromDateTime(occurrence.start));
    return Semantics(
      button: true,
      label: [event.title, ?time].join(', '),
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.only(bottom: compact ? 2 : 0),
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(4),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => showEventEditor(context, event: event),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  [event.title, if (!compact) ?time].join('\n'),
                  overflow: TextOverflow.fade,
                  style: TextStyle(color: onColor, fontSize: 12),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
