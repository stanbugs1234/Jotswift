import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/notebooks/notes_providers.dart';
import '../entitlements/entitlements.dart';
import '../settings/synced_setting.dart';
import '../settings/user_settings_repository.dart';
import 'font_resolver.dart';
import 'notely_skin.dart';
import 'skin_engine.dart';
import 'skin_manifest.dart';
import 'skin_repository.dart';

export '../settings/synced_setting.dart' show sharedPreferencesProvider;

/// The skins shipped with the app. Each one is a notebook style: the paper,
/// ink palette and accent font that notebook pages are drawn in.
/// Overridden in `main()` after [SkinRepository.loadBundled].
final bundledSkinsProvider = Provider<List<SkinManifest>>(
  (ref) => throw UnimplementedError('Override bundledSkinsProvider'),
);

/// The light and dark themes of the app's own screens. Overridden in
/// `main()` after [SkinRepository.loadInterface].
final interfaceSkinsProvider = Provider<InterfaceSkins>(
  (ref) => throw UnimplementedError('Override interfaceSkinsProvider'),
);

final fontResolverProvider = Provider<FontResolver>(
  (ref) => const GoogleFontResolver(),
);

final skinEngineProvider = Provider<SkinEngine>(
  (ref) => SkinEngine(fonts: ref.watch(fontResolverProvider)),
);

final lightThemeProvider = Provider<ThemeData>(
  (ref) => ref
      .watch(skinEngineProvider)
      .buildTheme(ref.watch(interfaceSkinsProvider).light),
);

final darkThemeProvider = Provider<ThemeData>(
  (ref) => ref
      .watch(skinEngineProvider)
      .buildTheme(ref.watch(interfaceSkinsProvider).dark),
);

const defaultSkinId = 'classic';

/// The id of the style the user picked for their notebooks. Notebooks that
/// don't choose their own style use it.
class ActiveSkinController extends SyncedSetting {
  @override
  String get key => SettingKeys.activeSkinId;

  @override
  String get defaultValue => defaultSkinId;

  /// Switches to [skin]. Returns false if the user hasn't unlocked it.
  Future<bool> select(SkinManifest skin) async {
    if (!ref.read(entitlementsProvider).canUseSkin(skin)) return false;
    await save(skin.id);
    return true;
  }
}

final activeSkinIdProvider = NotifierProvider<ActiveSkinController, String>(
  ActiveSkinController.new,
);

/// The default notebook style. Falls back to the default skin if the chosen
/// one is missing or no longer unlocked.
final activeSkinProvider = Provider<SkinManifest>(
  (ref) => _usableSkin(ref, ref.watch(activeSkinIdProvider)),
);

/// The style a notebook's pages are drawn in: its own, else the default.
/// A notebook keeps its style even if that style is no longer unlocked.
final notebookSkinProvider = Provider.family<SkinManifest, String>((
  ref,
  notebookId,
) {
  final own = ref.watch(notebookProvider(notebookId)).value?.collectionId;
  return ref
          .watch(bundledSkinsProvider)
          .where((s) => s.id == own)
          .firstOrNull ??
      ref.watch(activeSkinProvider);
});

/// The page style of a notebook, ready to put in a [Theme].
final notebookStyleProvider = Provider.family<NotelySkin, String>(
  (ref, notebookId) => ref
      .watch(skinEngineProvider)
      .buildNotelySkin(ref.watch(notebookSkinProvider(notebookId))),
);

/// The style of a page's notebook (the default style while it loads).
final pageStyleProvider = Provider.family<NotelySkin, String>((ref, pageId) {
  final notebookId = ref.watch(pageProvider(pageId)).value?.notebookId;
  return notebookId == null
      ? ref.watch(defaultStyleProvider)
      : ref.watch(notebookStyleProvider(notebookId));
});

/// The default notebook style, ready to put in a [Theme].
final defaultStyleProvider = Provider<NotelySkin>(
  (ref) => ref
      .watch(skinEngineProvider)
      .buildNotelySkin(ref.watch(activeSkinProvider)),
);

/// The notebook styles this user can pick.
final usableSkinsProvider = Provider<List<SkinManifest>>((ref) {
  final entitlements = ref.watch(entitlementsProvider);
  return ref
      .watch(bundledSkinsProvider)
      .where(entitlements.canUseSkin)
      .toList();
});

SkinManifest _usableSkin(Ref ref, String id, {SkinManifest? fallback}) {
  final skins = ref.watch(bundledSkinsProvider);
  final entitlements = ref.watch(entitlementsProvider);
  bool usable(SkinManifest s) => entitlements.canUseSkin(s);
  return skins.where((s) => s.id == id && usable(s)).firstOrNull ??
      fallback ??
      skins.where((s) => s.id == defaultSkinId).firstOrNull ??
      skins.firstWhere(usable);
}
