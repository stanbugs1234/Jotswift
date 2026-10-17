import '../canvas/templates.dart' show templateImageProvider, templatePage;
import '../notebooks/template_filter.dart' show categoryLabel;
import '../notebooks/template_gallery.dart'
    show TemplatePageStrip, showTemplatePages;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/catalog/catalog_item.dart';
import '../../core/catalog/catalog_providers.dart';
import '../../core/catalog/planner_series.dart';
import '../../core/catalog/template_spec.dart';
import '../../core/entitlements/entitlements.dart';
import '../../core/purchases/purchases_providers.dart';
import '../notebooks/domain/notebook_models.dart';
import '../shelf/shelf_actions.dart';
import '../shelf/shelf_view.dart';
import 'paywall.dart';
import 'store_actions.dart';
import '../calendar/templates/calendar_look.dart'
    show calendarTemplateSettingProvider;
import '../calendar/templates/calendar_template.dart';
import 'notebook_picker.dart';
import 'store_item.dart';
import 'store_screen.dart';

/// One item of the store: a large preview, what it is, and how to get or
/// use it. A planner's other editions (its other dates) can be switched to
/// in place.
class StoreItemScreen extends ConsumerStatefulWidget {
  const StoreItemScreen({required this.itemId, this.heroTag, super.key});

  final String itemId;

  /// The tile it was opened from, whose picture grows into this one.
  final Object? heroTag;

  @override
  ConsumerState<StoreItemScreen> createState() => _StoreItemScreenState();
}

class _StoreItemScreenState extends ConsumerState<StoreItemScreen> {
  /// The edition shown.
  late String _itemId = widget.itemId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = ref.watch(catalogItemProvider(_itemId));
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
    final isTemplate = item.kind == CatalogKind.template;
    final entitlements = ref.watch(entitlementsProvider);
    final locked = accessOf(entitlements, item) == ItemAccess.locked;
    final editions = ref.watch(editionsProvider(item));

    final tag = _itemId == widget.itemId ? widget.heroTag : null;
    Widget flies(Widget child) =>
        tag == null ? child : Hero(tag: tag, child: child);
    final preview = AspectRatio(
      aspectRatio: 3 / 4,
      child: flies(
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: switch ((isTemplate, locked, item.samples)) {
            (true, false, _) => _SharpPreview(item: item),
            // Not unlocked yet: its first page, published to look at.
            (true, true, [final first, ...]) => _SharpPreview(
              item: item,
              sample: first,
            ),
            _ => ItemPreview(item: item),
          },
        ),
      ),
    );

    Future<void> lookInside() async {
      final use = useItemAction(context, ref, item);
      final chosen = await showTemplatePages(
        context,
        item,
        locked: locked,
        lockedAction: locked && item.unlock.pro
            ? FilledButton(
                onPressed: () => showPaywall(context, ref),
                child: const Text('Get with Pro'),
              )
            : null,
      );
      if (chosen == true && context.mounted) await use?.run();
    }

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(item.name, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(kindLabel(item), style: theme.textTheme.bodyLarge),
        if (item.linked)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const LinkedPagesBadge(size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Linked pages: tap a date, tab or button to jump to '
                    'that page.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        if (item.tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            // Quiet words for what it's for, not buttons.
            child: Text(
              item.tags.join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (editions.length > 1) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in editions)
                ChoiceChip(
                  avatar: accessOf(entitlements, e) == ItemAccess.locked
                      ? const Icon(Icons.lock_outline, size: 16)
                      : null,
                  label: Text(editionLabel(e) ?? e.name),
                  selected: e.id == item.id,
                  onSelected: (_) => setState(() => _itemId = e.id),
                ),
            ],
          ),
          if (editionDates(item) != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Start it on any month when you make your notebook.',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
        const SizedBox(height: 24),
        _GetOrUse(key: ValueKey(item.id), item: item),
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
      // The name is the page's heading; the bar stays clear.
      appBar: AppBar(),
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
          if (isTemplate && (!locked || item.samples.isNotEmpty)) ...[
            Padding(
              padding: const EdgeInsets.only(top: 32, bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      "What's inside",
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Look inside'),
                    onPressed: lookInside,
                  ),
                ],
              ),
            ),
            TemplatePageStrip(item: item, locked: locked),
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
  const _GetOrUse({required this.item, super.key});

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
                ItemAccess.pro => 'Included in your Jotswift Pro',
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
            label: const Text('Included in Jotswift Pro'),
            onPressed: () => showPaywall(context, ref),
          ),
      ],
    );
  }

  /// How to use an unlocked item.
  List<Widget> _use(BuildContext context, CatalogItem item) {
    final theme = Theme.of(context);
    final use = useItemAction(context, ref, item);
    return [
      if (use != null) FilledButton(onPressed: use.run, child: Text(use.label)),
      if (use?.hint ?? _hint(item) case final hint?)
        Padding(
          padding: EdgeInsets.only(top: use == null ? 0 : 8),
          child: Text(hint, style: theme.textTheme.bodyMedium),
        ),
    ];
  }

  String? _hint(CatalogItem item) => switch (item.kind) {
    CatalogKind.collection =>
      'Everything in this collection is ready in your pickers.',
    _ => null,
  };
}

/// What an unlocked item's main button does.
typedef ItemUse = ({String label, Future<void> Function() run, String? hint});

/// The main way to use [item] once it's unlocked, or null if there's
/// nothing to start (a collection).
ItemUse? useItemAction(BuildContext context, WidgetRef ref, CatalogItem item) {
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

  /// Asks which notebook, then opens it ready to add [item]'s pages.
  Future<void> addPages() async {
    final notebook = await pickNotebook(
      context,
      title: 'Add ${item.name} pages to…',
    );
    if (notebook == null || !context.mounted) return;
    context.go(
      Uri(
        path: '/notebooks/${notebook.id}',
        queryParameters: {'newPage': item.name},
      ).toString(),
    );
  }

  /// Asks which notebook, then opens it where it was left.
  Future<void> openNotebookToUse() async {
    final notebook = await pickNotebook(context, title: 'Use in…');
    if (notebook == null || !context.mounted) return;
    context.go(switch (notebook.lastPageId) {
      final page? => '/notebooks/${notebook.id}/pages/$page',
      null => '/notebooks/${notebook.id}',
    });
  }

  return switch (item.kind) {
    CatalogKind.template when item.templateMode == TemplateMode.notebook => (
      label: 'New notebook from this planner',
      run: () => startNotebook(template: item),
      hint: null,
    ),
    CatalogKind.template => (
      label: 'Add pages to a notebook…',
      run: addPages,
      hint:
          'They\'re also in New page in any notebook, under '
          '${categoryLabel(item.category ?? 'pages')}.',
    ),
    CatalogKind.cover => (
      label: 'New notebook with this cover',
      run: () => startNotebook(
        cover: NotebookCover.art(item.id, color: item.color ?? 0xFF455A64),
      ),
      hint: null,
    ),
    CatalogKind.paper => (
      label: 'New notebook with this paper',
      run: () => startNotebook(paper: true),
      hint: null,
    ),
    CatalogKind.stickers => (
      label: 'Use in a notebook…',
      run: openNotebookToUse,
      hint: 'Tap Stickers in the page toolbar to place them.',
    ),
    CatalogKind.calendar => (
      label: 'Use this calendar template',
      run: () async {
        await ref
            .read(calendarTemplateSettingProvider.notifier)
            .select(calendarTemplateById(item.templateId ?? ''));
        if (context.mounted) context.go('/calendar');
      },
      hint: null,
    ),
    CatalogKind.collection || CatalogKind.unknown => null,
  };
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

/// A template's first page drawn at full size, instead of the small store
/// picture; the picture until it's ready (or if it can't be).
class _SharpPreview extends ConsumerWidget {
  const _SharpPreview({required this.item, this.sample});

  final CatalogItem item;

  /// A published page to show instead, for an item that isn't unlocked.
  final CatalogSample? sample;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Widget? picture = switch (sample) {
      final s? => switch (ref.watch(catalogImageProvider(s.path)).value) {
        final image? => Image(image: image, fit: BoxFit.contain),
        null => null,
      },
      null => switch (ref
          .watch(
            templateImageProvider((
              template: templatePage(item, 1),
              width: 900,
            )),
          )
          .value) {
        final image? => RawImage(image: image, fit: BoxFit.contain),
        null => null,
      },
    };
    if (picture == null) return ItemPreview(item: item);
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: picture,
          ),
        ),
      ),
    );
  }
}
