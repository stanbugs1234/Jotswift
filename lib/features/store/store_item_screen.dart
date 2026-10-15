import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/catalog/catalog_item.dart';
import '../../core/catalog/catalog_providers.dart';
import '../../core/catalog/template_spec.dart';
import '../../core/entitlements/entitlements.dart';
import '../../core/purchases/purchases_providers.dart';
import '../notebooks/domain/notebook_models.dart';
import '../shelf/shelf_actions.dart';
import '../shelf/shelf_view.dart';
import 'paywall.dart';
import 'store_actions.dart';
import 'store_item.dart';
import 'store_screen.dart';

/// One item of the store: a large preview, what it is, and how to get or
/// use it.
class StoreItemScreen extends ConsumerWidget {
  const StoreItemScreen({required this.itemId, super.key});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final item = ref.watch(catalogItemProvider(itemId));
    if (item == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: ref.watch(catalogProvider).isLoading
              ? const CircularProgressIndicator()
              : const Text('This item isn\'t available any more.'),
        ),
      );
    }
    final collection = switch (item.collectionId) {
      final id? => ref.watch(catalogItemProvider(id)),
      null => null,
    };
    final contents = item.kind == CatalogKind.collection
        ? [
            for (final i in ref.watch(storeCatalogProvider))
              if (i.collectionId == item.id) i,
          ]
        : const <CatalogItem>[];
    final wide = MediaQuery.sizeOf(context).width >= 700;

    final preview = AspectRatio(
      aspectRatio: 3 / 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ItemPreview(item: item),
      ),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(item.name, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(kindLabel(item), style: theme.textTheme.bodyLarge),
        if (item.tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in item.tags)
                  Chip(label: Text(t), visualDensity: VisualDensity.compact),
              ],
            ),
          ),
        const SizedBox(height: 24),
        _GetOrUse(item: item),
        if (collection != null &&
            collection.visibility != CatalogVisibility.retired)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.collections_bookmark_outlined),
              title: Text('Part of ${collection.name}'),
              subtitle: const Text('Get the whole collection'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('$storePath/${collection.id}'),
            ),
          ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: Text(item.name)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 320, child: preview),
                const SizedBox(width: 32),
                Expanded(child: details),
              ],
            )
          else ...[
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: preview,
              ),
            ),
            const SizedBox(height: 24),
            details,
          ],
          if (contents.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 32, bottom: 12),
              child: Text(
                'In this collection',
                style: theme.textTheme.titleMedium,
              ),
            ),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [for (final i in contents) StoreTile(item: i)],
            ),
          ],
        ],
      ),
    );
  }
}

/// Buy buttons for a locked item; what to do with it otherwise.
class _GetOrUse extends ConsumerStatefulWidget {
  const _GetOrUse({required this.item});

  final CatalogItem item;

  @override
  ConsumerState<_GetOrUse> createState() => _GetOrUseState();
}

class _GetOrUseState extends ConsumerState<_GetOrUse> {
  bool _busy = false;

  Future<void> _buy(String product) async {
    setState(() => _busy = true);
    await buyProduct(context, ref, product);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final access = accessOf(ref.watch(entitlementsProvider), item);
    final available = ref.watch(purchasesClientProvider).isAvailable;

    if (access != ItemAccess.locked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(switch (access) {
                ItemAccess.free => 'Free',
                ItemAccess.pro => 'Included in your Notely Pro',
                _ => 'You own this',
              }, style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 16),
          ..._use(context, item),
        ],
      );
    }

    final products = item.unlock.products;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!available)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Purchases open soon.'),
          ),
        for (final product in products) ...[
          _BuyButton(
            product: product,
            item: item,
            primary: product == products.first,
            onBuy: _busy || !available ? null : () => _buy(product),
          ),
          const SizedBox(height: 8),
        ],
        if (item.unlock.pro)
          OutlinedButton.icon(
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Included in Notely Pro'),
            onPressed: () => showPaywall(context, ref),
          ),
      ],
    );
  }

  /// How to use an unlocked item.
  List<Widget> _use(BuildContext context, CatalogItem item) {
    Future<void> startNotebook({
      NotebookCover? cover,
      CatalogItem? template,
      bool paper = false,
    }) => createNotebookAt(
      context,
      ref,
      const AllNotebooks(),
      cover: cover,
      paper: paper ? item.paper : null,
      template: template,
    );

    Widget hint(String text) =>
        Text(text, style: Theme.of(context).textTheme.bodyMedium);

    return switch (item.kind) {
      CatalogKind.template when item.templateMode == TemplateMode.notebook => [
        FilledButton(
          onPressed: () => startNotebook(template: item),
          child: const Text('New notebook from this planner'),
        ),
      ],
      CatalogKind.cover => [
        FilledButton(
          onPressed: () => startNotebook(
            cover: NotebookCover.art(item.id, color: item.color ?? 0xFF455A64),
          ),
          child: const Text('New notebook with this cover'),
        ),
      ],
      CatalogKind.paper => [
        FilledButton(
          onPressed: () => startNotebook(paper: true),
          child: const Text('New notebook with this paper'),
        ),
      ],
      CatalogKind.template => [
        hint(
          'In a notebook, choose New page from template in the ••• menu '
          'to add these pages.',
        ),
      ],
      CatalogKind.stickers => [
        hint('Open a page and tap Stickers in the toolbar.'),
      ],
      CatalogKind.collection => [
        hint('Everything in this collection is ready in your pickers.'),
      ],
      CatalogKind.unknown => const [],
    };
  }
}

class _BuyButton extends ConsumerWidget {
  const _BuyButton({
    required this.product,
    required this.item,
    required this.primary,
    required this.onBuy,
  });

  final String product;
  final CatalogItem item;
  final bool primary;
  final VoidCallback? onBuy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offer = ref.watch(storeOfferProvider(product)).value;
    // A product named after another item (a collection or bundle) says so.
    final isOwn = item.unlock.products.length == 1;
    final label = switch ((offer, isOwn)) {
      (final o?, true) => 'Buy · ${o.price}',
      (final o?, false) => '${o.title} · ${o.price}',
      (null, _) => 'Buy',
    };
    final child = Text(label);
    return primary
        ? FilledButton(onPressed: offer == null ? null : onBuy, child: child)
        : OutlinedButton(onPressed: offer == null ? null : onBuy, child: child);
  }
}
