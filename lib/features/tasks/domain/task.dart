import 'package:flutter/foundation.dart';

/// A calendar day with no time or time zone, such as a due date. Stored
/// as "2026-10-14", so it's the same day everywhere.
@immutable
class Day implements Comparable<Day> {
  const Day(this.year, this.month, this.day);

  factory Day.of(DateTime t) => Day(t.year, t.month, t.day);

  factory Day.today() => Day.of(DateTime.now());

  /// Reads "YYYY-MM-DD". Returns null for anything else.
  static Day? tryParse(Object? value) {
    if (value is! String) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (m == null) return null;
    final day = Day(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
    // Rejects impossible dates such as February 30.
    return Day.of(day.toDateTime()) == day ? day : null;
  }

  final int year;
  final int month;
  final int day;

  /// Midnight at the start of this day, local time.
  DateTime toDateTime() => DateTime(year, month, day);

  Day addDays(int days) => Day.of(DateTime(year, month, day + days));

  /// Whole days from this day to [other] (negative if [other] is earlier).
  int daysUntil(Day other) => DateTime.utc(
    other.year,
    other.month,
    other.day,
  ).difference(DateTime.utc(year, month, day)).inDays;

  bool isBefore(Day other) => compareTo(other) < 0;
  bool isAfter(Day other) => compareTo(other) > 0;

  @override
  int compareTo(Day other) =>
      (year - other.year) * 10000 +
      (month - other.month) * 100 +
      (day - other.day);

  @override
  bool operator ==(Object other) =>
      other is Day &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}

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
      other.completedAt == completedAt;

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
  );
}
