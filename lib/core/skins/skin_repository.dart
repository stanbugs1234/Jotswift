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

  /// Returns every valid skin. A broken manifest is skipped (and logged) so
  /// one bad skin can't stop the app from starting.
  Future<List<SkinManifest>> loadBundled() async {
    final catalog = jsonDecode(await _bundle.loadString(catalogPath));
    final ids = (catalog as Map<String, dynamic>)['skins'] as List<dynamic>;

    final skins = <SkinManifest>[];
    for (final id in ids.cast<String>()) {
      try {
        final json = jsonDecode(await _bundle.loadString(manifestPath(id)));
        final skin = SkinManifest.fromJson(json as Map<String, dynamic>);
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
