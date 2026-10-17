import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_repository.dart';
import '../entitlements/entitlements.dart';
import '../settings/user_settings_repository.dart';
import 'catalog_item.dart';
import 'catalog_repository.dart';
import 'pack_cache.dart';
import 'pack_disk_memory.dart' show MemoryPackDisk;
import 'planner_series.dart';

/// Overridden in `main()` with Firestore when Firebase is set up.
final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => InMemoryCatalogRepository(),
);

class _NoDownloads implements PackDownloader {
  @override
  Future<Never> download(String path, {required int maxBytes}) =>
      Future.error(PackException(path, 'downloads need Firebase'));
}

/// Overridden in `main()` with Cloud Storage when Firebase is set up.
final packCacheProvider = Provider<PackCache>(
  (ref) => PackCache(_NoDownloads(), MemoryPackDisk()),
);

/// Whether the signed-in account is marked as a tester (set only by the
/// server), so it sees items published for testers.
final isTesterProvider = StreamProvider<bool>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value(false);
  return ref.watch(userSettingsRepositoryProvider).watchTester(uid);
});

/// Every listing this app can read, including hidden and retired ones.
final catalogProvider = StreamProvider<List<CatalogItem>>(
  (ref) => ref
      .watch(catalogRepositoryProvider)
      .watchCatalog()
      .map((items) => items.where((i) => i.isReadable).toList()),
);

/// The items offered to this user that they can use, of [kind].
final offeredCatalogProvider = Provider.family<List<CatalogItem>, CatalogKind>((
  ref,
  kind,
) {
  final tester = ref.watch(isTesterProvider).value ?? false;
  final entitlements = ref.watch(entitlementsProvider);
  return [
    for (final item in ref.watch(catalogProvider).value ?? const [])
      if (item.kind == kind &&
          item.isOffered(isTester: tester) &&
          entitlements.canUseCatalogItem(item))
        item,
  ];
});

/// Every item offered to this user, used or not, for the store.
final storeCatalogProvider = Provider<List<CatalogItem>>((ref) {
  final tester = ref.watch(isTesterProvider).value ?? false;
  return [
    for (final item in ref.watch(catalogProvider).value ?? const [])
      if (item.isOffered(isTester: tester)) item,
  ];
});

/// The listing with [id], or null if it isn't in the catalog.
final catalogItemProvider = Provider.family<CatalogItem?, String>(
  (ref, id) =>
      ref.watch(catalogProvider).value?.where((i) => i.id == id).firstOrNull,
);

/// A catalog cover's image, downloaded on first use. Null while the
/// catalog loads or if [coverId] isn't a catalog cover.
final catalogCoverProvider = FutureProvider.family<ImageProvider?, String>((
  ref,
  coverId,
) async {
  final item = ref.watch(catalogItemProvider(coverId));
  if (item == null || item.kind != CatalogKind.cover) return null;
  final files = await ref.watch(packCacheProvider).files(item);
  final image = files['cover.webp'] ?? files.values.firstOrNull;
  return image == null ? null : MemoryImage(image);
});

/// A picture from the catalog by its storage path (a template's sample
/// page), kept on the device once downloaded.
final catalogImageProvider = FutureProvider.family<ImageProvider, String>(
  (ref, path) async =>
      MemoryImage(await ref.watch(packCacheProvider).image(path)),
);

/// An item's small preview image, for pickers and the store.
final catalogPreviewProvider =
    FutureProvider.family<ImageProvider?, CatalogItem>((ref, item) async {
      final bytes = await ref.watch(packCacheProvider).preview(item);
      return bytes == null ? null : MemoryImage(bytes);
    });

/// Every planner offered, once each, with its editions.
final plannerSeriesProvider = Provider<List<PlannerSeries>>(
  (ref) => plannerSeries(ref.watch(storeCatalogProvider)),
);

/// The editions of [item]'s planner, in date order; [item] alone if it
/// has no others.
final editionsProvider = Provider.family<List<CatalogItem>, CatalogItem>(
  (ref, item) =>
      ref
          .watch(plannerSeriesProvider)
          .where((s) => s.editions.any((e) => e.id == item.id))
          .firstOrNull
          ?.editions ??
      [item],
);
