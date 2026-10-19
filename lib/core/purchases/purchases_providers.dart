import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'purchases_client.dart';

/// Overridden in `main()` with RevenueCat once the store is set up.
final purchasesClientProvider = Provider<PurchasesClient>(
  (ref) => const UnavailablePurchases(),
);

/// The price of [productId] in this user's store, or null if it isn't on
/// sale (or the store isn't set up).
final storeOfferProvider = FutureProvider.family<StoreOffer?, String>((
  ref,
  productId,
) async {
  final client = ref.watch(purchasesClientProvider);
  if (!client.isAvailable) return null;
  return (await client.offers([productId]))[productId];
});

/// Jotswift Pro's plans for sale, keyed by [ProProducts] id; empty until
/// the store is set up.
final proOffersProvider = FutureProvider<Map<String, StoreOffer>>((ref) {
  final client = ref.watch(purchasesClientProvider);
  return client.isAvailable ? client.proOffers() : Future.value(const {});
});
