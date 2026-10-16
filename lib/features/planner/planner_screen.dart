import '../../shared/ui/empty_state.dart';
import '../../shared/ui/tab_title.dart';
import '../../shared/ui/tokens.dart';

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/skins/skin_providers.dart';
import '../../core/skins/widgets/page_style.dart';
import '../calendar/calendar_providers.dart';
import '../calendar/event_editor.dart';
import '../canvas/ink_toolbar.dart';
import '../canvas/page_canvas.dart';
import '../notebooks/notes_providers.dart';
import '../tasks/domain/task.dart';
import '../tasks/task_providers.dart';
import '../tasks/todo_screen.dart' show TaskTile;

const plannerPath = '/planner';

/// Planner pages aren't in any notebook; they share this notebook id.
const plannerNotebookId = 'planner';

/// The page id of [day]'s handwriting, the same on every device.
String plannerPageId(Day day) => 'planner-$day';

class PlannerDayController extends Notifier<Day> {
  @override
  Day build() => ref.read(todayProvider);

  void show(Day day) => state = day;
  void move(int days) => state = state.addDays(days);
}

/// The day the Planner tab shows.
final plannerDayProvider = NotifierProvider<PlannerDayController, Day>(
  PlannerDayController.new,
);

/// Opens [day] in the Planner tab.
void openPlannerDay(BuildContext context, WidgetRef ref, Day day) {
  ref.read(plannerDayProvider.notifier).show(day);
  context.go(plannerPath);
}

/// [day]'s open tasks: those due that day, plus overdue ones when it's
/// today. Highest priority first.
List<Task> plannerTasks(Iterable<Task> tasks, Day day, Day today) {
  final result = day == today
      ? tasksForToday(tasks, today)
      : [
          for (final t in tasks)
            if (!t.done && t.due == day) t,
        ];
  result.sort((a, b) {
    final p = b.priority.index - a.priority.index;
    return p != 0 ? p : a.order.compareTo(b.order);
  });
  return result;
}

/// The Planner tab: a day's schedule and tasks beside a page to write on.
class PlannerScreen extends ConsumerWidget {
  const PlannerScreen({super.key});

  static const wideBreakpoint = 900.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(plannerDayProvider);
    final today = ref.watch(todayProvider);
    final controller = ref.read(plannerDayProvider.notifier);
    final local = MaterialLocalizations.of(context);

    final actions = [
      IconButton(
        tooltip: 'Previous day',
        icon: const Icon(Icons.chevron_left),
        onPressed: () => controller.move(-1),
      ),
      TextButton(
        onPressed: day == today ? null : () => controller.show(today),
        child: const Text('Today'),
      ),
      IconButton(
        tooltip: 'Next day',
        icon: const Icon(Icons.chevron_right),
        onPressed: () => controller.move(1),
      ),
      IconButton(
        tooltip: 'Settings',
        icon: const Icon(Icons.settings_outlined),
        onPressed: () => context.push('/settings'),
      ),
    ];
    final title = TabTitle(local.formatFullDate(day.toDateTime()));

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= wideBreakpoint) {
          return Scaffold(
            appBar: AppBar(
              centerTitle: false,
              titleSpacing: gutterOf(context),
              title: title,
              actions: actions,
            ),
            body: Row(
              children: [
                SizedBox(width: 360, child: _DayPanel(day: day)),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _NotesArea(key: ValueKey(day), day: day),
                ),
              ],
            ),
          );
        }
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              centerTitle: false,
              titleSpacing: gutterOf(context),
              title: title,
              actions: actions,
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Plan'),
                  Tab(text: 'Notes'),
                ],
              ),
            ),
            body: TabBarView(
              // Swiping would fight with writing on the notes page.
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _DayPanel(day: day),
                _NotesArea(key: ValueKey(day), day: day),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The live part of the day: its schedule, then its tasks.
class _DayPanel extends ConsumerWidget {
  const _DayPanel({required this.day});

  final Day day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final local = MaterialLocalizations.of(context);
    final today = ref.watch(todayProvider);
    final events = ref.watch(occurrencesProvider((from: day, to: day)));
    final tasks = plannerTasks(
      ref.watch(tasksProvider).value ?? const [],
      day,
      today,
    );
    final top = tasks.take(3).toList();
    final rest = tasks.skip(3).toList();
    String time(DateTime t) => local.formatTimeOfDay(TimeOfDay.fromDateTime(t));

    Widget heading(String text, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
      child: Row(
        children: [
          Expanded(child: Text(text, style: theme.textTheme.titleMedium)),
          ?trailing,
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        heading(
          'Schedule',
          trailing: IconButton(
            tooltip: 'Add event',
            icon: const Icon(Icons.add),
            onPressed: () {
              final now = DateTime.now();
              showEventEditor(
                context,
                start: DateTime(
                  day.year,
                  day.month,
                  day.day,
                  day == today ? min(now.hour + 1, 23) : 9,
                ),
              );
            },
          ),
        ),
        if (events.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: Insets.lg),
            child: EmptyState(
              compact: true,
              icon: Icons.event_available_outlined,
              title: 'Nothing scheduled.',
              message: 'Tap + to add an event.',
            ),
          ),
        for (final o in events)
          ListTile(
            dense: true,
            leading: SizedBox(
              width: 64,
              child: Text(
                o.allDay ? 'All day' : time(o.start),
                style: theme.textTheme.labelMedium,
              ),
            ),
            title: Row(
              children: [
                Container(
                  width: 4,
                  height: 20,
                  margin: const EdgeInsets.only(right: 8),
                  color: Color(o.color),
                ),
                Expanded(child: Text(o.event.title)),
              ],
            ),
            onTap: () => showEventEditor(context, event: o.event),
          ),
        heading('Top 3'),
        _AddTask(day: day),
        if (tasks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: Insets.lg),
            child: EmptyState(
              compact: true,
              icon: Icons.flag_outlined,
              title: 'Nothing due.',
              message: 'Add the three things that matter most.',
            ),
          ),
        for (final t in top) TaskTile(key: ValueKey(t.id), task: t),
        if (rest.isNotEmpty) ...[
          heading('Also due'),
          for (final t in rest) TaskTile(key: ValueKey(t.id), task: t),
        ],
      ],
    );
  }
}

class _AddTask extends ConsumerStatefulWidget {
  const _AddTask({required this.day});

  final Day day;

  @override
  ConsumerState<_AddTask> createState() => _AddTaskState();
}

class _AddTaskState extends ConsumerState<_AddTask> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _add() {
    final title = _text.text.trim();
    if (title.isEmpty) return;
    ref.read(taskRepositoryProvider).createTask(title, due: widget.day);
    _text.clear();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
    child: TextField(
      controller: _text,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(
        hintText: 'Add a task for this day',
        prefixIcon: Icon(Icons.add),
        border: OutlineInputBorder(),
        isDense: true,
      ),
      onSubmitted: (_) => _add(),
    ),
  );
}

/// [day]'s page to write on, in the default notebook style.
class _NotesArea extends ConsumerStatefulWidget {
  const _NotesArea({required this.day, super.key});

  final Day day;

  @override
  ConsumerState<_NotesArea> createState() => _NotesAreaState();
}

class _NotesAreaState extends ConsumerState<_NotesArea> {
  String get _pageId => plannerPageId(widget.day);

  @override
  void initState() {
    super.initState();
    ref
        .read(notebookRepositoryProvider)
        .ensurePage(
          _pageId,
          notebookId: plannerNotebookId,
          title: widget.day.toString(),
        );
  }

  @override
  Widget build(BuildContext context) => PageStyle(
    style: ref.watch(defaultStyleProvider),
    child: Column(
      children: [
        InkToolbar(pageId: _pageId, inkEnabled: !kIsWeb),
        const Divider(height: 1),
        Expanded(
          child: PageCanvas(pageId: _pageId, inkEnabled: !kIsWeb),
        ),
      ],
    ),
  );
}
