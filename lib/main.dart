import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/skins/skin_providers.dart';
import 'core/skins/skin_repository.dart';

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
      ],
      child: const NotelyApp(),
    ),
  );
}
