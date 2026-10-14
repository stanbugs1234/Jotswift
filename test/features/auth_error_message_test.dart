import 'package:flutter_test/flutter_test.dart';
import 'package:notely/features/auth/firebase_auth_repository.dart';

void main() {
  test('common Firebase errors get friendly messages', () {
    expect(authErrorMessage('invalid-credential'), 'Wrong email or password.');
    expect(authErrorMessage('wrong-password'), 'Wrong email or password.');
    expect(
      authErrorMessage('email-already-in-use'),
      contains('Try signing in'),
    );
    expect(authErrorMessage('weak-password'), contains('6 characters'));
    expect(authErrorMessage('popup-closed-by-user'), 'Sign-in was cancelled.');
  });

  test('unknown errors include the code to help with support', () {
    expect(authErrorMessage('some-new-code'), contains('some-new-code'));
  });
}
