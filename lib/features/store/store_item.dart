import '../../shared/ui/skeleton.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/catalog_item.dart';
import '../../core/catalog/catalog_providers.dart';
import '../../core/catalog/template_spec.dart';
import '../../core/entitlements/entitlements.dart';
import '../../core/purchases/purchases_providers.dart';
import '../../core/skins/widgets/paper.dart';
import '../calendar/domain/event.dart' show Day;
import '../calendar/templates/calendar_template.dart';
import '../calendar/templates/calendar_templates_screen.dart';

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
  CatalogKind.calendar => 'Calendar template',
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

/// Marks a template whose pages link to each other.
class LinkedPagesBadge extends StatelessWidget {
  const LinkedPagesBadge({this.size = 16, super.key});

  final double size;

  static const tooltip = 'Linked pages: tap dates and tabs to jump around';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: EdgeInsets.all(size * 0.25),
        decoration: BoxDecoration(
          color: scheme.primary,
          shape: BoxShape.circle,
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
        ),
        child: Icon(Icons.link, size: size, color: scheme.onPrimary),
      ),
    );
  }
}

/// An item's preview: the paper itself, or its preview image.
class ItemPreview extends ConsumerWidget {
  const ItemPreview({required this.item, super.key});

  final CatalogItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (item.kind == CatalogKind.calendar) {
      // Drawn live by the app; there's no image to download.
      return TemplatePreview(
        template: calendarTemplateById(item.templateId ?? ''),
        month: Day.of(DateTime.now()).firstOfMonth,
      );
    }
    if (item.paper case final paper?) {
      return ColoredBox(
        color: paper.color,
        child: CustomPaint(
          painter: PaperPainter(paper, scale: 0.5),
          child: const SizedBox.expand(),
        ),
      );
    }
    final preview = ref.watch(catalogPreviewProvider(item));
    final image = preview.value;
    if (item.kind == CatalogKind.cover) {
      return ColoredBox(
        color: item.color == null
            ? theme.colorScheme.surfaceContainerHighest
            : Color(item.color!),
        child: image == null
            ? const SizedBox.expand()
            : Image(
                image: image,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
      );
    }
    // Pages sit on a soft surface with a shadow, like paper on a desk, so a
    // landscape planner in a portrait card looks placed, not letterboxed.
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: image == null
          // Pulses while loading; a preview that failed stays plain.
          ? (preview.isLoading ? const Skeleton(radius: 0) : null)
          : Padding(
              padding: const EdgeInsets.all(8),
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  // Loose constraints: the image keeps its shape, and the
                  // shadow hugs it.
                  child: Image(image: image, fit: BoxFit.contain),
                ),
              ),
            ),
    );
  }
}
