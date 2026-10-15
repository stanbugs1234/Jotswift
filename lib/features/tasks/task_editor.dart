import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/task.dart';
import 'task_providers.dart';

/// How a due day reads: "Today", "Tomorrow", "Yesterday" or a date.
String dueLabel(BuildContext context, Day due, Day today) {
  final days = today.daysUntil(due);
  return switch (days) {
    0 => 'Today',
    1 => 'Tomorrow',
    -1 => 'Yesterday',
    _ => MaterialLocalizations.of(context).formatMediumDate(due.toDateTime()),
  };
}

Color priorityColor(TaskPriority p, ColorScheme scheme) => switch (p) {
  TaskPriority.high => scheme.error,
  TaskPriority.medium => Colors.orange.shade700,
  TaskPriority.low => Colors.blue.shade600,
  TaskPriority.none => scheme.outline,
};

/// Edits [task]: title, notes, due day, priority and list. Saves when
/// "Save" is tapped; "Delete" deletes it.
Future<void> showTaskEditor(BuildContext context, Task task) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useRootNavigator: true,
      builder: (context) => _TaskEditor(task: task),
    );

class _TaskEditor extends ConsumerStatefulWidget {
  const _TaskEditor({required this.task});

  final Task task;

  @override
  ConsumerState<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends ConsumerState<_TaskEditor> {
  late final _title = TextEditingController(text: widget.task.title);
  late final _notes = TextEditingController(text: widget.task.notes);
  late Day? _due = widget.task.due;
  late TaskPriority _priority = widget.task.priority;
  late String? _listId = widget.task.listId;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    final t = widget.task;
    ref
        .read(taskRepositoryProvider)
        .saveTask(
          t.copyWith(
            title: title.isEmpty ? t.title : title,
            notes: _notes.text.trim(),
            due: _due,
            clearDue: _due == null,
            priority: _priority,
            listId: _listId,
            toInbox: _listId == null,
            // Moving to another list puts it at the end there.
            order: _listId == t.listId
                ? null
                : DateTime.now().millisecondsSinceEpoch.toDouble(),
          ),
        );
    Navigator.pop(context);
  }

  Future<void> _pickDate() async {
    final today = ref.read(todayProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: (_due ?? today).toDateTime(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _due = Day.of(picked));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = ref.watch(todayProvider);
    final lists = ref.watch(taskListsProvider).value ?? const [];
    final tomorrow = today.addDays(1);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                style: theme.textTheme.titleLarge,
                decoration: const InputDecoration(
                  hintText: 'Task',
                  border: InputBorder.none,
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(
                  hintText: 'Notes',
                  border: InputBorder.none,
                ),
                minLines: 1,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              Text('Due', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Today'),
                    selected: _due == today,
                    onSelected: (_) => setState(() => _due = today),
                  ),
                  ChoiceChip(
                    label: const Text('Tomorrow'),
                    selected: _due == tomorrow,
                    onSelected: (_) => setState(() => _due = tomorrow),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.event, size: 18),
                    label: Text(
                      _due == null || _due == today || _due == tomorrow
                          ? 'Pick a day'
                          : dueLabel(context, _due!, today),
                    ),
                    onPressed: _pickDate,
                  ),
                  ChoiceChip(
                    label: const Text('No date'),
                    selected: _due == null,
                    onSelected: (_) => setState(() => _due = null),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Priority', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<TaskPriority>(
                showSelectedIcon: false,
                segments: [
                  for (final p in TaskPriority.values)
                    ButtonSegment(
                      value: p,
                      label: Text(switch (p) {
                        TaskPriority.none => 'None',
                        TaskPriority.low => 'Low',
                        TaskPriority.medium => 'Medium',
                        TaskPriority.high => 'High',
                      }),
                    ),
                ],
                selected: {_priority},
                onSelectionChanged: (s) => setState(() => _priority = s.first),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                initialValue: _listId,
                decoration: const InputDecoration(labelText: 'List'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Inbox')),
                  for (final l in lists)
                    DropdownMenuItem(value: l.id, child: Text(l.title)),
                ],
                onChanged: (id) => setState(() => _listId = id),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                    onPressed: () {
                      ref
                          .read(taskRepositoryProvider)
                          .deleteTask(widget.task.id);
                      Navigator.pop(context);
                    },
                  ),
                  const Spacer(),
                  FilledButton(onPressed: _save, child: const Text('Save')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
