import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_repository.dart';
import '../catalog/catalog_item.dart';
import '../catalog/catalog_providers.dart' show isTesterProvider;
import '../purchases/purchases_client.dart';
import '../purchases/purchases_providers.dart';
import '../settings/user_settings_repository.dart';
import '../skins/skin_manifest.dart';

/// What the signed-in user has paid for.
///
/// Read from `users/{uid}.entitlements`, which a Cloud Function fills in
/// from RevenueCat, merged with the store receipt on this device so a
/// purchase unlocks at once.
@immutable
class Entitlements {
  const Entitlements({
    this.pro = false,
    this.proUntil,
    this.products = const {},
    this.grants = const {},
  });

  /// Reads `users/{uid}.entitlements`. Pro that ended before [now] is off.
  factory Entitlements.fromMap(Object? map, {required DateTime now}) {
    if (map is! Map) return none;
    final until = switch (map['proUntil']) {
      final String s => DateTime.tryParse(s),
      final DateTime d => d,
      final int ms => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
      _ => null,
    };
    Set<String> strings(Object? list) => {
      for (final s in list is List ? list : const []) ?(s is String ? s : null),
    };
    return Entitlements(
      pro: map['pro'] == true && (until == null || until.isAfter(now)),
      proUntil: until,
      products: strings(map['products']),
      grants: strings(map['grants']),
    );
  }

  static const none = Entitlements();

  final bool pro;

  /// When Pro ends unless it renews (null: no end date known).
  final DateTime? proUntil;

  /// Store products bought (packs, planners, bundles).
  final Set<String> products;

  /// Catalog items given for free (promotions, support).
  final Set<String> grants;

  /// Everything in either. Used to add this device's receipt to what the
  /// account says, since the account updates a few seconds later.
  Entitlements merge(Entitlements other) => Entitlements(
    pro: pro || other.pro,
    proUntil: switch ((proUntil, other.proUntil)) {
      (final a?, final b?) => a.isAfter(b) ? a : b,
      (final a, final b) => a ?? b,
    },
    products: {...products, ...other.products},
    grants: {...grants, ...other.grants},
  );

  /// Whether [product] has been bought.
  bool owns(String product) => products.contains(product);

  /// Any one way of unlocking [item] is enough (docs/skins-plan.md §7).
  /// Items in a collection list the collection's products too (added by
  /// tool/catalog.py), so owning a collection unlocks what's in it.
  /// firebase/storage.rules repeats this rule for downloads.
  bool canUseCatalogItem(CatalogItem item) =>
      item.unlock.free ||
      (item.unlock.pro && pro) ||
      item.unlock.products.any(products.contains) ||
      grants.contains(item.id);

  /// Whether [skin] may be chosen for notebooks.
  bool canUseSkin(SkinManifest skin) => !skin.pro || pro;

  @override
  bool operator ==(Object other) =>
      other is Entitlements &&
      other.pro == pro &&
      other.proUntil == proUntil &&
      setEquals(other.products, products) &&
      setEquals(other.grants, grants);

  @override
  int get hashCode => Object.hash(
    pro,
    proUntil,
    Object.hashAllUnordered(products),
    Object.hashAllUnordered(grants),
  );
}

/// What the account says the user owns (`users/{uid}.entitlements`).
final accountEntitlementsProvider = StreamProvider<Entitlements>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value(Entitlements.none);
  return ref
      .watch(userSettingsRepositoryProvider)
      .watchEntitlements(uid)
      .map((map) => Entitlements.fromMap(map, now: DateTime.now()));
});

/// The store receipt on this device, for the signed-in user.
final deviceEntitlementsProvider = StreamProvider<Entitlements>((ref) async* {
  final uid = ref.watch(authStateProvider).value?.uid;
  final client = ref.watch(purchasesClientProvider);
  if (uid == null || !client.isAvailable) {
    if (client.isAvailable) await client.logOut();
    yield Entitlements.none;
    return;
  }
  yield Entitlements.none;
  try {
    await client.logIn(uid);
  } on PurchasesException catch (e) {
    debugPrint('Store sign-in failed: $e');
    return;
  }
  yield* client.receipts;
});

/// Everything the signed-in user may use.
final entitlementsProvider = Provider<Entitlements>((ref) {
  final bought =
      (ref.watch(accountEntitlementsProvider).value ?? Entitlements.none).merge(
        ref.watch(deviceEntitlementsProvider).value ?? Entitlements.none,
      );
  // Testers get Pro, so they can try everything before it's on sale.
  final tester = ref.watch(isTesterProvider).value ?? false;
  return tester ? bought.merge(const Entitlements(pro: true)) : bought;
});
