import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Per-account settings that follow the user across devices, stored in
/// `users/{uid}`.
abstract interface class UserSettingsRepository {
  /// The skin id saved on the account, or null if none has been saved.
  Stream<String?> watchActiveSkinId(String uid);
  Future<void> setActiveSkinId(String uid, String skinId);
}

class FirestoreUserSettingsRepository implements UserSettingsRepository {
  FirestoreUserSettingsRepository(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _firestore.doc('users/$uid');

  @override
  Stream<String?> watchActiveSkinId(String uid) =>
      _doc(uid)
          .snapshots()
          .map((snap) => snap.data()?['activeSkinId'] as String?);

  @override
  Future<void> setActiveSkinId(String uid, String skinId) => _doc(uid).set({
    'activeSkinId': skinId,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

/// Keeps settings in memory. Used with the stand-in sign-in and in tests.
class InMemoryUserSettingsRepository implements UserSettingsRepository {
  final _skins = <String, String>{};
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String?> watchActiveSkinId(String uid) async* {
    yield _skins[uid];
    yield* _changes.stream.where((u) => u == uid).map((u) => _skins[u]);
  }

  @override
  Future<void> setActiveSkinId(String uid, String skinId) async {
    _skins[uid] = skinId;
    _changes.add(uid);
  }
}

final userSettingsRepositoryProvider = Provider<UserSettingsRepository>(
  (ref) => InMemoryUserSettingsRepository(),
);
