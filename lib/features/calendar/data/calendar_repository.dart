import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/calendar_info.dart';

/// One user's calendars (Personal, Work, ...). Personal is listed even
/// before it's saved, so the app never has to write anything to start.
abstract interface class CalendarRepository {
  /// Every calendar, Personal included, in their order.
  Stream<List<CalendarInfo>> watchCalendars();

  /// Saves [calendar], giving it an id if it has none (`id == ''`).
  Future<CalendarInfo> saveCalendar(CalendarInfo calendar);

  Future<void> deleteCalendar(String calendarId);
}

abstract interface class CalendarsBackend {
  CalendarRepository calendars(String uid);
}

/// Adds Personal if it isn't saved yet, and sorts.
List<CalendarInfo> withPersonal(Iterable<CalendarInfo> saved) {
  final list = [...saved];
  if (!list.any((c) => c.id == personalCalendarId)) {
    list.insert(0, CalendarInfo.personal);
  }
  return list..sort((a, b) {
    final byOrder = a.order.compareTo(b.order);
    if (byOrder != 0) return byOrder;
    if (a.id == personalCalendarId) return -1;
    if (b.id == personalCalendarId) return 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
}

/// Stores calendars in Firestore at `users/{uid}/calendars/{calendarId}`.
class FirestoreCalendarsBackend implements CalendarsBackend {
  FirestoreCalendarsBackend(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  CalendarRepository calendars(String uid) =>
      _FirestoreCalendars(_firestore.doc('users/$uid').collection('calendars'));
}

class _FirestoreCalendars implements CalendarRepository {
  _FirestoreCalendars(this._calendars);

  final CollectionReference<Map<String, dynamic>> _calendars;

  @override
  Stream<List<CalendarInfo>> watchCalendars() => _calendars.snapshots().map(
    (s) => withPersonal([
      for (final d in s.docs) ?CalendarInfo.fromMap(d.id, d.data()),
    ]),
  );

  @override
  Future<CalendarInfo> saveCalendar(CalendarInfo calendar) async {
    final ref = calendar.id.isEmpty
        ? _calendars.doc()
        : _calendars.doc(calendar.id);
    final saved = CalendarInfo.fromMap(ref.id, calendar.toMap())!;
    // Not awaited: offline writes complete only when synced.
    ref.set(saved.toMap()).ignore();
    return saved;
  }

  @override
  Future<void> deleteCalendar(String calendarId) async =>
      _calendars.doc(calendarId).delete().ignore();
}

/// Keeps calendars in memory. Used in tests and without Firebase.
class InMemoryCalendarsBackend implements CalendarsBackend {
  final _users = <String, _InMemoryCalendars>{};

  @override
  CalendarRepository calendars(String uid) =>
      _users.putIfAbsent(uid, _InMemoryCalendars.new);
}

class _InMemoryCalendars implements CalendarRepository {
  final _calendars = <String, CalendarInfo>{};
  final _changes = StreamController<void>.broadcast();
  final _random = Random();

  @override
  Stream<List<CalendarInfo>> watchCalendars() async* {
    yield withPersonal(_calendars.values);
    await for (final _ in _changes.stream) {
      yield withPersonal(_calendars.values);
    }
  }

  @override
  Future<CalendarInfo> saveCalendar(CalendarInfo calendar) async {
    final id = calendar.id.isEmpty
        ? 'c${_random.nextInt(1 << 30).toRadixString(36)}'
        : calendar.id;
    final saved = CalendarInfo.fromMap(id, calendar.toMap())!;
    _calendars[id] = saved;
    _changes.add(null);
    return saved;
  }

  @override
  Future<void> deleteCalendar(String calendarId) async {
    _calendars.remove(calendarId);
    _changes.add(null);
  }
}
