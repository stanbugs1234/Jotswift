import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../entitlements/entitlements.dart';
import 'font_resolver.dart';
import 'skin_engine.dart';
import 'skin_manifest.dart';

/// Overridden in `main()` once SharedPreferences has loaded.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override sharedPreferencesProvider'),
);

/// The skins shipped with the app. Overridden in `main()` after
/// [SkinRepository.loadBundled] so the first frame already has the right skin.
final bundledSkinsProvider = Provider<List<SkinManifest>>(
  (ref) => throw UnimplementedError('Override bundledSkinsProvider'),
);

final fontResolverProvider = Provider<FontResolver>(
  (ref) => const GoogleFontResolver(),
);

final skinEngineProvider = Provider<SkinEngine>(
  (ref) => SkinEngine(fonts: ref.watch(fontResolverProvider)),
);

const defaultSkinId = 'classic';

/// The id of the skin the user picked. Stored on the device for now; once
/// Firebase is connected it will also be saved to `users/{uid}.activeSkinId`.
class ActiveSkinController extends Notifier<String> {
  static const _prefsKey = 'activeSkinId';

  @override
  String build() =>
      ref.watch(sharedPreferencesProvider).getString(_prefsKey) ??
      defaultSkinId;

  /// Switches to [skin]. Returns false if the user hasn't unlocked it.
  Future<bool> select(SkinManifest skin) async {
    if (!ref.read(entitlementsProvider).canUseSkin(skin)) return false;
    state = skin.id;
    await ref.read(sharedPreferencesProvider).setString(_prefsKey, skin.id);
    return true;
  }
}

final activeSkinIdProvider = NotifierProvider<ActiveSkinController, String>(
  ActiveSkinController.new,
);

/// The skin currently in use. Falls back to the default skin if the chosen
/// one is missing or no longer unlocked.
final activeSkinProvider = Provider<SkinManifest>((ref) {
  final skins = ref.watch(bundledSkinsProvider);
  final entitlements = ref.watch(entitlementsProvider);
  final id = ref.watch(activeSkinIdProvider);

  bool usable(SkinManifest s) => entitlements.canUseSkin(s);
  return skins.where((s) => s.id == id && usable(s)).firstOrNull ??
      skins.where((s) => s.id == defaultSkinId).firstOrNull ??
      skins.firstWhere(usable);
});

final themeProvider = Provider<ThemeData>(
  (ref) =>
      ref.watch(skinEngineProvider).buildTheme(ref.watch(activeSkinProvider)),
);
