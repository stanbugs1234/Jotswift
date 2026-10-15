import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/catalog_item.dart';
import '../../core/catalog/catalog_providers.dart';
import '../../core/catalog/template_spec.dart';
import '../../core/entitlements/entitlements.dart';
import '../../core/purchases/purchases_providers.dart';
import '../../core/skins/widgets/paper.dart';

/// How the user may use an item.
enum ItemAccess {
  free,

  /// Bought, on its own or in a collection or bundle, or given.
  owned,

  /// Included in the user's Pro.
  pro,
  locked,
}

ItemAccess accessOf(Entitlements entitlements, CatalogItem item) {
  if (item.unlock.free) return ItemAccess.free;
  if (item.unlock.products.any(entitlements.owns) ||
      entitlements.grants.contains(item.id)) {
    return ItemAccess.owned;
  }
  if (item.unlock.pro && entitlements.pro) return ItemAccess.pro;
  return ItemAccess.locked;
}

/// What kind of thing an item is, for people.
String kindLabel(CatalogItem item) => switch (item.kind) {
  CatalogKind.cover => 'Cover',
  CatalogKind.paper => 'Paper',
  CatalogKind.template => switch (item.templateMode) {
    TemplateMode.notebook =>
      item.pageCount == null ? 'Planner' : 'Planner · ${item.pageCount} pages',
    _ => 'Page templates',
  },
  CatalogKind.stickers => 'Sticker pack',
  CatalogKind.collection => 'Collection',
  CatalogKind.unknown => '',
};

/// A short price or status for a tile: "Free", "Owned", "Pro", "$2.99".
final itemBadgeProvider = Provider.family<String, CatalogItem>((ref, item) {
  final access = accessOf(ref.watch(entitlementsProvider), item);
  switch (access) {
    case ItemAccess.free:
      return 'Free';
    case ItemAccess.owned:
      return 'Owned';
    case ItemAccess.pro:
      return 'In your Pro';
    case ItemAccess.locked:
      final product = item.unlock.products.firstOrNull;
      final price = product == null
          ? null
          : ref.watch(storeOfferProvider(product)).value?.price;
      return price ?? (item.unlock.pro ? 'Pro' : 'Coming soon');
  }
});

/// An item's preview: the paper itself, or its preview image.
class ItemPreview extends ConsumerWidget {
  const ItemPreview({required this.item, super.key});

  final CatalogItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (item.paper case final paper?) {
      return ColoredBox(
        color: paper.color,
        child: CustomPaint(
          painter: PaperPainter(paper, scale: 0.5),
          child: const SizedBox.expand(),
        ),
      );
    }
    final image = ref.watch(catalogPreviewProvider(item)).value;
    return ColoredBox(
      color: item.color == null
          ? theme.colorScheme.surfaceContainerHighest
          : Color(item.color!),
      child: image == null
          ? const SizedBox.expand()
          : Image(
              image: image,
              fit: item.kind == CatalogKind.cover
                  ? BoxFit.cover
                  : BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
            ),
    );
  }
}
