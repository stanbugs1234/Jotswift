import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'skin_manifest.dart';

/// Loads the skins bundled with the app from `assets/skins/`.
///
/// `assets/skins/catalog.json` lists the skin ids in display order, and each
/// skin lives in `assets/skins/<id>/manifest.json`. Paid skins will later be
/// downloaded from the Firestore catalog instead of bundled.
class SkinRepository {
  SkinRepository(this._bundle);

  static const catalogPath = 'assets/skins/catalog.json';
  static String manifestPath(String id) => 'assets/skins/$id/manifest.json';

  final AssetBundle _bundle;

  /// The light and dark themes for the app's own screens.
  Future<InterfaceSkins> loadInterface() async => (
    light: await _load('assets/interface/light.json'),
    dark: await _load('assets/interface/dark.json'),
  );

  Future<SkinManifest> _load(String path) async => SkinManifest.fromJson(
    jsonDecode(await _bundle.loadString(path)) as Map<String, dynamic>,
  );

  /// Returns every valid skin. A broken manifest is skipped (and logged) so
  /// one bad skin can't stop the app from starting.
  Future<List<SkinManifest>> loadBundled() async {
    final catalog = jsonDecode(await _bundle.loadString(catalogPath));
    final ids = (catalog as Map<String, dynamic>)['skins'] as List<dynamic>;

    final skins = <SkinManifest>[];
    for (final id in ids.cast<String>()) {
      try {
        final skin = await _load(manifestPath(id));
        if (skin.id != id) {
          throw SkinManifestException(id, 'manifest id is "${skin.id}"');
        }
        skins.add(skin);
      } on Object catch (e) {
        debugPrint('Skipping skin "$id": $e');
      }
    }
    return skins;
  }
}

/// The skins the app's own screens use in light and dark mode.
typedef InterfaceSkins = ({SkinManifest light, SkinManifest dark});
