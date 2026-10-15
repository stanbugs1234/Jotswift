import 'dart:math';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../notes_providers.dart';

/// Where the user's photos are kept: covers, and photos on pages.
abstract interface class CoverPhotoStore {
  /// Saves [jpeg] for [uid] in [folder] ("covers" or "images") and returns
  /// its path.
  Future<String> upload(String uid, Uint8List jpeg, {String folder});

  /// The image saved at [path].
  Future<ImageProvider> image(String path);
}

/// Keeps photos in Cloud Storage at `users/{uid}/{folder}/{id}.jpg`
/// (see firebase/storage.rules).
class FirebaseCoverPhotoStore implements CoverPhotoStore {
  FirebaseCoverPhotoStore(this._storage);

  final FirebaseStorage _storage;
  final _random = Random();

  @override
  Future<String> upload(
    String uid,
    Uint8List jpeg, {
    String folder = 'covers',
  }) async {
    final id =
        '${DateTime.now().millisecondsSinceEpoch}'
        '${_random.nextInt(1 << 30).toRadixString(36)}';
    final path = 'users/$uid/$folder/$id.jpg';
    await _storage
        .ref(path)
        .putData(jpeg, SettableMetadata(contentType: 'image/jpeg'));
    return path;
  }

  @override
  Future<ImageProvider> image(String path) async =>
      NetworkImage(await _storage.ref(path).getDownloadURL());
}

/// Keeps photos in memory. Used in tests and without Firebase.
class InMemoryCoverPhotoStore implements CoverPhotoStore {
  final _photos = <String, Uint8List>{};
  var _count = 0;

  @override
  Future<String> upload(
    String uid,
    Uint8List jpeg, {
    String folder = 'covers',
  }) async {
    final path = 'users/$uid/$folder/${_count++}.jpg';
    _photos[path] = jpeg;
    return path;
  }

  @override
  Future<ImageProvider> image(String path) async {
    final bytes = _photos[path];
    if (bytes == null) throw StateError('No photo at $path');
    return MemoryImage(bytes);
  }
}

/// Overridden in `main()` with Cloud Storage when Firebase is set up.
final coverPhotoStoreProvider = Provider<CoverPhotoStore>(
  (ref) => InMemoryCoverPhotoStore(),
);

/// A saved photo (a cover, or a photo on a page).
final coverPhotoProvider = FutureProvider.family<ImageProvider, String>(
  (ref, path) => ref.watch(coverPhotoStoreProvider).image(path),
);

/// Lets the user choose a photo, shrunk to fit [maxSize] (a cover by
/// default). Returns null if they cancel. Replaced in tests.
final photoPickerProvider =
    Provider<Future<Uint8List?> Function({Size maxSize})>(
      (ref) => ({Size maxSize = const Size(1536, 2048)}) async {
        final file = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: maxSize.width,
          maxHeight: maxSize.height,
          imageQuality: 85,
        );
        return file?.readAsBytes();
      },
    );

/// Asks for a photo and saves it. Returns its path, or null if cancelled.
/// Throws if it can't be saved (e.g. offline).
Future<String?> chooseCoverPhoto(WidgetRef ref) async {
  final bytes = await ref.read(photoPickerProvider)();
  if (bytes == null) return null;
  return ref
      .read(coverPhotoStoreProvider)
      .upload(ref.read(currentUidProvider), bytes);
}
