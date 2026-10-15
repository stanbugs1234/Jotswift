import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/event.dart';

/// One user's calendar events.
abstract interface class EventRepository {
  /// Every event. Repeating events are stored once; see
  /// [occurrencesBetween].
  Stream<List<CalendarEvent>> watchEvents();

  /// Saves [event], giving it an id if it has none (`id == ''`). Returns the
  /// saved event.
  Future<CalendarEvent> saveEvent(CalendarEvent event);

  Future<void> deleteEvent(String eventId);
}

abstract interface class EventsBackend {
  EventRepository events(String uid);
}

/// Stores events in Firestore at `users/{uid}/events/{eventId}`.
class FirestoreEventsBackend implements EventsBackend {
  FirestoreEventsBackend(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  EventRepository events(String uid) =>
      _FirestoreEvents(_firestore.doc('users/$uid').collection('events'));
}

class _FirestoreEvents implements EventRepository {
  _FirestoreEvents(this._events);

  final CollectionReference<Map<String, dynamic>> _events;

  @override
  Stream<List<CalendarEvent>> watchEvents() => _events.snapshots().map(
    (s) => [for (final d in s.docs) ?CalendarEvent.fromMap(d.id, d.data())],
  );

  @override
  Future<CalendarEvent> saveEvent(CalendarEvent event) async {
    final ref = event.id.isEmpty ? _events.doc() : _events.doc(event.id);
    final saved = CalendarEvent.fromMap(ref.id, event.toMap())!;
    // Not awaited: offline writes complete only when synced.
    ref.set(saved.toMap()).ignore();
    return saved;
  }

  @override
  Future<void> deleteEvent(String eventId) async =>
      _events.doc(eventId).delete().ignore();
}

/// Keeps events in memory. Used in tests and without Firebase.
class InMemoryEventsBackend implements EventsBackend {
  final _users = <String, _InMemoryEvents>{};

  @override
  EventRepository events(String uid) =>
      _users.putIfAbsent(uid, _InMemoryEvents.new);
}

class _InMemoryEvents implements EventRepository {
  final _events = <String, CalendarEvent>{};
  final _changes = StreamController<void>.broadcast();
  final _random = Random();
  var _counter = 0;

  @override
  Stream<List<CalendarEvent>> watchEvents() async* {
    yield _events.values.toList();
    await for (final _ in _changes.stream) {
      yield _events.values.toList();
    }
  }

  @override
  Future<CalendarEvent> saveEvent(CalendarEvent event) async {
    final id = event.id.isEmpty
        ? '${(_counter++).toRadixString(36)}${_random.nextInt(1 << 30).toRadixString(36)}'
        : event.id;
    final saved = CalendarEvent.fromMap(id, event.toMap())!;
    _events[id] = saved;
    _changes.add(null);
    return saved;
  }

  @override
  Future<void> deleteEvent(String eventId) async {
    _events.remove(eventId);
    _changes.add(null);
  }
}
