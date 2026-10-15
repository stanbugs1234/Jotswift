import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/dialogs.dart';
import '../notebooks/domain/notebook_models.dart' show notebookColors;
import 'domain/task.dart';
import 'task_editor.dart';
import 'task_providers.dart';

/// The To-do tab: Today, Upcoming, the Inbox and the user's lists.
class TodoScreen extends ConsumerWidget {
  const TodoScreen({super.key});

  /// Content at least this wide shows the views in a side pane.
  static const paneBreakpoint = 720.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(taskListsProvider);
    var view = ref.watch(taskViewProvider);
    // A deleted list falls back to Today.
    if (view case TaskListView(:final listId?)
        when lists.hasValue && !lists.value!.any((l) => l.id == listId)) {
      view = const TodayView();
    }
    final list = switch (view) {
      TaskListView(:final listId?) =>
        lists.value?.where((l) => l.id == listId).firstOrNull,
      _ => null,
    };
    final title = switch (view) {
      TodayView() => 'Today',
      UpcomingView() => 'Upcoming',
      TaskListView() => list?.title ?? 'Inbox',
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= paneBreakpoint;
        final scaffold = Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              if (list != null) _ListMenu(list: list),
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => context.push('/settings'),
              ),
            ],
            bottom: wide ? null : _ViewChips(selected: view),
          ),
          body: _TaskPane(view: view),
        );
        if (!wide) return scaffold;
        return Row(
          children: [
            SizedBox(width: 240, child: _ViewPane(selected: view)),
            const VerticalDivider(width: 1),
            Expanded(child: scaffold),
          ],
        );
      },
    );
  }
}

Future<void> createTaskList(BuildContext context, WidgetRef ref) async {
  final title = await askForText(
    context,
    title: 'New list',
    confirmLabel: 'Create',
    hint: 'List name',
  );
  if (title == null || title.trim().isEmpty) return;
  final count = ref.read(taskListsProvider).value?.length ?? 0;
  final list = await ref
      .read(taskRepositoryProvider)
      .createList(
        title.trim(),
        color: notebookColors[(count + 1) % notebookColors.length],
      );
  ref.read(taskViewProvider.notifier).show(TaskListView(list.id));
}

/// The views as a side pane, with counts (wide screens).
class _ViewPane extends ConsumerWidget {
  const _ViewPane({required this.selected});

  final TaskView selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final lists = ref.watch(taskListsProvider).value ?? const [];
    final counts = ref.watch(taskCountsProvider);

    Widget entry(
      TaskView view,
      String label,
      Widget icon, {
      bool showCount = true,
    }) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: ListTile(
        dense: true,
        selected: selected == view,
        selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: icon,
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: showCount && (counts[view] ?? 0) > 0
            ? Text('${counts[view]}')
            : null,
        onTap: () => ref.read(taskViewProvider.notifier).show(view),
      ),
    );

    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        right: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            entry(const TodayView(), 'Today', const Icon(Icons.today)),
            entry(
              const UpcomingView(),
              'Upcoming',
              const Icon(Icons.date_range),
              showCount: false,
            ),
            entry(const TaskListView(null), 'Inbox', const Icon(Icons.inbox)),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 6),
              child: Text('LISTS', style: theme.textTheme.labelSmall),
            ),
            for (final l in lists)
              entry(
                TaskListView(l.id),
                l.title,
                Icon(Icons.circle, size: 14, color: Color(l.color)),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.add),
                title: const Text('New list'),
                onTap: () => createTaskList(context, ref),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The views as a row of chips (phones and narrow windows).
class _ViewChips extends ConsumerWidget implements PreferredSizeWidget {
  const _ViewChips({required this.selected});

  final TaskView selected;

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(taskListsProvider).value ?? const [];
    Widget chip(TaskView view, String label) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected == view,
        onSelected: (_) => ref.read(taskViewProvider.notifier).show(view),
      ),
    );
    return SizedBox(
      height: preferredSize.height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        children: [
          chip(const TodayView(), 'Today'),
          chip(const UpcomingView(), 'Upcoming'),
          chip(const TaskListView(null), 'Inbox'),
          for (final l in lists) chip(TaskListView(l.id), l.title),
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('New list'),
            onPressed: () => createTaskList(context, ref),
          ),
        ],
      ),
    );
  }
}

class _ListMenu extends ConsumerWidget {
  const _ListMenu({required this.list});

  final TaskList list;

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final title = await askForText(
      context,
      title: 'Rename list',
      confirmLabel: 'Rename',
      initialValue: list.title,
    );
    if (title == null || title.trim().isEmpty) return;
    await ref
        .read(taskRepositoryProvider)
        .saveList(list.copyWith(title: title.trim()));
  }

  Future<void> _recolor(BuildContext context, WidgetRef ref) async {
    final color = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('List color'),
        contentPadding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final c in notebookColors)
                Semantics(
                  button: true,
                  selected: c == list.color,
                  label: 'Color ${notebookColors.indexOf(c) + 1}',
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.pop(context, c),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: Color(c),
                      child: c == list.color
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
    if (color == null) return;
    await ref
        .read(taskRepositoryProvider)
        .saveList(list.copyWith(color: color));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final count = ref
        .read(tasksProvider)
        .value
        ?.where((t) => t.listId == list.id)
        .length;
    final ok = await confirmDelete(
      context,
      title: 'Delete "${list.title}"?',
      message: count == null || count == 0
          ? 'The list is empty.'
          : 'Its $count ${count == 1 ? 'task' : 'tasks'} will be deleted '
                'too.',
    );
    if (!ok) return;
    ref.read(taskViewProvider.notifier).show(const TodayView());
    await ref.read(taskRepositoryProvider).deleteList(list.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
    tooltip: 'List options',
    onSelected: (action) => switch (action) {
      'rename' => _rename(context, ref),
      'color' => _recolor(context, ref),
      _ => _delete(context, ref),
    },
    itemBuilder: (context) => const [
      PopupMenuItem(value: 'rename', child: Text('Rename')),
      PopupMenuItem(value: 'color', child: Text('Color')),
      PopupMenuItem(value: 'delete', child: Text('Delete list')),
    ],
  );
}

/// The quick-add box and the tasks of [view].
class _TaskPane extends ConsumerWidget {
  const _TaskPane({required this.view});

  final TaskView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider);
    final today = ref.watch(todayProvider);
    final all = tasks.value ?? const <Task>[];

    final Widget content;
    if (tasks.isLoading && !tasks.hasValue) {
      content = const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    } else {
      content = switch (view) {
        TodayView() => _plainList(
          tasksForToday(all, today),
          empty: 'Nothing due today.',
          showList: true,
        ),
        UpcomingView() => _upcoming(context, upcomingTasks(all, today), today),
        TaskListView(:final listId) => _ListContents(
          tasks: tasksInList(all, listId),
        ),
      };
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _QuickAdd(view: view)),
        content,
        const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
      ],
    );
  }

  Widget _plainList(
    List<Task> tasks, {
    required String empty,
    bool showList = false,
  }) => tasks.isEmpty
      ? SliverToBoxAdapter(child: _Empty(empty))
      : SliverList.list(
          children: [
            for (final t in tasks)
              TaskTile(key: ValueKey(t.id), task: t, showList: showList),
          ],
        );

  Widget _upcoming(
    BuildContext context,
    List<(Day, List<Task>)> days,
    Day today,
  ) {
    if (days.isEmpty) {
      return const SliverToBoxAdapter(
        child: _Empty('Nothing coming up. Give tasks a due day to see them.'),
      );
    }
    final theme = Theme.of(context);
    final local = MaterialLocalizations.of(context);
    return SliverList.list(
      children: [
        for (final (day, tasks) in days) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              today.daysUntil(day) == 1
                  ? 'Tomorrow'
                  : local.formatFullDate(day.toDateTime()),
              style: theme.textTheme.titleSmall,
            ),
          ),
          for (final t in tasks)
            TaskTile(
              key: ValueKey(t.id),
              task: t,
              showList: true,
              showDue: false,
            ),
        ],
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(48),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyLarge,
    ),
  );
}

/// A list's open tasks, which can be dragged into order, then its
/// completed tasks.
class _ListContents extends ConsumerWidget {
  const _ListContents({required this.tasks});

  final ({List<Task> open, List<Task> done}) tasks;

  void _reorder(WidgetRef ref, int from, int to) {
    final open = [...tasks.open];
    final moving = open.removeAt(from);
    ref
        .read(taskRepositoryProvider)
        .saveTask(moving.copyWith(order: orderAt(open, to)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tasks.open.isEmpty && tasks.done.isEmpty) {
      return const SliverToBoxAdapter(child: _Empty('No tasks yet.'));
    }
    return SliverMainAxisGroup(
      slivers: [
        SliverReorderableList(
          itemCount: tasks.open.length,
          onReorderItem: (from, to) => _reorder(ref, from, to),
          itemBuilder: (context, i) {
            final t = tasks.open[i];
            return ReorderableDelayedDragStartListener(
              key: ValueKey(t.id),
              index: i,
              child: TaskTile(task: t),
            );
          },
        ),
        if (tasks.done.isNotEmpty)
          SliverToBoxAdapter(
            child: ExpansionTile(
              title: Text('Completed (${tasks.done.length})'),
              children: [
                for (final t in tasks.done)
                  TaskTile(key: ValueKey(t.id), task: t),
              ],
            ),
          ),
      ],
    );
  }
}

/// Adds tasks to the current view: due today in Today, due tomorrow in
/// Upcoming, and into the list otherwise.
class _QuickAdd extends ConsumerStatefulWidget {
  const _QuickAdd({required this.view});

  final TaskView view;

  @override
  ConsumerState<_QuickAdd> createState() => _QuickAddState();
}

class _QuickAddState extends ConsumerState<_QuickAdd> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add() {
    final title = _text.text.trim();
    if (title.isEmpty) return;
    final today = ref.read(todayProvider);
    ref
        .read(taskRepositoryProvider)
        .createTask(
          title,
          listId: switch (widget.view) {
            TaskListView(:final listId) => listId,
            _ => null,
          },
          due: switch (widget.view) {
            TodayView() => today,
            UpcomingView() => today.addDays(1),
            TaskListView() => null,
          },
        );
    _text.clear();
    // Stay in the box to add several in a row.
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: TextField(
      controller: _text,
      focusNode: _focus,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        hintText: 'Add a task',
        prefixIcon: const Icon(Icons.add),
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: IconButton(
          tooltip: 'Add',
          icon: const Icon(Icons.keyboard_return),
          onPressed: _add,
        ),
      ),
      onSubmitted: (_) => _add(),
    ),
  );
}

/// One task: tick it off, tap to edit, swipe to delete.
class TaskTile extends ConsumerWidget {
  const TaskTile({
    required this.task,
    this.showList = false,
    this.showDue = true,
    super.key,
  });

  final Task task;

  /// Shows which list it's in (in Today and Upcoming).
  final bool showList;
  final bool showDue;

  void _toggle(WidgetRef ref, bool done) => ref
      .read(taskRepositoryProvider)
      .saveTask(
        task.copyWith(
          done: done,
          completedAt: done ? DateTime.now().millisecondsSinceEpoch : null,
          clearCompletedAt: !done,
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = ref.watch(todayProvider);
    final list = showList && task.listId != null
        ? ref
              .watch(taskListsProvider)
              .value
              ?.where((l) => l.id == task.listId)
              .firstOrNull
        : null;
    final overdue = !task.done && task.due != null && task.due!.isBefore(today);

    final details = <Widget>[
      if (showDue && task.due != null)
        Text(
          overdue
              ? 'Overdue · ${dueLabel(context, task.due!, today)}'
              : dueLabel(context, task.due!, today),
          style: theme.textTheme.bodySmall?.copyWith(
            color: overdue ? theme.colorScheme.error : null,
          ),
        ),
      if (list != null)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 8, color: Color(list.color)),
            const SizedBox(width: 4),
            Text(list.title, style: theme.textTheme.bodySmall),
          ],
        ),
      if (task.notes.isNotEmpty)
        Icon(Icons.notes, size: 14, color: theme.colorScheme.outline),
    ];

    return Dismissible(
      key: ValueKey('dismiss-${task.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete, color: theme.colorScheme.onError),
      ),
      onDismissed: (_) {
        final repo = ref.read(taskRepositoryProvider);
        repo.deleteTask(task.id);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Deleted "${task.title}"'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () => repo.saveTask(task),
              ),
            ),
          );
      },
      child: ListTile(
        leading: Checkbox(
          value: task.done,
          semanticLabel: task.done
              ? 'Mark ${task.title} not done'
              : 'Complete ${task.title}',
          onChanged: (v) => _toggle(ref, v ?? false),
        ),
        title: Text(
          task.title,
          style: task.done
              ? TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: theme.colorScheme.outline,
                )
              : null,
        ),
        subtitle: details.isEmpty
            ? null
            : Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: details,
              ),
        trailing: task.priority == TaskPriority.none
            ? null
            : Icon(
                Icons.flag,
                semanticLabel: '${task.priority.name} priority',
                color: priorityColor(task.priority, theme.colorScheme),
              ),
        onTap: () => showTaskEditor(context, task),
      ),
    );
  }
}
