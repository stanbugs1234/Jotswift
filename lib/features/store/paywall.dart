import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/entitlements/entitlements.dart';
import '../../core/purchases/purchases_client.dart';
import '../../core/purchases/purchases_providers.dart';
import 'store_actions.dart';

/// Offers Jotswift Pro, yearly first. [reason] says what needed Pro, such as
/// the notebook limit. Returns whether the user has Pro afterwards.
Future<bool> showPaywall(
  BuildContext context,
  WidgetRef ref, {
  String? reason,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useRootNavigator: true,
    builder: (context) => Paywall(reason: reason),
  );
  return ref.read(entitlementsProvider).pro;
}

class Paywall extends ConsumerStatefulWidget {
  const Paywall({this.reason, super.key});

  final String? reason;

  @override
  ConsumerState<Paywall> createState() => _PaywallState();
}

class _PaywallState extends ConsumerState<Paywall> {
  String _plan = ProProducts.yearly;
  bool _busy = false;

  Future<void> _subscribe() async {
    setState(() => _busy = true);
    await buyProduct(context, ref, _plan);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final available = ref.watch(purchasesClientProvider).isAvailable;
    final entitlements = ref.watch(entitlementsProvider);
    // Close once Pro arrives (from this purchase or a restore).
    ref.listen(entitlementsProvider.select((e) => e.pro), (was, pro) {
      if (pro && !(was ?? false) && context.mounted) Navigator.pop(context);
    });
    final yearly = ref.watch(storeOfferProvider(ProProducts.yearly)).value;
    final monthly = ref.watch(storeOfferProvider(ProProducts.monthly)).value;
    final chosen = _plan == ProProducts.yearly ? yearly : monthly;
    final trial = chosen?.trialDays;

    Widget benefit(IconData icon, String text) => ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(text),
    );

    Widget plan(String id, String label, StoreOffer? offer, String per) {
      final selected = _plan == id;
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: ListTile(
          onTap: () => setState(() => _plan = id),
          leading: Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? theme.colorScheme.primary : null,
          ),
          title: Text(label),
          subtitle: switch (offer?.trialDays) {
            final days? => Text('$days days free'),
            null => null,
          },
          trailing: Text(
            offer == null ? '' : '${offer.price}/$per',
            style: theme.textTheme.titleMedium,
          ),
        ),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Jotswift Pro', style: theme.textTheme.headlineSmall),
              if (widget.reason case final reason?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(reason),
                ),
              const SizedBox(height: 12),
              benefit(Icons.all_inclusive, 'Unlimited notebooks'),
              benefit(
                Icons.auto_awesome_outlined,
                'Every cover, paper, planner and sticker pack marked Pro',
              ),
              benefit(
                Icons.calendar_month_outlined,
                'A new collection or planner every month',
              ),
              const SizedBox(height: 12),
              if (entitlements.pro)
                Text(switch (entitlements.proUntil) {
                  final until? =>
                    'You have Jotswift Pro. It renews or ends on '
                        '${MaterialLocalizations.of(context).formatMediumDate(until.toLocal())}.',
                  null => 'You have Jotswift Pro.',
                }, style: theme.textTheme.titleSmall)
              else if (!available)
                const Text(
                  'Jotswift Pro isn\'t on sale yet. Everything is free for '
                  'now.',
                )
              else ...[
                plan(ProProducts.yearly, 'Yearly', yearly, 'year'),
                plan(ProProducts.monthly, 'Monthly', monthly, 'month'),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy || chosen == null ? null : _subscribe,
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(trial != null ? 'Start free trial' : 'Subscribe'),
                ),
                const SizedBox(height: 8),
                Text(
                  [
                    if (trial != null && chosen != null)
                      '$trial days free, then ${chosen.price} '
                          '${_plan == ProProducts.yearly ? 'a year' : 'a month'}.',
                    'Renews automatically until you cancel. Cancel any '
                        'time in your store account settings.',
                  ].join(' '),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (available)
                TextButton(
                  onPressed: () => restorePurchases(context, ref),
                  child: const Text('Restore purchases'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
