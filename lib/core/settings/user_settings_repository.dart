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
}

final userSettingsRepositoryProvider = Provider<UserSettingsRepository>(
  (ref) => InMemoryUserSettingsRepository(),
);
