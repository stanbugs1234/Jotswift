import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/auth_repository.dart';
import '../entitlements/entitlements.dart';
import '../settings/user_settings_repository.dart';
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

/// The skin id saved on the signed-in user's account (null when signed out
/// or nothing has been saved yet).
final accountSkinIdProvider = StreamProvider<String?>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(userSettingsRepositoryProvider).watchActiveSkinId(uid);
});

/// The id of the skin the user picked. Saved on the device so the app opens
/// in the right skin straight away, and on the account so it follows the
/// user to their other devices.
class ActiveSkinController extends Notifier<String> {
  static const _prefsKey = 'activeSkinId';

  @override
  String build() {
    ref.listen(accountSkinIdProvider, (_, next) {
      if (!next.hasValue) return;
      final saved = next.value;
      if (saved == null) {
        // First sign-in on this account: keep the skin picked on this device.
        _saveToAccount(state);
      } else if (saved != state) {
        state = saved;
        ref.read(sharedPreferencesProvider).setString(_prefsKey, saved);
      }
    });
    return ref.watch(sharedPreferencesProvider).getString(_prefsKey) ??
        defaultSkinId;
  }

  void _saveToAccount(String skinId) {
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) return;
    // Not awaited: while offline, Firestore saves locally and syncs later.
    unawaited(
      ref
          .read(userSettingsRepositoryProvider)
          .setActiveSkinId(uid, skinId)
          .catchError((Object e) => debugPrint('Could not save skin: $e')),
    );
  }

  /// Switches to [skin]. Returns false if the user hasn't unlocked it.
  Future<bool> select(SkinManifest skin) async {
    if (!ref.read(entitlementsProvider).canUseSkin(skin)) return false;
    state = skin.id;
    await ref.read(sharedPreferencesProvider).setString(_prefsKey, skin.id);
    _saveToAccount(skin.id);
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
