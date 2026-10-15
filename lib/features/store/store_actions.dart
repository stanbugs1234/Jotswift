import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/purchases/purchases_client.dart';
import '../../core/purchases/purchases_providers.dart';

void _say(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Buys [productId] through the store. Returns whether it was bought.
Future<bool> buyProduct(
  BuildContext context,
  WidgetRef ref,
  String productId,
) async {
  try {
    final outcome = await ref.read(purchasesClientProvider).buy(productId);
    if (outcome == PurchaseOutcome.purchased && context.mounted) {
      _say(context, 'Thank you! It\'s ready to use.');
    }
    return outcome == PurchaseOutcome.purchased;
  } on PurchasesException catch (e) {
    if (context.mounted) _say(context, 'Couldn\'t buy it: $e');
    return false;
  }
}

/// Asks the store for everything this store account bought before.
Future<void> restorePurchases(BuildContext context, WidgetRef ref) async {
  try {
    await ref.read(purchasesClientProvider).restore();
    if (context.mounted) _say(context, 'Your purchases are restored.');
  } on PurchasesException catch (e) {
    if (context.mounted) _say(context, 'Couldn\'t restore purchases: $e');
  }
}
