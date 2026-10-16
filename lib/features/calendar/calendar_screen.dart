import '../../shared/ui/tab_title.dart';
import '../../shared/ui/tokens.dart';

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/directional_switcher.dart';
import '../../core/motion/period_transition.dart';
import '../../core/motion/zoom_switcher.dart';
import '../planner/planner_screen.dart' show openPlannerDay;
import '../tasks/task_providers.dart' show todayProvider;
import 'calendar_providers.dart';
import 'calendars_panel.dart';
import 'templates/calendar_art.dart';
import 'templates/calendar_look.dart';
import 'templates/calendar_templates_screen.dart';
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
        onMonth: (month, rect) => ref
            .read(calendarProvider.notifier)
            .zoomIn(
              CalendarMode.month,
              month.year == today.year && month.month == today.month
                  ? today
                  : month,
              from: rect,
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

    return CalendarLook(
      template: seasonalTemplate(
        ref.watch(calendarTemplateProvider),
        day.month,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showPanel = constraints.maxWidth >= calendarsPanelBreakpoint;
          // Below this the six view buttons don't fit; use a menu.
          final narrow = constraints.maxWidth < 720;
          return _scaffold(
            context,
            ref,
            title,
            body,
            period,
            showPanel,
            narrow,
          );
        },
      ),
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
        // Back out to the month, then the year, like a back button named
        // after where it goes ("‹ 2026", "‹ Oct").
        leadingWidth: zoomLevel(state.mode) > 0 ? 96 : null,
        leading: zoomLevel(state.mode) > 0
            ? Tooltip(
                message: 'Zoom out',
                child: TextButton.icon(
                  onPressed: controller.zoomOut,
                  icon: const Icon(Icons.chevron_left),
                  label: Text(
                    zoomLevel(state.mode) == 1
                        ? '${day.year}'
                        : _shortMonths[day.month - 1],
                  ),
                ),
              )
            : null,
        centerTitle: false,
        titleSpacing: zoomLevel(state.mode) > 0 ? 0 : gutterOf(context),
        // A template with its own heading font keeps it.
        title: CalendarLook.of(context).headingFont == null
            ? TabTitle(title)
            : Text(title),
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
                'templates' => showCalendarTemplates(context),
                'planner' => openPlannerDay(context, ref, day),
                _ => context.push('/settings'),
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'calendars',
                  child: Text('Calendars'),
                ),
                const PopupMenuItem(
                  value: 'templates',
                  child: Text('Templates & animation'),
                ),
                if (state.mode == CalendarMode.day)
                  const PopupMenuItem(
                    value: 'planner',
                    child: Text('Open in Planner'),
                  ),
                const PopupMenuItem(value: 'settings', child: Text('Settings')),
              ],
            )
          else ...[
            IconButton(
              tooltip: 'Templates & animation',
              icon: const Icon(Icons.palette_outlined),
              onPressed: () => showCalendarTemplates(context),
            ),
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.push('/settings'),
            ),
          ],
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
                        ButtonSegment(
                          value: m,
                          label: Text(m.label, maxLines: 1, softWrap: false),
                        ),
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
        child: _PinchToZoom(
          onZoomIn: () => switch (state.mode) {
            CalendarMode.year => controller.zoomIn(CalendarMode.month, day),
            CalendarMode.month => controller.zoomIn(CalendarMode.day, day),
            _ => null,
          },
          onZoomOut: zoomLevel(state.mode) > 0 ? controller.zoomOut : null,
          child: GestureDetector(
            onHorizontalDragEnd: (details) {
              final v = details.primaryVelocity ?? 0;
              if (v.abs() > 300) controller.move(v < 0 ? 1 : -1);
            },
            // Changing view zooms in or out; moving within a view slides.
            child: ZoomSwitcher(
              view: state.mode,
              level: zoomLevel(state.mode),
              origin: ref.watch(zoomOriginProvider)?.rect,
              child: _PeriodSwitcher(
                key: ValueKey(state.mode),
                mode: state.mode,
                period: period,
                child: body,
              ),
            ),
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

/// Two-finger pinch: spreading zooms in a level, pinching zooms out. Uses
/// raw pointers so one-finger swipes and scrolling still work as before.
class _PinchToZoom extends StatefulWidget {
  const _PinchToZoom({
    required this.child,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final Widget child;
  final VoidCallback onZoomIn;
  final VoidCallback? onZoomOut;

  @override
  State<_PinchToZoom> createState() => _PinchToZoomState();
}

class _PinchToZoomState extends State<_PinchToZoom> {
  final _points = <int, Offset>{};
  double? _startSpan;
  var _done = false;

  double get _span {
    final p = _points.values.take(2).toList();
    return (p[0] - p[1]).distance;
  }

  void _down(PointerDownEvent e) {
    _points[e.pointer] = e.position;
    if (_points.length == 2) {
      _startSpan = _span;
      _done = false;
    }
  }

  void _move(PointerMoveEvent e) {
    if (!_points.containsKey(e.pointer)) return;
    _points[e.pointer] = e.position;
    final start = _startSpan;
    if (_points.length != 2 || start == null || start < 1 || _done) return;
    final ratio = _span / start;
    if (ratio > 1.35) {
      _done = true;
      widget.onZoomIn();
    } else if (ratio < 0.7 && widget.onZoomOut != null) {
      _done = true;
      widget.onZoomOut!();
    }
  }

  void _up(PointerEvent e) {
    _points.remove(e.pointer);
    if (_points.length < 2) _startSpan = null;
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _up,
    onPointerCancel: _up,
    child: widget.child,
  );
}

/// Moves within a view: months and years use the chosen month animation;
/// weeks and days slide.
class _PeriodSwitcher extends ConsumerWidget {
  const _PeriodSwitcher({
    required this.mode,
    required this.period,
    required this.child,
    super.key,
  });

  final CalendarMode mode;
  final Day period;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (mode != CalendarMode.month && mode != CalendarMode.year) {
      return DirectionalSwitcher<Day>(position: period, child: child);
    }
    return PeriodTransition<Day>(
      animation: ref.watch(monthAnimationProvider),
      period: period,
      child: child,
    );
  }
}

const _shortMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
