import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;

import '../entitlements/entitlements.dart';
import 'purchases_client.dart';

/// RevenueCat's public SDK keys, passed at build time:
/// `--dart-define=REVENUECAT_APPLE_KEY=appl_...` (and `_GOOGLE_`, `_WEB_`).
/// A platform without a key gets [UnavailablePurchases].
PurchasesClient createPurchasesClient() {
  const apple = String.fromEnvironment('REVENUECAT_APPLE_KEY');
  const google = String.fromEnvironment('REVENUECAT_GOOGLE_KEY');
  const web = String.fromEnvironment('REVENUECAT_WEB_KEY');
  final key = kIsWeb
      ? web
      : switch (defaultTargetPlatform) {
          TargetPlatform.iOS || TargetPlatform.macOS => apple,
          TargetPlatform.android => google,
          _ => '',
        };
  return key.isEmpty ? const UnavailablePurchases() : RevenueCatPurchases(key);
}

class RevenueCatPurchases implements PurchasesClient {
  RevenueCatPurchases(this._apiKey);

  /// RevenueCat's entitlement for Notely Pro.
  static const proEntitlement = 'pro';

  final String _apiKey;
  final _receipts = StreamController<Entitlements>.broadcast();
  final _products = <String, rc.StoreProduct>{};
  Entitlements? _last;
  bool _configured = false;

  @override
  bool get isAvailable => true;

  @override
  Future<void> logIn(String uid) => _guard(() async {
    if (!_configured) {
      await rc.Purchases.configure(
        rc.PurchasesConfiguration(_apiKey)..appUserID = uid,
      );
      rc.Purchases.addCustomerInfoUpdateListener(_update);
      _configured = true;
    } else {
      _update((await rc.Purchases.logIn(uid)).customerInfo);
    }
    _update(await rc.Purchases.getCustomerInfo());
  });

  @override
  Future<void> logOut() async {
    if (!_configured) return;
    _last = Entitlements.none;
    _receipts.add(Entitlements.none);
    try {
      await rc.Purchases.logOut();
    } on PlatformException {
      // RevenueCat refuses to log out an anonymous user; nothing to undo.
    }
  }

  void _update(rc.CustomerInfo info) {
    final pro = info.entitlements.active[proEntitlement];
    final next = Entitlements(
      pro: pro != null,
      proUntil: DateTime.tryParse(pro?.expirationDate ?? ''),
      products: {
        for (final t in info.nonSubscriptionTransactions) t.productIdentifier,
      },
    );
    _last = next;
    _receipts.add(next);
  }

  @override
  Stream<Entitlements> get receipts async* {
    if (_last case final last?) yield last;
    yield* _receipts.stream;
  }

  @override
  Future<Map<String, StoreOffer>> offers(List<String> productIds) =>
      _guard(() async {
        final missing = productIds.where((id) => !_products.containsKey(id));
        final subs = [...missing.where(ProProducts.isPro)];
        final others = [...missing.where((id) => !ProProducts.isPro(id))];
        for (final p in [
          if (subs.isNotEmpty) ...await rc.Purchases.getProducts(subs),
          if (others.isNotEmpty)
            ...await rc.Purchases.getProducts(
              others,
              productCategory: rc.ProductCategory.nonSubscription,
            ),
        ]) {
          _products[p.identifier] = p;
        }
        return {
          for (final id in productIds)
            if (_products[id] case final p?) id: _offer(p),
        };
      });

  StoreOffer _offer(rc.StoreProduct p) {
    final intro = p.introductoryPrice;
    final trial = intro != null && intro.price == 0
        ? switch (intro.periodUnit) {
            rc.PeriodUnit.day => intro.periodNumberOfUnits,
            rc.PeriodUnit.week => intro.periodNumberOfUnits * 7,
            rc.PeriodUnit.month => intro.periodNumberOfUnits * 30,
            _ => null,
          }
        : null;
    return StoreOffer(
      productId: p.identifier,
      title: p.title,
      price: p.priceString,
      trialDays: trial,
    );
  }

  @override
  Future<PurchaseOutcome> buy(String productId) => _guard(() async {
    if (!_products.containsKey(productId)) await offers([productId]);
    final product = _products[productId];
    if (product == null) {
      throw PurchasesException('This item isn\'t on sale in your store yet.');
    }
    try {
      final result = await rc.Purchases.purchase(
        rc.PurchaseParams.storeProduct(product),
      );
      _update(result.customerInfo);
      return PurchaseOutcome.purchased;
    } on PlatformException catch (e) {
      if (rc.PurchasesErrorHelper.getErrorCode(e) ==
          rc.PurchasesErrorCode.purchaseCancelledError) {
        return PurchaseOutcome.cancelled;
      }
      rethrow;
    }
  });

  @override
  Future<void> restore() =>
      _guard(() async => _update(await rc.Purchases.restorePurchases()));

  /// Turns the SDK's errors into [PurchasesException]s with its message.
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PlatformException catch (e) {
      throw PurchasesException(e.message ?? 'The store had a problem.');
    }
  }
}
