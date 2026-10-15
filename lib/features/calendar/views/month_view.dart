import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../planner/planner_screen.dart' show openPlannerDay;
import '../../tasks/task_providers.dart' show todayProvider;
import '../calendar_providers.dart';
import '../domain/event.dart';
import '../event_editor.dart';

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
        final grid = _MonthGrid(
          focus: focus,
          days: days,
          occurrences: occurrences,
          showTitles: constraints.maxWidth >= 600,
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

    Widget cell(Day day) {
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
          onTap: () => ref.read(calendarProvider.notifier).select(day),
          child: Container(
            decoration: BoxDecoration(
              color: selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.10)
                  : null,
              border: Border.all(
                color: theme.colorScheme.outlineVariant,
                width: 0.5,
              ),
            ),
            padding: const EdgeInsets.all(3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: isToday ? theme.colorScheme.primary : null,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${day.day}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: isToday
                          ? theme.colorScheme.onPrimary
                          : inMonth
                          ? null
                          : theme.colorScheme.outline,
                    ),
                  ),
                ),
                if (showTitles)
                  for (final o in events.take(3))
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Color(o.color).withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        o.event.title,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                          fontSize: 11,
                          color:
                              ThemeData.estimateBrightnessForColor(
                                    Color(o.color),
                                  ) ==
                                  Brightness.dark
                              ? Colors.white
                              : Colors.black,
                        ),
                      ),
                    )
                else if (events.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Wrap(
                      spacing: 3,
                      children: [
                        for (final o in events.take(4))
                          Icon(Icons.circle, size: 6, color: Color(o.color)),
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    local.narrowWeekdays[(local.firstDayOfWeekIndex + i) % 7],
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall,
                  ),
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
                        Expanded(child: cell(days[w * 7 + i])),
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
