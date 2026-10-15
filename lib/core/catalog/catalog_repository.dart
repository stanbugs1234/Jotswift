import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'catalog_item.dart';

/// The published catalog (Firestore `catalog/{id}`), managed with
/// tool/catalog.py and read-only to the app.
abstract interface class CatalogRepository {
  /// Every listing this app can read, including hidden and retired ones
  /// (so items already in use keep working).
  Stream<List<CatalogItem>> watchCatalog();
}

class FirestoreCatalogRepository implements CatalogRepository {
  FirestoreCatalogRepository(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Stream<List<CatalogItem>> watchCatalog() => _firestore
      .collection('catalog')
      .snapshots()
      .map((snap) => [for (final d in snap.docs) ?_read(d.id, d.data())]);

  static CatalogItem? _read(String id, Map<String, dynamic> data) {
    final item = CatalogItem.fromMap(id, data);
    if (item == null) debugPrint('Skipping catalog item "$id": incomplete');
    return item;
  }
}

/// A fixed catalog. Used in tests and without Firebase.
class InMemoryCatalogRepository implements CatalogRepository {
  InMemoryCatalogRepository([List<CatalogItem> items = const []])
    : _items = items;

  List<CatalogItem> _items;
  final _changes = StreamController<void>.broadcast();

  set items(List<CatalogItem> items) {
    _items = items;
    _changes.add(null);
  }

  @override
  Stream<List<CatalogItem>> watchCatalog() async* {
    yield _items;
    await for (final _ in _changes.stream) {
      yield _items;
    }
  }
}
