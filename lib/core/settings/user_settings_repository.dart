import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Names of the settings saved on the account. Each is a string field in
/// `users/{uid}` (checked by firestore.rules) and a key in the device's
/// SharedPreferences.
abstract final class SettingKeys {
  /// The default style (collection) for notebooks that don't pick one.
  static const activeSkinId = 'activeSkinId';

  /// Light, dark or following the system: "light", "dark" or "system".
  static const appearance = 'appearance';
}

/// Per-account settings that follow the user across devices, stored in
/// `users/{uid}`.
abstract interface class UserSettingsRepository {
  /// The setting saved on the account, or null if none has been saved.
  Stream<String?> watch(String uid, String key);
  Future<void> set(String uid, String key, String value);

  /// Whether the account is marked as a tester. Only the server sets this.
  Stream<bool> watchTester(String uid);

  /// The account's `entitlements` map (what it has bought), or null. Only
  /// the server sets this. Timestamps arrive as [DateTime]s.
  Stream<Map<String, Object?>?> watchEntitlements(String uid);
}

class FirestoreUserSettingsRepository implements UserSettingsRepository {
  FirestoreUserSettingsRepository(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _firestore.doc('users/$uid');

  @override
  Stream<String?> watch(String uid, String key) =>
      _doc(uid).snapshots().map((snap) => snap.data()?[key] as String?);

  @override
  Stream<bool> watchTester(String uid) =>
      _doc(uid).snapshots().map((snap) => snap.data()?['tester'] == true);

  @override
  Stream<Map<String, Object?>?> watchEntitlements(String uid) =>
      _doc(uid).snapshots().map((snap) {
        final map = snap.data()?['entitlements'];
        if (map is! Map) return null;
        return {
          for (final MapEntry(:key, :value) in map.entries)
            '$key': value is Timestamp ? value.toDate() : value,
        };
      });

  @override
  Future<void> set(String uid, String key, String value) => _doc(uid).set({
    key: value,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

/// Keeps settings in memory. Used with the stand-in sign-in and in tests.
class InMemoryUserSettingsRepository implements UserSettingsRepository {
  final _values = <(String, String), String>{};
  final _changes = StreamController<(String, String)>.broadcast();

  @override
  Stream<String?> watch(String uid, String key) async* {
    yield _values[(uid, key)];
    yield* _changes.stream.where((k) => k == (uid, key)).map((k) => _values[k]);
  }

  @override
  Future<void> set(String uid, String key, String value) async {
    _values[(uid, key)] = value;
    _changes.add((uid, key));
  }

  final _testers = <String>{};

  /// Marks [uid] as a tester, as the server would.
  void setTester(String uid, {required bool tester}) {
    tester ? _testers.add(uid) : _testers.remove(uid);
    _changes.add((uid, 'tester'));
  }

  final _entitlements = <String, Map<String, Object?>>{};

  /// Sets what [uid] has bought, as the server would.
  void setEntitlements(String uid, Map<String, Object?>? entitlements) {
    entitlements == null
        ? _entitlements.remove(uid)
        : _entitlements[uid] = entitlements;
    _changes.add((uid, 'entitlements'));
  }

  @override
  Stream<Map<String, Object?>?> watchEntitlements(String uid) async* {
    yield _entitlements[uid];
    yield* _changes.stream
        .where((k) => k == (uid, 'entitlements'))
        .map((_) => _entitlements[uid]);
  }

  @override
  Stream<bool> watchTester(String uid) async* {
    yield _testers.contains(uid);
    yield* _changes.stream
        .where((k) => k == (uid, 'tester'))
        .map((_) => _testers.contains(uid));
  }
}

final userSettingsRepositoryProvider = Provider<UserSettingsRepository>(
  (ref) => InMemoryUserSettingsRepository(),
);
