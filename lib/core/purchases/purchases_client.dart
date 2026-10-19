import 'dart:async';

import 'package:flutter/foundation.dart';

import '../entitlements/entitlements.dart';

/// Jotswift Pro's plans, yearly first (the one the paywall suggests). Each
/// is also its App Store product id; with RevenueCat the plans come from the
/// current offering's annual, monthly and lifetime packages instead, so the
/// products behind them can change (RevenueCat's Test Store calls them
/// "yearly", "monthly" and "lifetime").
abstract final class ProProducts {
  static const yearly = 'pro_yearly';
  static const monthly = 'pro_monthly';

  /// Bought once, never renews. Offered only once the stores sell it.
  static const lifetime = 'pro_lifetime';
  static const all = [yearly, monthly, lifetime];

  static bool isPro(String productId) => productId.startsWith('pro_');
}

/// A product as the store sells it, with the price in the buyer's currency.
@immutable
class StoreOffer {
  const StoreOffer({
    required this.productId,
    required this.title,
    required this.price,
    this.trialDays,
  });

  final String productId;
  final String title;

  /// Formatted for display, such as "$2.99".
  final String price;

  /// Days free before the first payment, if the buyer may have a trial.
  final int? trialDays;
}

class PurchasesException implements Exception {
  PurchasesException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum PurchaseOutcome { purchased, cancelled }

/// The app store (Apple, Google, or Stripe on the web) through RevenueCat.
/// The RevenueCat user is the Firebase uid.
abstract interface class PurchasesClient {
  /// False until the store is set up for this platform (no API key yet).
  bool get isAvailable;

  /// Connects purchases to [uid]. Purchases made before signing in move
  /// to the account.
  Future<void> logIn(String uid);
  Future<void> logOut();

  /// What this device's store receipt unlocks, now and after each change.
  Stream<Entitlements> get receipts;

  /// Prices for [productIds]. Products the store doesn't know are left out.
  Future<Map<String, StoreOffer>> offers(List<String> productIds);

  /// Jotswift Pro's plans for sale, keyed by [ProProducts] id.
  Future<Map<String, StoreOffer>> proOffers();

  /// Buys [productId], or a [ProProducts] plan, with the store's own
  /// payment sheet. Throws [PurchasesException] if the store refuses.
  Future<PurchaseOutcome> buy(String productId);

  /// Asks the store again for everything this Apple/Google account bought.
  Future<void> restore();

  /// Whether [presentPaywall] and [presentCustomerCenter] work here
  /// (RevenueCat's own screens, on iOS and Android).
  bool get hasStoreScreens;

  /// Shows the paywall designed in RevenueCat. Returns whether something
  /// was bought or restored.
  Future<bool> presentPaywall();

  /// Shows RevenueCat's Customer Center: manage or cancel the
  /// subscription, ask for a refund, restore.
  Future<void> presentCustomerCenter();
}

/// Used until the store is set up: nothing can be bought.
class UnavailablePurchases implements PurchasesClient {
  const UnavailablePurchases();

  @override
  bool get isAvailable => false;

  @override
  Future<void> logIn(String uid) async {}

  @override
  Future<void> logOut() async {}

  @override
  Stream<Entitlements> get receipts => Stream.value(Entitlements.none);

  @override
  Future<Map<String, StoreOffer>> offers(List<String> productIds) async =>
      const {};

  @override
  Future<Map<String, StoreOffer>> proOffers() async => const {};

  @override
  Future<PurchaseOutcome> buy(String productId) =>
      Future.error(PurchasesException('The store isn\'t open yet.'));

  @override
  Future<void> restore() =>
      Future.error(PurchasesException('The store isn\'t open yet.'));

  @override
  bool get hasStoreScreens => false;

  @override
  Future<bool> presentPaywall() =>
      Future.error(PurchasesException('The store isn\'t open yet.'));

  @override
  Future<void> presentCustomerCenter() =>
      Future.error(PurchasesException('The store isn\'t open yet.'));
}
