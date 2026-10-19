import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

import '../entitlements/entitlements.dart';
import 'purchases_client.dart';

/// RevenueCat's public SDK keys, passed at build time:
/// `--dart-define=REVENUECAT_APPLE_KEY=appl_...` (and `_GOOGLE_`, `_WEB_`).
/// A platform without a key gets [UnavailablePurchases].
///
/// A Test Store key (`test_...`) sells RevenueCat's test products with no
/// real payments, for trying the store in debug builds. A release build
/// ignores it, since RevenueCat refuses to run one with it.
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
  if (key.isEmpty || (kReleaseMode && key.startsWith('test_'))) {
    return const UnavailablePurchases();
  }
  return RevenueCatPurchases(key);
}

class RevenueCatPurchases implements PurchasesClient {
  RevenueCatPurchases(this._apiKey);

  /// RevenueCat's entitlement for Jotswift Pro.
  static const proEntitlement = 'jotswift_pro';

  final String _apiKey;
  final _receipts = StreamController<Entitlements>.broadcast();
  final _products = <String, rc.StoreProduct>{};

  /// The current offering's package for each [ProProducts] plan.
  final _plans = <String, rc.Package>{};
  Entitlements? _last;
  bool _configured = false;

  @override
  bool get isAvailable => true;

  @override
  bool get hasStoreScreens =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  @override
  Future<void> logIn(String uid) => _guard(() async {
    if (!_configured) {
      await rc.Purchases.setLogLevel(
        kDebugMode ? rc.LogLevel.debug : rc.LogLevel.warn,
      );
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

  @override
  Future<Map<String, StoreOffer>> proOffers() => _guard(() async {
    final offering = (await rc.Purchases.getOfferings()).current;
    _plans
      ..clear()
      ..addAll({
        ProProducts.yearly: ?offering?.annual,
        ProProducts.monthly: ?offering?.monthly,
        ProProducts.lifetime: ?offering?.lifetime,
      });
    // Without an offering in RevenueCat, the App Store's own products.
    if (_plans.isEmpty) return offers(ProProducts.all);
    return {
      for (final MapEntry(:key, :value) in _plans.entries)
        key: _offer(value.storeProduct),
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
    final rc.PurchaseParams params;
    if (_plans[productId] case final package?) {
      params = rc.PurchaseParams.package(package);
    } else {
      if (!_products.containsKey(productId)) await offers([productId]);
      final product = _products[productId];
      if (product == null) {
        throw PurchasesException('This item isn\'t on sale in your store yet.');
      }
      params = rc.PurchaseParams.storeProduct(product);
    }
    try {
      _update((await rc.Purchases.purchase(params)).customerInfo);
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

  @override
  Future<bool> presentPaywall() => _guard(() async {
    final result = await RevenueCatUI.presentPaywall(displayCloseButton: true);
    _update(await rc.Purchases.getCustomerInfo());
    return switch (result) {
      PaywallResult.purchased || PaywallResult.restored => true,
      _ => false,
    };
  });

  @override
  Future<void> presentCustomerCenter() => _guard(() async {
    await RevenueCatUI.presentCustomerCenter();
    _update(await rc.Purchases.getCustomerInfo());
  });

  /// Turns the SDK's errors into [PurchasesException]s someone can act on.
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PlatformException catch (e) {
      throw PurchasesException(purchasesErrorMessage(e));
    }
  }
}

/// What to tell the buyer about a store error.
@visibleForTesting
String purchasesErrorMessage(PlatformException e) =>
    switch (rc.PurchasesErrorHelper.getErrorCode(e)) {
      rc.PurchasesErrorCode.networkError => 'No internet connection.',
      rc.PurchasesErrorCode.purchaseNotAllowedError =>
        'Purchases aren\'t allowed on this device. Check Screen Time '
            'restrictions.',
      rc.PurchasesErrorCode.paymentPendingError =>
        'Your purchase is waiting for approval. It unlocks as soon as it '
            'goes through.',
      rc.PurchasesErrorCode.productNotAvailableForPurchaseError =>
        'This item isn\'t on sale in your store yet.',
      rc.PurchasesErrorCode.productAlreadyPurchasedError ||
      rc.PurchasesErrorCode.receiptAlreadyInUseError ||
      rc.PurchasesErrorCode.receiptInUseByOtherSubscriberError =>
        'This was already bought with this Apple ID, perhaps on another '
            'Jotswift account. Try Restore purchases.',
      rc.PurchasesErrorCode.operationAlreadyInProgressError =>
        'A purchase is already in progress.',
      _ => e.message ?? 'The store had a problem. Please try again.',
    };
