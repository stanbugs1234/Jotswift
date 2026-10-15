import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../notebooks/data/notes_repository.dart' show nowMillis;
import '../domain/task.dart';

/// One user's tasks and task lists.
abstract interface class TaskRepository {
  /// Lists in order.
  Stream<List<TaskList>> watchLists();

  /// Every task, done or not.
  Stream<List<Task>> watchTasks();

  Future<TaskList> createList(String title, {required int color});

  /// Saves a renamed, recolored or moved list.
  Future<void> saveList(TaskList list);

  /// Deletes [listId] and every task in it.
  Future<void> deleteList(String listId);

  /// Adds a task at the end of its list.
  Future<Task> createTask(
    String title, {
    String? listId,
    Day? due,
    TaskPriority priority,
  });

  /// Saves [task] as it is, replacing what was stored (also brings back a
  /// deleted task).
  Future<void> saveTask(Task task);

  Future<void> deleteTask(String taskId);
}

/// Where tasks are kept, for any user.
abstract interface class TasksBackend {
  TaskRepository tasks(String uid);
}

/// New items go after everything made before them, without reading the
/// others first.
double _endOrder() => nowMillis().toDouble();

/// Stores tasks in Firestore:
///
/// ```
/// users/{uid}/taskLists/{listId}
/// users/{uid}/tasks/{taskId}
/// ```
class FirestoreTasksBackend implements TasksBackend {
  FirestoreTasksBackend(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  TaskRepository tasks(String uid) =>
      _FirestoreTasks(_firestore.doc('users/$uid'));
}

class _FirestoreTasks implements TaskRepository {
  _FirestoreTasks(this._user);

  final DocumentReference<Map<String, dynamic>> _user;

  CollectionReference<Map<String, dynamic>> get _lists =>
      _user.collection('taskLists');
  CollectionReference<Map<String, dynamic>> get _tasks =>
      _user.collection('tasks');

  @override
  Stream<List<TaskList>> watchLists() => _lists
      .orderBy('order')
      .snapshots()
      .map((s) => [for (final d in s.docs) TaskList.fromMap(d.id, d.data())]);

  @override
  Stream<List<Task>> watchTasks() => _tasks.snapshots().map(
    (s) => [for (final d in s.docs) Task.fromMap(d.id, d.data())],
  );

  @override
  Future<TaskList> createList(String title, {required int color}) async {
    final ref = _lists.doc();
    final list = TaskList(
      id: ref.id,
      title: title,
      color: color,
      order: _endOrder(),
    );
    // Not awaited: offline writes complete only when synced.
    ref.set(list.toMap()).ignore();
    return list;
  }

  @override
  Future<void> saveList(TaskList list) async =>
      _lists.doc(list.id).set(list.toMap()).ignore();

  @override
  Future<void> deleteList(String listId) async {
    final tasks = await _tasks.where('listId', isEqualTo: listId).get();
    // Batches hold at most 500 writes.
    final refs = [for (final d in tasks.docs) d.reference, _lists.doc(listId)];
    for (var i = 0; i < refs.length; i += 450) {
      final batch = _user.firestore.batch();
      for (final r in refs.skip(i).take(450)) {
        batch.delete(r);
      }
      batch.commit().ignore();
    }
  }

  @override
  Future<Task> createTask(
    String title, {
    String? listId,
    Day? due,
    TaskPriority priority = TaskPriority.none,
  }) async {
    final ref = _tasks.doc();
    final task = Task(
      id: ref.id,
      title: title,
      listId: listId,
      due: due,
      priority: priority,
      order: _endOrder(),
      createdAt: nowMillis(),
    );
    ref.set(task.toMap()).ignore();
    return task;
  }

  @override
  Future<void> saveTask(Task task) async =>
      _tasks.doc(task.id).set(task.toMap()).ignore();

  @override
  Future<void> deleteTask(String taskId) async =>
      _tasks.doc(taskId).delete().ignore();
}

/// Keeps tasks in memory. Used in tests and without Firebase.
class InMemoryTasksBackend implements TasksBackend {
  final _users = <String, _InMemoryTasks>{};

  @override
  TaskRepository tasks(String uid) =>
      _users.putIfAbsent(uid, _InMemoryTasks.new);
}

class _InMemoryTasks implements TaskRepository {
  final _lists = <String, TaskList>{};
  final _tasks = <String, Task>{};
  final _changes = StreamController<void>.broadcast();
  final _random = Random();
  var _counter = 0;
  var _order = 0.0;

  String _id() =>
      '${(_counter++).toRadixString(36)}${_random.nextInt(1 << 30).toRadixString(36)}';

  // Strictly increasing, even within one millisecond.
  double _next() => _order = max(_order + 1, _endOrder());

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    await for (final _ in _changes.stream) {
      yield read();
    }
  }

  void _changed() => _changes.add(null);

  @override
  Stream<List<TaskList>> watchLists() => _watch(
    () => _lists.values.toList()..sort((a, b) => a.order.compareTo(b.order)),
  );

  @override
  Stream<List<Task>> watchTasks() => _watch(() => _tasks.values.toList());

  @override
  Future<TaskList> createList(String title, {required int color}) async {
    final list = TaskList(
      id: _id(),
      title: title,
      color: color,
      order: _next(),
    );
    _lists[list.id] = list;
    _changed();
    return list;
  }

  @override
  Future<void> saveList(TaskList list) async {
    _lists[list.id] = list;
    _changed();
  }

  @override
  Future<void> deleteList(String listId) async {
    _lists.remove(listId);
    _tasks.removeWhere((_, t) => t.listId == listId);
    _changed();
  }

  @override
  Future<Task> createTask(
    String title, {
    String? listId,
    Day? due,
    TaskPriority priority = TaskPriority.none,
  }) async {
    final task = Task(
      id: _id(),
      title: title,
      listId: listId,
      due: due,
      priority: priority,
      order: _next(),
      createdAt: nowMillis(),
    );
    _tasks[task.id] = task;
    _changed();
    return task;
  }

  @override
  Future<void> saveTask(Task task) async {
    _tasks[task.id] = task;
    _changed();
  }

  @override
  Future<void> deleteTask(String taskId) async {
    _tasks.remove(taskId);
    _changed();
  }
}
