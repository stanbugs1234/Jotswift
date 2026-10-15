import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/auth_repository.dart';
import 'user_settings_repository.dart';

/// Overridden in `main()` once SharedPreferences has loaded.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override sharedPreferencesProvider'),
);

/// A setting's value on the signed-in user's account (null when signed out
/// or nothing has been saved yet).
final accountSettingProvider = StreamProvider.family<String?, String>((
  ref,
  key,
) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(userSettingsRepositoryProvider).watch(uid, key);
});

/// A setting saved on the device, so the app opens with it straight away,
/// and on the account, so it follows the user to their other devices.
abstract class SyncedSetting extends Notifier<String> {
  /// The key in SharedPreferences and the field in `users/{uid}`.
  String get key;
  String get defaultValue;

  @override
  String build() {
    ref.listen(accountSettingProvider(key), (_, next) {
      if (!next.hasValue) return;
      final saved = next.value;
      if (saved == null) {
        // First sign-in on this account: keep this device's value.
        _saveToAccount(state);
      } else if (saved != state) {
        state = saved;
        ref.read(sharedPreferencesProvider).setString(key, saved);
      }
    });
    return ref.watch(sharedPreferencesProvider).getString(key) ?? defaultValue;
  }

  /// Changes the setting on this device and the account.
  @protected
  Future<void> save(String value) async {
    state = value;
    await ref.read(sharedPreferencesProvider).setString(key, value);
    _saveToAccount(value);
  }

  void _saveToAccount(String value) {
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) return;
    // Not awaited: while offline, Firestore saves locally and syncs later.
    unawaited(
      ref
          .read(userSettingsRepositoryProvider)
          .set(uid, key, value)
          .catchError((Object e) => debugPrint('Could not save $key: $e')),
    );
  }
}
