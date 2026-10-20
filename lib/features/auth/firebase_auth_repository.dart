import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';

import 'auth_repository.dart';

/// Sign-in backed by Firebase Authentication.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth);

  final fb.FirebaseAuth _auth;

  static AuthUser? _toUser(fb.User? user) => user == null
      ? null
      : AuthUser(
          uid: user.uid,
          email: user.email,
          displayName: user.displayName,
        );

  @override
  AuthUser? get currentUser => _toUser(_auth.currentUser);

  @override
  Stream<AuthUser?> authStateChanges() => _auth.authStateChanges().map(_toUser);

  /// Runs [action], turning Firebase errors into readable [AuthException]s.
  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException(authErrorMessage(e.code));
    }
  }

  @override
  Future<void> signInWithEmail(String email, String password) => _guard(
    () => _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    ),
  );

  @override
  Future<void> createAccountWithEmail(String email, String password) => _guard(
    () => _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    ),
  );

  Future<void> _signInWithProvider(fb.AuthProvider provider) => _guard(
    () => kIsWeb
        ? _auth.signInWithPopup(provider)
        : _auth.signInWithProvider(provider),
  );

  @override
  Future<void> signInWithApple() => _signInWithProvider(fb.AppleAuthProvider());

  @override
  Future<void> signInWithGoogle() =>
      _signInWithProvider(fb.GoogleAuthProvider());

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));

  @override
  Future<void> deleteAccount() => _guard(() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final providers = {for (final p in user.providerData) p.providerId};
    if (!kIsWeb && providers.contains('apple.com')) {
      // Apple requires apps to revoke their Sign in with Apple token when
      // the account is deleted. Signing in again gives a fresh code to
      // revoke it with, and is the recent sign-in Firebase needs to delete.
      final again = await user.reauthenticateWithProvider(
        fb.AppleAuthProvider(),
      );
      final code = again.additionalUserInfo?.authorizationCode;
      if (code != null) await _auth.revokeTokenWithAuthorizationCode(code);
    } else if (!kIsWeb && providers.contains('google.com')) {
      await user.reauthenticateWithProvider(fb.GoogleAuthProvider());
    }
    // The deleteUserData Cloud Function then erases everything the account
    // owns (firebase/functions/src/accounts.ts). Deleting the account
    // first means a "sign in again" refusal leaves the data untouched.
    await user.delete();
  });
}

/// A friendly message for a Firebase Auth error code.
String authErrorMessage(String code) => switch (code) {
  'invalid-email' => 'Enter a valid email.',
  'user-disabled' => 'This account has been disabled.',
  'user-not-found' ||
  'wrong-password' ||
  'invalid-credential' => 'Wrong email or password.',
  'email-already-in-use' =>
    'There is already an account with this email. Try signing in.',
  'weak-password' => 'Password must be at least 6 characters.',
  'too-many-requests' => 'Too many attempts. Please wait a moment and retry.',
  'network-request-failed' => 'No internet connection.',
  'popup-closed-by-user' ||
  'cancelled-popup-request' ||
  'web-context-canceled' ||
  'canceled' => 'Sign-in was cancelled.',
  'user-mismatch' => 'Sign in with the account you are deleting.',
  'operation-not-allowed' => 'This sign-in method is not turned on yet.',
  'missing-email' => 'Enter your email first.',
  'requires-recent-login' =>
    'For your security, sign out and back in, then try again.',
  _ => 'Something went wrong ($code). Please try again.',
};
