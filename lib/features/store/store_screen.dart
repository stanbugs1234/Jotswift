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
const _categoryRows = [
  ('spreads', 'Spread planners'),
  ('diaries', 'Diaries'),
  ('journals', 'Journals'),
  ('study', 'Study'),
  ('work', 'Work'),
  ('wellness', 'Wellness'),
  ('lifestyle', 'Lifestyle'),
  ('creative', 'Creative'),
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
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(48),
              child: Text(
                catalog.hasError
                    ? 'Couldn\'t load the templates. Check your connection.'
                    : 'Nothing here yet.',
                textAlign: TextAlign.center,
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
      label: '${item.name}, ${kindLabel(item)}, $badge',
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
                  child: ItemPreview(item: item),
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
