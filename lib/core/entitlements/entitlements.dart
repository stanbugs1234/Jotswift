import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../skins/skin_manifest.dart';

/// What the signed-in user has paid for.
///
/// Until the store is built (roadmap Phase 4), everyone has no purchases.
/// Later this will be read from `users/{uid}.entitlements`, which a Cloud
/// Function fills in from RevenueCat.
class Entitlements {
  const Entitlements({this.pro = false, this.ownedSkinIds = const {}});

  static const none = Entitlements();

  final bool pro;
  final Set<String> ownedSkinIds;

  bool canUseSkin(SkinManifest skin) => switch (skin.tier) {
    SkinTier.free => true,
    SkinTier.paid => ownedSkinIds.contains(skin.id),
    SkinTier.pro => pro,
  };
}

final entitlementsProvider = Provider<Entitlements>((ref) => Entitlements.none);
