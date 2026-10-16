import '../notebooks/template_filter.dart';
import '../../shared/ui/empty_state.dart';
import '../../shared/ui/skeleton.dart';
import '../../shared/ui/tokens.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/catalog/catalog_item.dart';
import '../../core/catalog/catalog_providers.dart';
import '../../core/catalog/template_spec.dart';
import '../../core/entitlements/entitlements.dart';
import '../../core/motion/rise_in.dart';
import '../../core/purchases/purchases_providers.dart';
import 'paywall.dart';
import 'store_actions.dart';
import 'store_item.dart';

const storePath = '/templates';

enum _Filter { all, free, pro, owned }

/// A row of the Templates screen: its title and which items it shows.
typedef _Section = (String, bool Function(CatalogItem));

bool _isTemplate(CatalogItem i, TemplateMode mode, Set<String> categories) =>
    i.kind == CatalogKind.template &&
    i.templateMode == mode &&
    !categories.contains(i.category);

/// Template categories with their own row, in the order shown.
/// Categories with rows of their own, named and ordered as in the
/// pickers. Planners and basic pages have the rows below.
final _categoryRows = [
  for (final MapEntry(:key, :value) in templateCategories.entries)
    if (key != 'planners' && key != 'pages') (key, value),
];

final _ownRows = {for (final (category, _) in _categoryRows) category};

final List<_Section> _sections = [
  ('Planners', (i) => _isTemplate(i, TemplateMode.notebook, _ownRows)),
  for (final (category, title) in _categoryRows)
    (title, (CatalogItem i) => i.category == category),
  ('Calendars', (i) => i.kind == CatalogKind.calendar),
  ('Collections', (i) => i.kind == CatalogKind.collection),
  ('Page templates', (i) => _isTemplate(i, TemplateMode.pages, _ownRows)),
  ('Covers', (i) => i.kind == CatalogKind.cover),
  ('Papers', (i) => i.kind == CatalogKind.paper),
  ('Stickers', (i) => i.kind == CatalogKind.stickers),
];

/// The store: planners, covers, papers, stickers and collections to get.
class StoreScreen extends ConsumerStatefulWidget {
  const StoreScreen({super.key});

  @override
  ConsumerState<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends ConsumerState<StoreScreen> {
  _Filter _filter = _Filter.all;

  bool _matches(Entitlements entitlements, CatalogItem item) =>
      switch (_filter) {
        _Filter.all => true,
        _Filter.free => item.unlock.free,
        _Filter.pro => item.unlock.pro,
        _Filter.owned => switch (accessOf(entitlements, item)) {
          ItemAccess.owned || ItemAccess.pro => true,
          _ => false,
        },
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entitlements = ref.watch(entitlementsProvider);
    final catalog = ref.watch(catalogProvider);
    final items = [
      for (final i in ref.watch(storeCatalogProvider))
        if (_matches(entitlements, i)) i,
    ];
    final available = ref.watch(purchasesClientProvider).isAvailable;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Templates'),
        actions: [
          if (available)
            TextButton(
              onPressed: () => restorePurchases(context, ref),
              child: const Text('Restore purchases'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 8,
              children: [
                for (final f in _Filter.values)
                  ChoiceChip(
                    label: Text(switch (f) {
                      _Filter.all => 'All',
                      _Filter.free => 'Free',
                      _Filter.pro => 'Pro',
                      _Filter.owned => 'Yours',
                    }),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
              ],
            ),
          ),
          if (!entitlements.pro) const _ProBanner(),
          if (catalog.isLoading)
            // Rows of cards stand in until the catalog arrives.
            for (var row = 0; row < 2; row++)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Skeleton(width: 140, height: 18),
                    const SizedBox(height: Insets.md),
                    Row(
                      children: [
                        for (var i = 0; i < 4; i++) ...[
                          if (i > 0) const SizedBox(width: Insets.lg),
                          const Expanded(child: Skeleton(height: 200)),
                        ],
                      ],
                    ),
                  ],
                ),
              )
          else if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Insets.xxxl),
              child: catalog.hasError
                  ? const EmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: 'Couldn\'t load the templates',
                      message: 'Check your connection and try again.',
                    )
                  : const EmptyState(
                      icon: Icons.storefront_outlined,
                      title: 'Nothing here yet.',
                    ),
            ),
          for (final (title, belongs) in _sections)
            if (items.where(belongs).toList() case final row
                when row.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Text(title, style: theme.textTheme.titleMedium),
              ),
              SizedBox(
                height: 236,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: row.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 16),
                  // Cards arrive one after another.
                  itemBuilder: (context, i) => RiseIn(
                    index: i,
                    child: StoreTile(item: row[i]),
                  ),
                ),
              ),
            ],
        ],
      ),
    );
  }
}

class _ProBanner extends ConsumerWidget {
  const _ProBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      color: theme.colorScheme.primaryContainer,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(
          Icons.auto_awesome,
          color: theme.colorScheme.onPrimaryContainer,
        ),
        title: const Text('Jotswift Pro'),
        subtitle: const Text(
          'Everything marked Pro, unlimited notebooks, and something new '
          'every month.',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showPaywall(context, ref),
      ),
    );
  }
}

/// One item in a row: its preview, name and price or status.
class StoreTile extends ConsumerWidget {
  const StoreTile({required this.item, super.key});

  final CatalogItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final badge = ref.watch(itemBadgeProvider(item));
    return Semantics(
      button: true,
      label: [
        item.name,
        kindLabel(item),
        if (item.linked) 'linked pages',
        badge,
      ].join(', '),
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('$storePath/${item.id}'),
        child: SizedBox(
          width: 140,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 180,
                  width: 140,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ItemPreview(item: item),
                      if (item.linked)
                        const Positioned(
                          top: 6,
                          right: 6,
                          child: LinkedPagesBadge(),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              Text(
                badge,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
