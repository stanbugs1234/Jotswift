import 'package:flutter/foundation.dart';

import '../paper/paper_style.dart';

/// What a catalog item is. Kinds this version doesn't know are kept as
/// [unknown] and never shown.
enum CatalogKind { cover, paper, template, stickers, collection, unknown }

/// Who sees an item in the app.
enum CatalogVisibility {
  /// Not shown (e.g. while its store products are being set up).
  hidden,

  /// Shown only to accounts marked as testers.
  testers,

  /// Shown to everyone.
  public,

  /// No longer offered, but still works for anyone already using it.
  retired,
}

/// The ways to unlock an item; any one is enough.
@immutable
class CatalogUnlock {
  const CatalogUnlock({
    this.free = false,
    this.pro = false,
    this.products = const [],
  });

  factory CatalogUnlock.fromMap(Object? map) {
    if (map is! Map) return const CatalogUnlock();
    return CatalogUnlock(
      free: map['free'] == true,
      pro: map['pro'] == true,
      products: [
        for (final p in map['products'] as List? ?? const []) ?(p as String?),
      ],
    );
  }

  final bool free;

  /// Included with Notely Pro.
  final bool pro;

  /// Store products that unlock it (a pack, a bundle, ...).
  final List<String> products;
}

/// The downloadable files of an item, in Cloud Storage.
@immutable
class CatalogFiles {
  const CatalogFiles({
    required this.pack,
    required this.sha256,
    required this.bytes,
    this.preview,
  });

  static CatalogFiles? fromMap(Object? map) {
    if (map is! Map) return null;
    final pack = map['pack'];
    final sha256 = map['sha256'];
    final bytes = map['bytes'];
    if (pack is! String || sha256 is! String || bytes is! int) return null;
    return CatalogFiles(
      pack: pack,
      sha256: sha256,
      bytes: bytes,
      preview: map['preview'] as String?,
    );
  }

  /// Storage path of the zip with the item's files.
  final String pack;

  /// Hex SHA-256 of the zip, checked after downloading.
  final String sha256;
  final int bytes;

  /// Storage path of a small preview image for the store and pickers.
  final String? preview;
}

/// One item in the catalog (Firestore `catalog/{id}`): what it is and how
/// it's offered. See docs/skins-plan.md §5.
@immutable
class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.kind,
    required this.name,
    required this.version,
    required this.unlock,
    required this.visibility,
    this.format = 1,
    this.collectionId,
    this.category,
    this.tags = const [],
    this.files,
    this.color,
    this.paper,
  });

  /// Reads a listing. Returns null if it's missing what every item needs.
  static CatalogItem? fromMap(String id, Map<String, dynamic> map) {
    final name = map['name'];
    final version = map['version'];
    if (name is! String || version is! int) return null;
    T byName<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.where((v) => v.name == name).firstOrNull ?? fallback;
    return CatalogItem(
      id: id,
      kind: byName(CatalogKind.values, map['kind'], CatalogKind.unknown),
      name: name,
      version: version,
      unlock: CatalogUnlock.fromMap(map['unlock']),
      visibility: byName(
        CatalogVisibility.values,
        map['visibility'],
        CatalogVisibility.hidden,
      ),
      format: map['format'] as int? ?? 1,
      collectionId: map['collectionId'] as String?,
      category: map['category'] as String?,
      tags: [for (final t in map['tags'] as List? ?? const []) ?(t as String?)],
      files: CatalogFiles.fromMap(map['files']),
      color: map['color'] as int?,
      paper: PaperStyle.fromMap(map['paper']),
    );
  }

  /// The newest listing format this app reads. Items with a higher
  /// [format] need a newer app and are skipped.
  static const supportedFormat = 1;

  final String id;
  final CatalogKind kind;
  final String name;

  /// Goes up whenever the item's files change, so devices download again.
  final int version;
  final CatalogUnlock unlock;
  final CatalogVisibility visibility;
  final int format;
  final String? collectionId;
  final String? category;
  final List<String> tags;
  final CatalogFiles? files;

  /// Covers: ARGB color shown while the image loads.
  final int? color;

  /// Papers: the paper itself (small enough to live in the listing).
  final PaperStyle? paper;

  /// Whether this app version can use the item at all.
  bool get isReadable =>
      format <= supportedFormat &&
      kind != CatalogKind.unknown &&
      switch (kind) {
        CatalogKind.cover || CatalogKind.stickers => files != null,
        CatalogKind.paper => paper != null,
        _ => true,
      };

  /// Whether the item is offered to a user ([isTester]: marked as a tester).
  bool isOffered({required bool isTester}) =>
      isReadable &&
      switch (visibility) {
        CatalogVisibility.public => true,
        CatalogVisibility.testers => isTester,
        CatalogVisibility.hidden || CatalogVisibility.retired => false,
      };
}
