import 'dart:typed_data';

import 'pack_disk_memory.dart'
    if (dart.library.io) 'pack_disk_io.dart'
    as platform;

/// Keeps unpacked catalog packs on the device, one folder per item and
/// version.
abstract interface class PackDisk {
  /// The files of [id] at [version], or null if they aren't saved.
  Future<Map<String, Uint8List>?> read(String id, int version);
  Future<void> write(String id, int version, Map<String, Uint8List> files);

  /// Removes the saved versions of [id] other than [keep].
  Future<void> removeOtherVersions(String id, int keep);
}

/// Files on phones, tablets and desktops; memory on the web (where the
/// browser caches the downloads).
PackDisk createPackDisk() => platform.createPackDisk();
