import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'pack_disk.dart';

PackDisk createPackDisk() => IoPackDisk();

/// Keeps packs in the app's support folder:
/// `<support>/catalog/<id>/<version>/<file>`.
class IoPackDisk implements PackDisk {
  Future<Directory> _itemDir(String id) async =>
      Directory('${(await getApplicationSupportDirectory()).path}/catalog/$id');

  @override
  Future<Map<String, Uint8List>?> read(String id, int version) async {
    final dir = Directory('${(await _itemDir(id)).path}/$version');
    if (!dir.existsSync()) return null;
    return {
      for (final f in dir.listSync(recursive: true).whereType<File>())
        f.path.substring(dir.path.length + 1): await f.readAsBytes(),
    };
  }

  @override
  Future<void> write(
    String id,
    int version,
    Map<String, Uint8List> files,
  ) async {
    final item = await _itemDir(id);
    // Write to a temporary folder first, so a crash never leaves half a
    // pack where a whole one is expected.
    final temp = Directory('${item.path}/$version.partial');
    if (temp.existsSync()) temp.deleteSync(recursive: true);
    for (final MapEntry(key: name, value: bytes) in files.entries) {
      final file = File('${temp.path}/$name');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
    }
    final done = Directory('${item.path}/$version');
    if (done.existsSync()) done.deleteSync(recursive: true);
    await temp.rename(done.path);
  }

  @override
  Future<void> removeOtherVersions(String id, int keep) async {
    final item = await _itemDir(id);
    if (!item.existsSync()) return;
    for (final dir in item.listSync().whereType<Directory>()) {
      if (dir.uri.pathSegments.where((s) => s.isNotEmpty).last != '$keep') {
        dir.deleteSync(recursive: true);
      }
    }
  }
}
