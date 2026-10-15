import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/catalog_item.dart';
import '../../core/catalog/catalog_providers.dart';
import 'ink_tools.dart';

/// One sticker in a pack.
typedef Sticker = ({String file, String name, Uint8List bytes});

/// A downloaded sticker pack: its `stickers.json` list with the images.
class StickerPack {
  StickerPack(this.item, this.stickers);

  /// Reads a pack's files. Entries whose image is missing are skipped.
  factory StickerPack.fromFiles(
    CatalogItem item,
    Map<String, Uint8List> files,
  ) {
    final list = files['stickers.json'];
    final entries = list == null
        ? const []
        : (jsonDecode(utf8.decode(list)) as Map)['stickers'] as List? ??
              const [];
    return StickerPack(item, [
      for (final e in entries.whereType<Map>())
        if (e['file'] case final String file when files[file] != null)
          (file: file, name: e['name'] as String? ?? '', bytes: files[file]!),
    ]);
  }

  final CatalogItem item;
  final List<Sticker> stickers;
}

/// A sticker pack's stickers, downloaded on first use.
final stickerPackProvider = FutureProvider.family<StickerPack, CatalogItem>(
  (ref, item) async => StickerPack.fromFiles(
    item,
    await ref.watch(packCacheProvider).files(item),
  ),
);

/// The image of one placed sticker. Null while the catalog loads or if the
/// pack is gone. Retired packs keep working for stickers already placed.
final stickerImageProvider =
    FutureProvider.family<ImageProvider?, ({String itemId, String file})>((
      ref,
      key,
    ) async {
      final item = ref.watch(catalogItemProvider(key.itemId));
      if (item == null) return null;
      final files = await ref.watch(packCacheProvider).files(item);
      final bytes = files[key.file];
      return bytes == null ? null : MemoryImage(bytes);
    });

/// A sticker the user picked, waiting for the canvas to place it.
typedef StickerRequest = ({String itemId, String file, double aspect});

/// The sticker waiting to be placed on a page (set by the sticker tray,
/// taken by the page's canvas, which knows what part of the page is in
/// view).
class StickerRequestController extends Notifier<StickerRequest?> {
  StickerRequestController(this.pageId);

  final String pageId;

  @override
  StickerRequest? build() => null;

  void request(StickerRequest sticker) => state = sticker;

  /// Takes the waiting sticker, if any.
  StickerRequest? take() {
    final sticker = state;
    state = null;
    return sticker;
  }
}

final stickerRequestProvider = NotifierProvider.autoDispose
    .family<StickerRequestController, StickerRequest?, String>(
      StickerRequestController.new,
    );

/// The sticker tray: every sticker pack the user can use. Picking a sticker
/// places it on [pageId] and switches to the select tool.
Future<void> showStickerTray(BuildContext context, String pageId) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _StickerTray(pageId: pageId),
    );

class _StickerTray extends ConsumerWidget {
  const _StickerTray({required this.pageId});

  final String pageId;

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    CatalogItem pack,
    Sticker sticker,
  ) async {
    final codec = await ui.instantiateImageCodec(sticker.bytes);
    final image = (await codec.getNextFrame()).image;
    final aspect = image.width / image.height;
    image.dispose();
    ref.read(stickerRequestProvider(pageId).notifier).request((
      itemId: pack.id,
      file: sticker.file,
      aspect: aspect,
    ));
    ref.read(inkToolProvider.notifier).selectTool(InkToolKind.select);
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packs = ref.watch(offeredCatalogProvider(CatalogKind.stickers));
    final theme = Theme.of(context);

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: packs.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No sticker packs yet. Check your connection; free '
                    'packs appear here.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Text('Stickers', style: theme.textTheme.titleLarge),
                  for (final item in packs) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 8),
                      child: Text(item.name, style: theme.textTheme.titleSmall),
                    ),
                    switch (ref.watch(stickerPackProvider(item))) {
                      AsyncData(value: final pack) => Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in pack.stickers)
                            Semantics(
                              button: true,
                              label: '${s.name} sticker',
                              excludeSemantics: true,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => _pick(context, ref, item, s),
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Image.memory(
                                    s.bytes,
                                    width: 64,
                                    height: 64,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      AsyncError() => const Text(
                        'Could not download this pack. Check your connection.',
                      ),
                      _ => const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    },
                  ],
                ],
              ),
      ),
    );
  }
}
