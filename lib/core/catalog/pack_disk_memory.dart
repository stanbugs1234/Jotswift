import 'dart:typed_data';

import 'pack_disk.dart';

PackDisk createPackDisk() => MemoryPackDisk();

/// Keeps packs in memory only. Used on the web and in tests.
class MemoryPackDisk implements PackDisk {
  final _packs = <(String, int), Map<String, Uint8List>>{};

  @override
  Future<Map<String, Uint8List>?> read(String id, int version) async =>
      _packs[(id, version)];

  @override
  Future<void> write(
    String id,
    int version,
    Map<String, Uint8List> files,
  ) async => _packs[(id, version)] = files;

  @override
  Future<void> removeOtherVersions(String id, int keep) async =>
      _packs.removeWhere((k, _) => k.$1 == id && k.$2 != keep);

  /// The versions of [id] that are saved (for tests).
  Set<int> versionsOf(String id) => {
    for (final k in _packs.keys)
      if (k.$1 == id) k.$2,
  };
}
