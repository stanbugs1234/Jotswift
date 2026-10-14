import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/settings/user_settings_repository.dart';
import 'core/skins/skin_providers.dart';
import 'core/skins/skin_repository.dart';
import 'features/auth/auth_repository.dart';
import 'features/auth/firebase_auth_repository.dart';
import 'features/notebooks/data/firestore_notes_backend.dart';
import 'features/notebooks/notes_providers.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load these before the first frame so the app opens in the user's skin.
  final prefs = await SharedPreferences.getInstance();
  final skins = await SkinRepository(rootBundle).loadBundled();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        bundledSkinsProvider.overrideWithValue(skins),
        ...await _backendOverrides(),
      ],
      child: const NotelyApp(),
    ),
  );
}

/// Uses Firebase when this platform is registered in Firebase; otherwise
/// keeps the stand-in sign-in so the app still runs.
Future<List<Override>> _backendOverrides() async {
  final options = DefaultFirebaseOptions.currentPlatformOrNull;
  if (options == null) {
    debugPrint('Firebase is not set up for this platform; using dev sign-in.');
    return const [];
  }

  await Firebase.initializeApp(options: options);
  final auth = FirebaseAuth.instance;
  final firestore = FirebaseFirestore.instance;
  // Wait for the saved session so signed-in users skip the sign-in screen.
  await auth.authStateChanges().first;

  return [
    authRepositoryProvider.overrideWithValue(
      FirebaseAuthRepository(auth, firestore),
    ),
    userSettingsRepositoryProvider.overrideWithValue(
      FirestoreUserSettingsRepository(firestore),
    ),
    notesBackendProvider.overrideWithValue(FirestoreNotesBackend(firestore)),
  ];
}
