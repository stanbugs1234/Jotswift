import 'package:flutter/foundation.dart';

import '../../../core/day.dart';

export '../../../core/day.dart';

enum TaskPriority {
  none,
  low,
  medium,
  high;

  static TaskPriority fromInt(Object? value) =>
      value is int && value >= 0 && value < values.length
      ? values[value]
      : none;
}

/// A list of tasks, such as "Groceries". Tasks without a list are in the
/// Inbox, which isn't stored.
@immutable
class TaskList {
  const TaskList({
    required this.id,
    required this.title,
    required this.color,
    required this.order,
  });

  static TaskList fromMap(String id, Map<String, dynamic> map) => TaskList(
    id: id,
    title: map['title'] as String? ?? 'List',
    color: map['color'] as int? ?? 0xFF5C6BC0,
    order: (map['order'] as num?)?.toDouble() ?? 0,
  );

  final String id;
  final String title;

  /// ARGB.
  final int color;
  final double order;

  Map<String, Object?> toMap() => {
    'title': title,
    'color': color,
    'order': order,
  };

  TaskList copyWith({String? title, int? color, double? order}) => TaskList(
    id: id,
    title: title ?? this.title,
    color: color ?? this.color,
    order: order ?? this.order,
  );

  @override
  bool operator ==(Object other) =>
      other is TaskList &&
      other.id == id &&
      other.title == title &&
      other.color == color &&
      other.order == order;

  @override
  int get hashCode => Object.hash(id, title, color, order);
}

/// A typed to-do item.
@immutable
class Task {
  const Task({
    required this.id,
    required this.title,
    required this.order,
    required this.createdAt,
    this.notes = '',
    this.done = false,
    this.due,
    this.priority = TaskPriority.none,
    this.listId,
    this.completedAt,
    this.remindAt,
  });

  static Task fromMap(String id, Map<String, dynamic> map) => Task(
    id: id,
    title: map['title'] as String? ?? '',
    notes: map['notes'] as String? ?? '',
    done: map['done'] == true,
    due: Day.tryParse(map['due']),
    priority: TaskPriority.fromInt(map['priority']),
    listId: map['listId'] as String?,
    order: (map['order'] as num?)?.toDouble() ?? 0,
    createdAt: map['createdAt'] as int? ?? 0,
    completedAt: map['completedAt'] as int?,
    remindAt: switch (map['remindAt']) {
      final int m when m >= 0 && m < 24 * 60 => m,
      _ => null,
    },
  );

  final String id;
  final String title;
  final String notes;
  final bool done;

  /// The day it's due, if any.
  final Day? due;
  final TaskPriority priority;

  /// Its list, or null for the Inbox.
  final String? listId;

  /// Position within its list (smaller first).
  final double order;

  /// Milliseconds since the epoch.
  final int createdAt;
  final int? completedAt;

  /// Minutes after midnight on [due] to send a reminder, if any.
  final int? remindAt;

  /// When to remind, local time (null without a due day or reminder).
  DateTime? get reminderTime => due == null || remindAt == null
      ? null
      : due!.toDateTime().add(Duration(minutes: remindAt!));

  Map<String, Object?> toMap() => {
    'title': title,
    'notes': notes,
    'done': done,
    'due': ?due?.toString(),
    'priority': priority.index,
    'listId': ?listId,
    'order': order,
    'createdAt': createdAt,
    'completedAt': ?completedAt,
    'remindAt': ?remindAt,
  };

  /// A changed copy. Pass `due: null` / `listId: null` with [clearDue] /
  /// [toInbox] to remove them.
  Task copyWith({
    String? title,
    String? notes,
    bool? done,
    Day? due,
    bool clearDue = false,
    TaskPriority? priority,
    String? listId,
    bool toInbox = false,
    double? order,
    int? completedAt,
    bool clearCompletedAt = false,
    int? remindAt,
    bool clearRemindAt = false,
  }) => Task(
    id: id,
    title: title ?? this.title,
    notes: notes ?? this.notes,
    done: done ?? this.done,
    due: clearDue ? null : due ?? this.due,
    priority: priority ?? this.priority,
    listId: toInbox ? null : listId ?? this.listId,
    order: order ?? this.order,
    createdAt: createdAt,
    completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
    remindAt: clearRemindAt ? null : remindAt ?? this.remindAt,
  );

  @override
  bool operator ==(Object other) =>
      other is Task &&
      other.id == id &&
      other.title == title &&
      other.notes == notes &&
      other.done == done &&
      other.due == due &&
      other.priority == priority &&
      other.listId == listId &&
      other.order == order &&
      other.createdAt == createdAt &&
      other.completedAt == completedAt &&
      other.remindAt == remindAt;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    notes,
    done,
    due,
    priority,
    listId,
    order,
    createdAt,
    completedAt,
    remindAt,
  );
}
