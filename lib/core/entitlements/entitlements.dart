import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/catalog_item.dart';
import '../skins/skin_manifest.dart';

/// What the signed-in user has paid for.
///
/// Until the store is built (roadmap Phase 4), everyone has no purchases.
/// Later this will be read from `users/{uid}.entitlements`, which a Cloud
/// Function fills in from RevenueCat.
class Entitlements {
  const Entitlements({
    this.pro = false,
    this.ownedSkinIds = const {},
    this.products = const {},
    this.grants = const {},
  });

  static const none = Entitlements();

  final bool pro;
  final Set<String> ownedSkinIds;

  /// Store products bought (packs, bundles).
  final Set<String> products;

  /// Catalog items given for free (promotions, support).
  final Set<String> grants;

  /// Any one way of unlocking [item] is enough (docs/skins-plan.md §7).
  bool canUseCatalogItem(CatalogItem item) =>
      item.unlock.free ||
      (item.unlock.pro && pro) ||
      item.unlock.products.any(products.contains) ||
      grants.contains(item.id);

  bool canUseSkin(SkinManifest skin) => switch (skin.tier) {
    SkinTier.free => true,
    SkinTier.paid => ownedSkinIds.contains(skin.id),
    SkinTier.pro => pro,
  };
}

final entitlementsProvider = Provider<Entitlements>((ref) => Entitlements.none);
