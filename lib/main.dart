import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/catalog/catalog_providers.dart';
import 'core/catalog/catalog_repository.dart';
import 'core/catalog/pack_cache.dart';
import 'core/catalog/pack_disk.dart';
import 'core/purchases/purchases_providers.dart';
import 'core/purchases/revenuecat_purchases.dart';
import 'core/settings/user_settings_repository.dart';
import 'core/skins/skin_providers.dart';
import 'core/skins/skin_repository.dart';
import 'features/auth/auth_repository.dart';
import 'features/auth/firebase_auth_repository.dart';
import 'features/calendar/calendar_providers.dart';
import 'features/calendar/data/event_repository.dart';
import 'features/notebooks/data/cover_photos.dart';
import 'features/notebooks/data/firestore_notes_backend.dart';
import 'features/notebooks/notes_providers.dart';
import 'features/reminders/local_reminders.dart';
import 'features/reminders/reminders.dart';
import 'features/tasks/data/task_repository.dart';
import 'features/tasks/task_providers.dart';
import 'firebase_options.dart';

Future<void> main() async {
  // On the web, addresses look like /notebooks/abc (not /#/notebooks/abc),
  // so links and refreshes open the same screen. Hosting sends every path
  // to index.html (firebase.json).
  usePathUrlStrategy();
  // Screens opened with push() show their address too.
  GoRouter.optionURLReflectsImperativeAPIs = true;
  WidgetsFlutterBinding.ensureInitialized();

  // Load these before the first frame so the app opens with the user's
  // appearance and notebook style.
  final prefs = await SharedPreferences.getInstance();
  final skinRepository = SkinRepository(rootBundle);
  final skins = await skinRepository.loadBundled();
  final interface = await skinRepository.loadInterface();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        bundledSkinsProvider.overrideWithValue(skins),
        interfaceSkinsProvider.overrideWithValue(interface),
        ...await _backendOverrides(),
        ...await _reminderOverrides(),
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
    authRepositoryProvider.overrideWithValue(FirebaseAuthRepository(auth)),
    userSettingsRepositoryProvider.overrideWithValue(
      FirestoreUserSettingsRepository(firestore),
    ),
    notesBackendProvider.overrideWithValue(FirestoreNotesBackend(firestore)),
    tasksBackendProvider.overrideWithValue(FirestoreTasksBackend(firestore)),
    eventsBackendProvider.overrideWithValue(FirestoreEventsBackend(firestore)),
    coverPhotoStoreProvider.overrideWithValue(
      FirebaseCoverPhotoStore(FirebaseStorage.instance),
    ),
    catalogRepositoryProvider.overrideWithValue(
      FirestoreCatalogRepository(firestore),
    ),
    purchasesClientProvider.overrideWithValue(createPurchasesClient()),
    packCacheProvider.overrideWithValue(
      PackCache(
        FirebasePackDownloader(FirebaseStorage.instance),
        createPackDisk(),
      ),
    ),
  ];
}

/// Local notifications on iOS and Android; none elsewhere.
Future<List<Override>> _reminderOverrides() async {
  if (kIsWeb ||
      !(defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android)) {
    return const [];
  }
  try {
    return [
      reminderServiceProvider.overrideWithValue(await LocalReminders.create()),
    ];
  } catch (e) {
    debugPrint('Reminders are off: $e');
    return const [];
  }
}
