import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/directional_switcher.dart';
import '../planner/planner_screen.dart' show openPlannerDay;
import '../tasks/task_providers.dart' show todayProvider;
import 'calendar_providers.dart';
import 'calendars_panel.dart';
import 'domain/event.dart';
import 'event_editor.dart';
import 'time_grid.dart';
import 'views/agenda_view.dart';
import 'views/month_view.dart';
import 'views/year_view.dart';

/// The Calendar tab: month, week and day views of the user's events.
class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(calendarProvider);
    final local = MaterialLocalizations.of(context);
    final firstWeekday = local.firstDayOfWeekIndex;
    final day = state.day;
    final today = ref.watch(todayProvider);

    final week = startOfWeek(day, firstWeekday);
    final title = switch (state.mode) {
      CalendarMode.year => '${day.year}',
      CalendarMode.month ||
      CalendarMode.agenda => local.formatMonthYear(day.toDateTime()),
      CalendarMode.week => local.formatMonthYear(week.toDateTime()),
      CalendarMode.threeDay => local.formatMonthYear(day.toDateTime()),
      CalendarMode.day => local.formatFullDate(day.toDateTime()),
    };

    final body = switch (state.mode) {
      CalendarMode.year => YearView(
        key: ValueKey(day.year),
        year: day.year,
        onMonth: (month, _) => ref
            .read(calendarProvider.notifier)
            .openMonth(
              month.year == today.year && month.month == today.month
                  ? today
                  : month,
            ),
      ),
      CalendarMode.month => MonthView(focus: day),
      CalendarMode.week => TimeGrid(
        key: ValueKey(week),
        days: [for (var i = 0; i < 7; i++) week.addDays(i)],
      ),
      CalendarMode.threeDay => TimeGrid(
        key: ValueKey(('3', day)),
        days: [for (var i = 0; i < 3; i++) day.addDays(i)],
      ),
      CalendarMode.day => TimeGrid(key: ValueKey(day), days: [day]),
      CalendarMode.agenda => AgendaView(anchor: day),
    };

    // Years, months, weeks and days slide in from the side they come from.
    // Picking another day in the same month or week doesn't move anything.
    final period = switch (state.mode) {
      CalendarMode.year => Day(day.year, 1, 1),
      CalendarMode.month => Day(day.year, day.month, 1),
      CalendarMode.week => week,
      CalendarMode.threeDay || CalendarMode.day => day,
      // The list scrolls instead.
      CalendarMode.agenda => Day(0, 1, 1),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final showPanel = constraints.maxWidth >= calendarsPanelBreakpoint;
        final narrow = constraints.maxWidth < 600;
        return _scaffold(context, ref, title, body, period, showPanel, narrow);
      },
    );
  }

  Widget _scaffold(
    BuildContext context,
    WidgetRef ref,
    String title,
    Widget body,
    Day period,
    bool showPanel,
    bool narrow,
  ) {
    final state = ref.watch(calendarProvider);
    final controller = ref.read(calendarProvider.notifier);
    final day = state.day;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (state.mode == CalendarMode.day && !narrow)
            IconButton(
              tooltip: 'Open in Planner',
              icon: const Icon(Icons.edit_note),
              onPressed: () => openPlannerDay(context, ref, day),
            ),
          if (narrow)
            PopupMenuButton<CalendarMode>(
              tooltip: 'View',
              icon: const Icon(Icons.calendar_view_month_outlined),
              initialValue: state.mode,
              onSelected: controller.setMode,
              itemBuilder: (_) => [
                for (final m in CalendarMode.values)
                  CheckedPopupMenuItem(
                    value: m,
                    checked: m == state.mode,
                    child: Text(m.label),
                  ),
              ],
            ),
          if (!showPanel && !narrow)
            IconButton(
              tooltip: 'Calendars',
              icon: const Icon(Icons.layers_outlined),
              onPressed: () => showCalendarsSheet(context),
            ),
          // The agenda scrolls instead.
          if (state.mode != CalendarMode.agenda)
            IconButton(
              tooltip: 'Previous',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => controller.move(-1),
            ),
          TextButton(onPressed: controller.today, child: const Text('Today')),
          if (state.mode != CalendarMode.agenda)
            IconButton(
              tooltip: 'Next',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => controller.move(1),
            ),
          if (narrow)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (choice) => switch (choice) {
                'calendars' => showCalendarsSheet(context),
                'planner' => openPlannerDay(context, ref, day),
                _ => context.push('/settings'),
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'calendars',
                  child: Text('Calendars'),
                ),
                if (state.mode == CalendarMode.day)
                  const PopupMenuItem(
                    value: 'planner',
                    child: Text('Open in Planner'),
                  ),
                const PopupMenuItem(value: 'settings', child: Text('Settings')),
              ],
            )
          else
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.push('/settings'),
            ),
        ],
        // Phones choose the view from a menu (see actions).
        bottom: narrow
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SegmentedButton<CalendarMode>(
                    showSelectedIcon: false,
                    segments: [
                      for (final m in CalendarMode.values)
                        ButtonSegment(value: m, label: Text(m.label)),
                    ],
                    selected: {state.mode},
                    onSelectionChanged: (s) => controller.setMode(s.first),
                  ),
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        // The shelf has a button too; tabs stay alive side by side.
        heroTag: null,
        onPressed: () {
          final now = DateTime.now();
          showEventEditor(
            context,
            start: DateTime(
              day.year,
              day.month,
              day.day,
              min(now.hour + 1, 23),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('New event'),
      ),
      // Swipe sideways to move a month, week or day.
      body: _WithCalendarsPanel(
        show: showPanel,
        child: GestureDetector(
          onHorizontalDragEnd: (details) {
            final v = details.primaryVelocity ?? 0;
            if (v.abs() > 300) controller.move(v < 0 ? 1 : -1);
          },
          child: DirectionalSwitcher<Day>(
            // Switching between Month, Week and Day replaces the view.
            key: ValueKey(state.mode),
            position: period,
            child: body,
          ),
        ),
      ),
    );
  }
}

/// Body width from which the Calendars panel sits beside the calendar;
/// narrower screens open it from the app bar.
const calendarsPanelBreakpoint = 1100.0;

class _WithCalendarsPanel extends StatelessWidget {
  const _WithCalendarsPanel({required this.show, required this.child});

  final bool show;
  final Widget child;

  @override
  Widget build(BuildContext context) => !show
      ? child
      : Row(
          children: [
            const SizedBox(width: 220, child: CalendarsPanel()),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        );
}
