import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'synced_setting.dart';
import 'user_settings_repository.dart';

/// Light, dark, or following the device: the look of the app's own
/// screens. Notebook pages keep their own paper either way.
class AppearanceController extends SyncedSetting {
  @override
  String get key => SettingKeys.appearance;

  @override
  String get defaultValue => ThemeMode.system.name;

  Future<void> set(ThemeMode mode) => save(mode.name);
}

final appearanceProvider = NotifierProvider<AppearanceController, String>(
  AppearanceController.new,
);

/// The saved appearance as a [ThemeMode]. Unknown values (e.g. from a newer
/// app version) follow the system.
final themeModeProvider = Provider<ThemeMode>((ref) {
  final name = ref.watch(appearanceProvider);
  return ThemeMode.values.where((m) => m.name == name).firstOrNull ??
      ThemeMode.system;
});
