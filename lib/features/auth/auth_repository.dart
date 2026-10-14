import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthUser {
  const AuthUser({required this.uid, required this.email, this.displayName});

  final String uid;
  final String? email;
  final String? displayName;
}

class AuthException implements Exception {
  AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Sign-in for Motley. An account is required to use the app.
///
/// The Firebase implementation is added once the Firebase project exists.
/// Until then [DevAuthRepository] lets the app run end to end.
abstract interface class AuthRepository {
  AuthUser? get currentUser;
  Stream<AuthUser?> authStateChanges();

  Future<void> signInWithEmail(String email, String password);
  Future<void> createAccountWithEmail(String email, String password);
  Future<void> signInWithApple();
  Future<void> signInWithGoogle();
  Future<void> signOut();

  /// Deletes the account and all its data. Apple requires apps with
  /// accounts to offer this.
  Future<void> deleteAccount();
}

/// An in-memory stand-in for Firebase Auth. Any email and a password of
/// 6+ characters signs in. Nothing is saved between launches.
class DevAuthRepository implements AuthRepository {
  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _user;

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> authStateChanges() async* {
    yield _user;
    yield* _controller.stream;
  }

  void _set(AuthUser? user) {
    _user = user;
    _controller.add(user);
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    final trimmed = email.trim();
    if (!trimmed.contains('@')) throw AuthException('Enter a valid email.');
    if (password.length < 6) {
      throw AuthException('Password must be at least 6 characters.');
    }
    _set(AuthUser(uid: 'dev-${trimmed.hashCode}', email: trimmed));
  }

  @override
  Future<void> createAccountWithEmail(String email, String password) =>
      signInWithEmail(email, password);

  @override
  Future<void> signInWithApple() async => _set(
    const AuthUser(uid: 'dev-apple', email: null, displayName: 'Apple user'),
  );

  @override
  Future<void> signInWithGoogle() async => _set(
    const AuthUser(uid: 'dev-google', email: null, displayName: 'Google user'),
  );

  @override
  Future<void> signOut() async => _set(null);

  @override
  Future<void> deleteAccount() async => _set(null);
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => DevAuthRepository(),
);

final authStateProvider = StreamProvider<AuthUser?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);
