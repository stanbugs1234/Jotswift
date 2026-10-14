import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase settings for the Notely project (`notely-b1aec`), taken from
/// `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`.
///
/// These values only identify the project; they are not secrets. Access to
/// data is controlled by `firestore.rules`.
abstract final class DefaultFirebaseOptions {
  /// Options for the current platform, or null if this platform hasn't been
  /// registered in Firebase yet.
  static FirebaseOptions? get currentPlatformOrNull {
    if (kIsWeb) return web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => android,
      TargetPlatform.iOS => ios,
      _ => null,
    };
  }

  static const _projectId = 'notely-b1aec';
  static const _senderId = '699023762250';
  static const _storageBucket = 'notely-b1aec.firebasestorage.app';

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyBKA8uTpXQeO2k9JoExiefMSFDEH0rnXaY',
    appId: '1:699023762250:android:fd38a358bc303a78f457b3',
    messagingSenderId: _senderId,
    projectId: _projectId,
    storageBucket: _storageBucket,
  );

  static const ios = FirebaseOptions(
    apiKey: 'AIzaSyBYQasnQZ2qC6FzDfL8CKJlMwwAQVZMRPY',
    appId: '1:699023762250:ios:2925a34545b79c7af457b3',
    messagingSenderId: _senderId,
    projectId: _projectId,
    storageBucket: _storageBucket,
    iosBundleId: 'com.notelyapp.notely',
  );

  /// Waiting on the web app's config from the Firebase console.
  static const FirebaseOptions? web = null;
}
