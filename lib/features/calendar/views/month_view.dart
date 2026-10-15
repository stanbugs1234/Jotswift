import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../planner/planner_screen.dart' show openPlannerDay;
import '../../tasks/task_providers.dart' show todayProvider;
import '../calendar_providers.dart';
import '../domain/event.dart';
import '../event_editor.dart';
import '../templates/calendar_look.dart';
import '../templates/calendar_template.dart';

/// A month grid with the chosen day's events beside it (wide) or below.
class MonthView extends ConsumerWidget {
  const MonthView({required this.focus, super.key});

  final Day focus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = MaterialLocalizations.of(context);
    final first = startOfWeek(focus.firstOfMonth, local.firstDayOfWeekIndex);
    final days = [for (var i = 0; i < 42; i++) first.addDays(i)];
    final occurrences = ref.watch(
      occurrencesProvider((from: days.first, to: days.last)),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        final look = CalendarLook.of(context);
        final grid = Column(
          children: [
            if (look.bigMonthNumber) _BigMonthHeading(month: focus),
            Expanded(
              child: _MonthGrid(
                focus: focus,
                days: days,
                occurrences: occurrences,
                showTitles: constraints.maxWidth >= 600,
              ),
            ),
          ],
        );
        final agenda = _Agenda(
          day: focus,
          occurrences: [
            for (final o in occurrences)
              if (o.isOn(focus)) o,
          ],
        );
        if (wide) {
          return Row(
            children: [
              Expanded(child: grid),
              const VerticalDivider(width: 1),
              SizedBox(width: 320, child: agenda),
            ],
          );
        }
        return Column(
          children: [
            Expanded(flex: 3, child: grid),
            const Divider(height: 1),
            Expanded(flex: 2, child: agenda),
          ],
        );
      },
    );
  }
}

class _MonthGrid extends ConsumerWidget {
  const _MonthGrid({
    required this.focus,
    required this.days,
    required this.occurrences,
    required this.showTitles,
  });

  final Day focus;
  final List<Day> days;
  final List<Occurrence> occurrences;

  /// Event titles in the cells (tablets); dots otherwise.
  final bool showTitles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final local = MaterialLocalizations.of(context);
    final today = ref.watch(todayProvider);
    final look = CalendarLook.of(context);

    Widget cell(Day day) {
      final weekend = day.weekday >= DateTime.saturday;
      final inMonth = day.month == focus.month;
      final selected = day == focus;
      final isToday = day == today;
      final events = [
        for (final o in occurrences)
          if (o.isOn(day)) o,
      ];
      return Semantics(
        button: true,
        selected: selected,
        label:
            '${local.formatFullDate(day.toDateTime())}, '
            '${events.length} ${events.length == 1 ? 'event' : 'events'}',
        excludeSemantics: true,
        child: InkWell(
          // A second tap on the chosen day zooms into it.
          onTap: () {
            final calendar = ref.read(calendarProvider.notifier);
            if (!selected) return calendar.select(day);
            final box = context.findRenderObject();
            calendar.zoomIn(
              CalendarMode.day,
              day,
              from: box is RenderBox
                  ? box.localToGlobal(Offset.zero) & box.size
                  : null,
            );
          },
          child: Container(
            margin: EdgeInsets.all(look.cornerRadius > 0 ? 2 : 0),
            decoration: BoxDecoration(
              color: selected
                  ? look.accent.withValues(alpha: 0.12)
                  : weekend && look.weekend != null
                  ? look.weekend
                  : look.cornerRadius > 0
                  ? look.cell
                  : null,
              borderRadius: look.cornerRadius > 0
                  ? BorderRadius.circular(look.cornerRadius)
                  : null,
            ),
            padding: const EdgeInsets.all(3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isToday)
                  TodayMark(
                    text: '${day.day}',
                    style: theme.textTheme.labelMedium,
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Text(
                      '${day.day}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: inMonth ? null : theme.colorScheme.outline,
                      ),
                    ),
                  ),
                if (showTitles)
                  for (final o in events.take(3))
                    _EventChip(occurrence: o, look: look.events)
                else if (events.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Wrap(
                      spacing: 3,
                      children: [
                        for (final o in events.take(4))
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: Color(o.color),
                              shape: BoxShape.circle,
                              boxShadow: look.dark
                                  ? [
                                      BoxShadow(
                                        color: Color(o.color),
                                        blurRadius: 4,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                      ],
                    ),
                  ),
                if (showTitles && events.length > 3)
                  Text(
                    '+${events.length - 3}',
                    style: theme.textTheme.labelSmall,
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
            for (var i = 0; i < 7; i++)
              Expanded(
                child: _WeekdayHeading(
                  index: (local.firstDayOfWeekIndex + i) % 7,
                  label:
                      local.narrowWeekdays[(local.firstDayOfWeekIndex + i) % 7],
                ),
              ),
          ],
        ),
        Expanded(
          child: Column(
            children: [
              for (var w = 0; w < 6; w++)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < 7; i++)
                        Expanded(
                          child: look.cornerRadius > 0
                              ? cell(days[w * 7 + i])
                              : CustomPaint(
                                  foregroundPainter: CellEdges(
                                    look.gridLines,
                                    look.grid,
                                    seed: w * 7 + i,
                                  ),
                                  child: cell(days[w * 7 + i]),
                                ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One day's events as a list.
class _Agenda extends ConsumerWidget {
  const _Agenda({required this.day, required this.occurrences});

  final Day day;
  final List<Occurrence> occurrences;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final local = MaterialLocalizations.of(context);
    String time(DateTime t) => local.formatTimeOfDay(TimeOfDay.fromDateTime(t));

    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  local.formatFullDate(day.toDateTime()),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.edit_note),
                label: const Text('Planner'),
                onPressed: () => openPlannerDay(context, ref, day),
              ),
            ],
          ),
        ),
        if (occurrences.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('No events.')),
        for (final o in occurrences)
          ListTile(
            leading: Container(
              width: 6,
              height: 36,
              decoration: BoxDecoration(
                color: Color(o.color),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            title: Text(o.event.title),
            subtitle: Text(
              [
                o.allDay ? 'All day' : '${time(o.start)} – ${time(o.end)}',
                if (o.event.recurrence != null) 'Repeats',
              ].join(' · '),
            ),
            onTap: () => showEventEditor(context, event: o.event),
          ),
      ],
    );
  }
}

/// A weekday letter; Pastel gives each day its own colour.
class _WeekdayHeading extends StatelessWidget {
  const _WeekdayHeading({required this.index, required this.label});

  /// 0 Sunday ... 6 Saturday, as in MaterialLocalizations.
  final int index;
  final String label;

  @override
  Widget build(BuildContext context) {
    final look = CalendarLook.of(context);
    final style = Theme.of(context).textTheme.labelSmall;
    final colors = look.weekdayColors;
    if (colors == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(label, textAlign: TextAlign.center, style: style),
      );
    }
    // The colours run Monday first.
    final color = colors[(index + 6) % 7];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: style?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// An event in a month cell, drawn the template's way.
class _EventChip extends StatelessWidget {
  const _EventChip({required this.occurrence, required this.look});

  final Occurrence occurrence;
  final EventLook look;

  @override
  Widget build(BuildContext context) {
    final color = Color(occurrence.color);
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;
    final text = Theme.of(context).colorScheme.onSurface;
    final (decoration, textColor) = switch (look) {
      EventLook.filled => (
        BoxDecoration(
          color: color.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(3),
        ),
        onColor,
      ),
      EventLook.outline => (
        BoxDecoration(
          border: Border.all(color: color, width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        text,
      ),
      EventLook.bar => (
        BoxDecoration(
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        text,
      ),
      EventLook.dot => (const BoxDecoration(), text),
    };
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      width: double.infinity,
      decoration: decoration,
      child: Row(
        children: [
          if (look == EventLook.dot)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          Expanded(
            child: Text(
              occurrence.event.title,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(fontSize: 11, color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bold Modern's heading: the month as a huge number beside its name.
class _BigMonthHeading extends StatelessWidget {
  const _BigMonthHeading({required this.month});

  final Day month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final look = CalendarLook.of(context);
    final local = MaterialLocalizations.of(context);
    final name = local.formatMonthYear(month.toDateTime());
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            month.month.toString().padLeft(2, '0'),
            style: theme.textTheme.displayMedium?.copyWith(
              color: look.accent,
              fontWeight: FontWeight.w900,
              height: 0.9,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name.toUpperCase(),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
