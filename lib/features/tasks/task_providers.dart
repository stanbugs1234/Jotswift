import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notebooks/notes_providers.dart' show currentUidProvider;
import 'data/task_repository.dart';
import 'domain/task.dart';

/// Overridden in `main()` with Firestore when Firebase is set up.
final tasksBackendProvider = Provider<TasksBackend>(
  (ref) => InMemoryTasksBackend(),
);

final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => ref.watch(tasksBackendProvider).tasks(ref.watch(currentUidProvider)),
);

final taskListsProvider = StreamProvider<List<TaskList>>(
  (ref) => ref.watch(taskRepositoryProvider).watchLists(),
);

final tasksProvider = StreamProvider<List<Task>>(
  (ref) => ref.watch(taskRepositoryProvider).watchTasks(),
);

/// Today's date. A provider so tests can fix it.
final todayProvider = Provider<Day>((ref) => Day.today());

/// Which tasks the To-do screen shows.
sealed class TaskView {
  const TaskView();
}

/// Open tasks due today or earlier.
class TodayView extends TaskView {
  const TodayView();

  @override
  bool operator ==(Object other) => other is TodayView;

  @override
  int get hashCode => 1;
}

/// Open tasks due after today, by day.
class UpcomingView extends TaskView {
  const UpcomingView();

  @override
  bool operator ==(Object other) => other is UpcomingView;

  @override
  int get hashCode => 2;
}

/// One list's tasks; [listId] null is the Inbox.
@immutable
class TaskListView extends TaskView {
  const TaskListView(this.listId);

  final String? listId;

  @override
  bool operator ==(Object other) =>
      other is TaskListView && other.listId == listId;

  @override
  int get hashCode => Object.hash(3, listId);
}

class TaskViewController extends Notifier<TaskView> {
  @override
  TaskView build() => const TodayView();

  void show(TaskView view) => state = view;
}

final taskViewProvider = NotifierProvider<TaskViewController, TaskView>(
  TaskViewController.new,
);

int _byOrder(Task a, Task b) => a.order.compareTo(b.order);

/// Higher priority first, then list order.
int _byPriority(Task a, Task b) {
  final p = b.priority.index - a.priority.index;
  return p != 0 ? p : _byOrder(a, b);
}

/// Open tasks due on or before [today]: overdue days first, then by
/// priority.
List<Task> tasksForToday(Iterable<Task> tasks, Day today) =>
    [
      for (final t in tasks)
        if (!t.done && t.due != null && !t.due!.isAfter(today)) t,
    ]..sort((a, b) {
      final d = a.due!.compareTo(b.due!);
      return d != 0 ? d : _byPriority(a, b);
    });

/// Open tasks due after [today], grouped by day in date order.
List<(Day, List<Task>)> upcomingTasks(Iterable<Task> tasks, Day today) {
  final byDay = <Day, List<Task>>{};
  for (final t in tasks) {
    if (!t.done && t.due != null && t.due!.isAfter(today)) {
      byDay.putIfAbsent(t.due!, () => []).add(t);
    }
  }
  return [
    for (final day in byDay.keys.toList()..sort())
      (day, byDay[day]!..sort(_byPriority)),
  ];
}

/// A list's open tasks in their order, and its done tasks, newest first.
({List<Task> open, List<Task> done}) tasksInList(
  Iterable<Task> tasks,
  String? listId,
) {
  final open = <Task>[];
  final done = <Task>[];
  for (final t in tasks) {
    if (t.listId != listId) continue;
    (t.done ? done : open).add(t);
  }
  open.sort(_byOrder);
  done.sort((a, b) => (b.completedAt ?? 0).compareTo(a.completedAt ?? 0));
  return (open: open, done: done);
}

/// How many open tasks each view would show, for the badges.
final taskCountsProvider = Provider<Map<TaskView, int>>((ref) {
  final tasks = ref.watch(tasksProvider).value ?? const [];
  final today = ref.watch(todayProvider);
  final counts = <TaskView, int>{
    const TodayView(): tasksForToday(tasks, today).length,
  };
  for (final t in tasks) {
    if (t.done) continue;
    final view = TaskListView(t.listId);
    counts[view] = (counts[view] ?? 0) + 1;
  }
  return counts;
});

/// The order that puts a task at [index] of [open] (a list's open tasks,
/// with the moving task already removed).
double orderAt(List<Task> open, int index) {
  if (open.isEmpty) return 0;
  if (index <= 0) return open.first.order - 1;
  if (index >= open.length) return open.last.order + 1;
  return (open[index - 1].order + open[index].order) / 2;
}
