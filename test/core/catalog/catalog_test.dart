import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/catalog/catalog_item.dart';
import 'package:notely/core/catalog/pack_cache.dart';
import 'package:notely/core/catalog/pack_disk_memory.dart';
import 'package:notely/core/entitlements/entitlements.dart';
import 'package:notely/core/paper/paper_style.dart';

/// A zip with [files], as tool/catalog.py makes them.
Uint8List zip(Map<String, List<int>> files) {
  final archive = Archive();
  for (final MapEntry(key: name, value: bytes) in files.entries) {
    archive.addFile(ArchiveFile.bytes(name, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Map<String, dynamic> listing({
  String kind = 'cover',
  int version = 1,
  String visibility = 'public',
  Map<String, Object?> unlock = const {'free': true},
  int format = 1,
  Uint8List? pack,
}) => {
  'kind': kind,
  'name': 'Night Sky',
  'version': version,
  'visibility': visibility,
  'unlock': unlock,
  'format': format,
  'color': 0xFF1C2A57,
  if (kind == 'cover')
    'files': {
      'pack': 'catalog/night_sky/$version/pack.zip',
      'sha256': sha256
          .convert(
            pack ??
                zip({
                  'cover.webp': [1],
                }),
          )
          .toString(),
      'bytes':
          (pack ??
                  zip({
                    'cover.webp': [1],
                  }))
              .length,
      'preview': 'catalog/night_sky/$version/preview.webp',
    },
  if (kind == 'paper')
    'paper': {
      'color': 0xFFEEF2EA,
      'lineColor': 0xFFAFC0A8,
      'pattern': 'dot',
      'spacing': 26,
    },
};

class FakeDownloader implements PackDownloader {
  final files = <String, Uint8List>{};
  final requested = <String>[];

  @override
  Future<Uint8List> download(String path, {required int maxBytes}) async {
    requested.add(path);
    await Future<void>.delayed(Duration.zero);
    final data = files[path];
    if (data == null) throw PackException(path, 'not found');
    return data;
  }
}

void main() {
  group('CatalogItem', () {
    test('reads a cover listing', () {
      final item = CatalogItem.fromMap('night_sky', listing())!;
      expect(item.kind, CatalogKind.cover);
      expect(item.unlock.free, isTrue);
      expect(item.files!.pack, 'catalog/night_sky/1/pack.zip');
      expect(item.isReadable, isTrue);
    });

    test('reads a paper listing with its paper inline', () {
      final item = CatalogItem.fromMap('sage', listing(kind: 'paper'))!;
      expect(item.paper!.pattern, PaperPattern.dot);
      expect(item.isReadable, isTrue);
    });

    test('a listing without a name or version is skipped', () {
      expect(CatalogItem.fromMap('x', {'kind': 'cover'}), isNull);
    });

    test('kinds and formats from newer apps are not readable', () {
      expect(
        CatalogItem.fromMap('x', listing(kind: 'hologram'))!.isReadable,
        isFalse,
      );
      expect(CatalogItem.fromMap('x', listing(format: 2))!.isReadable, isFalse);
    });

    test('a cover without files is not readable', () {
      final map = listing()..remove('files');
      expect(CatalogItem.fromMap('x', map)!.isReadable, isFalse);
    });

    test('visibility decides who is offered it', () {
      CatalogItem at(String v) =>
          CatalogItem.fromMap('x', listing(visibility: v))!;
      expect(at('public').isOffered(isTester: false), isTrue);
      expect(at('testers').isOffered(isTester: false), isFalse);
      expect(at('testers').isOffered(isTester: true), isTrue);
      expect(at('hidden').isOffered(isTester: true), isFalse);
      expect(at('retired').isOffered(isTester: true), isFalse);
      expect(at('nonsense').isOffered(isTester: true), isFalse);
    });
  });

  group('canUseCatalogItem', () {
    CatalogItem item(Map<String, Object?> unlock) =>
        CatalogItem.fromMap('night_sky', listing(unlock: unlock))!;

    test('free items are always usable', () {
      expect(Entitlements.none.canUseCatalogItem(item({'free': true})), isTrue);
    });

    test('Pro items need Pro', () {
      final pro = item({'pro': true});
      expect(Entitlements.none.canUseCatalogItem(pro), isFalse);
      expect(const Entitlements(pro: true).canUseCatalogItem(pro), isTrue);
    });

    test('sold items need one of their products', () {
      final sold = item({
        'products': ['pack_space', 'bundle_all'],
      });
      expect(Entitlements.none.canUseCatalogItem(sold), isFalse);
      expect(
        const Entitlements(products: {'bundle_all'}).canUseCatalogItem(sold),
        isTrue,
      );
    });

    test('a grant unlocks a single item', () {
      expect(
        const Entitlements(grants: {'night_sky'})
            .canUseCatalogItem(item({'pro': true})),
        isTrue,
      );
    });
  });

  group('PackCache', () {
    late FakeDownloader downloader;
    late MemoryPackDisk disk;
    late PackCache cache;

    setUp(() {
      downloader = FakeDownloader();
      disk = MemoryPackDisk();
      cache = PackCache(downloader, disk);
    });

    CatalogItem publish(Uint8List pack, {int version = 1}) {
      downloader.files['catalog/night_sky/$version/pack.zip'] = pack;
      return CatalogItem.fromMap(
        'night_sky',
        listing(version: version, pack: pack),
      )!;
    }

    test('downloads, unpacks and keeps a pack', () async {
      final item = publish(
        zip({
          'cover.webp': [1, 2, 3],
        }),
      );

      final files = await cache.files(item);

      expect(files['cover.webp'], [1, 2, 3]);
      expect(disk.versionsOf('night_sky'), {1});
    });

    test('a saved pack is not downloaded again', () async {
      final item = publish(
        zip({
          'cover.webp': [1],
        }),
      );
      await cache.files(item);

      final fresh = PackCache(downloader, disk);
      await fresh.files(item);

      expect(downloader.requested, hasLength(1));
    });

    test('several requests at once share one download', () async {
      final item = publish(
        zip({
          'cover.webp': [1],
        }),
      );

      await Future.wait([cache.files(item), cache.files(item)]);

      expect(downloader.requested, hasLength(1));
    });

    test('a pack that does not match its checksum is refused', () async {
      final item = publish(
        zip({
          'cover.webp': [1],
        }),
      );
      downloader.files[item.files!.pack] = zip({
        'cover.webp': [6, 6, 6],
      });

      expect(cache.files(item), throwsA(isA<PackException>()));
      await pumpEventQueue();
      expect(disk.versionsOf('night_sky'), isEmpty);
    });

    test('a new version replaces the old one on the device', () async {
      await cache.files(
        publish(
          zip({
            'cover.webp': [1],
          }),
        ),
      );
      final v2 = publish(
        zip({
          'cover.webp': [2],
        }),
        version: 2,
      );

      final files = await cache.files(v2);
      await pumpEventQueue();

      expect(files['cover.webp'], [2]);
      expect(disk.versionsOf('night_sky'), {2});
    });

    test('files that would escape the pack folder are dropped', () async {
      final item = publish(
        zip({
          'cover.webp': [1],
          '../escape.txt': [9],
          '/etc/passwd': [9],
        }),
      );

      expect((await cache.files(item)).keys, ['cover.webp']);
    });

    test('previews are downloaded once', () async {
      final item = publish(
        zip({
          'cover.webp': [1],
        }),
      );
      downloader.files[item.files!.preview!] = Uint8List.fromList([7]);

      expect(await cache.preview(item), [7]);
      expect(await cache.preview(item), [7]);
      expect(
        downloader.requested.where((p) => p.endsWith('preview.webp')),
        hasLength(1),
      );
    });
  });
}
