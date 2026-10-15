import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'catalog_item.dart';
import 'pack_disk.dart';

/// Thrown when a downloaded pack doesn't match its listing.
class PackException implements Exception {
  PackException(this.itemId, this.message);

  final String itemId;
  final String message;

  @override
  String toString() => 'Pack "$itemId": $message';
}

/// Downloads a file from Cloud Storage.
abstract interface class PackDownloader {
  Future<Uint8List> download(String path, {required int maxBytes});
}

class FirebasePackDownloader implements PackDownloader {
  FirebasePackDownloader(this._storage);

  final FirebaseStorage _storage;

  @override
  Future<Uint8List> download(String path, {required int maxBytes}) async {
    final data = await _storage.ref(path).getData(maxBytes);
    if (data == null) throw PackException(path, 'not found');
    return data;
  }
}

/// The files of catalog items, downloaded once and kept on the device.
class PackCache {
  PackCache(this._download, this._disk);

  final PackDownloader _download;
  final PackDisk _disk;
  final _memory = <(String, int), Map<String, Uint8List>>{};
  final _loading = <(String, int), Future<Map<String, Uint8List>>>{};
  final _previews = <String, Future<Uint8List>>{};

  /// Packs larger than this are refused (templates are the biggest).
  static const maxPackBytes = 25 * 1024 * 1024;
  static const maxPreviewBytes = 1024 * 1024;

  /// The unpacked files of [item]: from memory, else from the device, else
  /// downloaded (checked against the listing, then saved).
  Future<Map<String, Uint8List>> files(CatalogItem item) {
    final key = (item.id, item.version);
    if (_memory[key] case final files?) return Future.value(files);
    // Several covers asking at once share one download.
    return _loading[key] ??= _load(item).whenComplete(() {
      // A block, not `=> remove(...)`: whenComplete would wait for the
      // returned future, which is this one.
      _loading.remove(key);
    });
  }

  Future<Map<String, Uint8List>> _load(CatalogItem item) async {
    final key = (item.id, item.version);
    final saved = await _disk.read(item.id, item.version);
    if (saved != null) return _memory[key] = saved;

    final info = item.files;
    if (info == null) throw PackException(item.id, 'has no files');
    if (info.bytes > maxPackBytes) {
      throw PackException(item.id, 'is too large (${info.bytes} bytes)');
    }
    final zip = await _download.download(info.pack, maxBytes: maxPackBytes);
    if (sha256.convert(zip).toString() != info.sha256) {
      throw PackException(item.id, "doesn't match its checksum");
    }
    final files = <String, Uint8List>{
      for (final f in ZipDecoder().decodeBytes(zip))
        if (f.isFile && _isSafeName(f.name)) f.name: f.readBytes()!,
    };
    await _disk.write(item.id, item.version, files);
    unawaited(_disk.removeOtherVersions(item.id, item.version));
    return _memory[key] = files;
  }

  /// Rejects names that could escape the pack's folder.
  static bool _isSafeName(String name) =>
      name.isNotEmpty &&
      !name.startsWith('/') &&
      !name.split('/').contains('..');

  /// The preview image of [item], or null if it has none.
  Future<Uint8List?> preview(CatalogItem item) async {
    final path = item.files?.preview;
    if (path == null) return null;
    return _previews[path] ??= _download
        .download(path, maxBytes: maxPreviewBytes)
        .catchError((Object e) {
          _previews.remove(path);
          throw e;
        });
  }
}
