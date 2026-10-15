import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/paper/paper_style.dart';
import '../../canvas/domain/stroke.dart';
import '../domain/notebook_models.dart';
import 'notes_repository.dart';

/// Stores notes in Firestore (see PLAN.md §4 for the layout):
///
/// ```
/// users/{uid}/notebooks/{notebookId}
/// users/{uid}/notebooks/{notebookId}/sections/{sectionId}
/// users/{uid}/categories/{categoryId}
/// users/{uid}/groups/{groupId}
/// users/{uid}/pages/{pageId}
/// users/{uid}/pages/{pageId}/strokes/{strokeId}
/// ```
///
/// Firestore's offline cache makes writes show up instantly and sync later.
class FirestoreNotesBackend implements NotesBackend {
  FirestoreNotesBackend(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  NotebookRepository notebooks(String uid) =>
      _FirestoreUserNotes(_firestore.doc('users/$uid'));

  @override
  ShelfRepository shelf(String uid) =>
      _FirestoreUserNotes(_firestore.doc('users/$uid'));

  @override
  StrokeRepository strokes(String uid) =>
      _FirestoreUserNotes(_firestore.doc('users/$uid'));
}

class _FirestoreUserNotes
    implements NotebookRepository, ShelfRepository, StrokeRepository {
  _FirestoreUserNotes(this._user);

  final DocumentReference<Map<String, dynamic>> _user;

  CollectionReference<Map<String, dynamic>> get _notebooks =>
      _user.collection('notebooks');
  CollectionReference<Map<String, dynamic>> _sections(String notebookId) =>
      _notebooks.doc(notebookId).collection('sections');
  CollectionReference<Map<String, dynamic>> get _categories =>
      _user.collection('categories');
  CollectionReference<Map<String, dynamic>> get _groups =>
      _user.collection('groups');
  CollectionReference<Map<String, dynamic>> get _pages =>
      _user.collection('pages');
  CollectionReference<Map<String, dynamic>> _strokes(String pageId) =>
      _pages.doc(pageId).collection('strokes');

  // Notebooks

  @override
  Stream<List<Notebook>> watchNotebooks() => _notebooks.snapshots().map(
    (snap) =>
        [for (final d in snap.docs) Notebook.fromMap(d.id, d.data())]
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
  );

  @override
  Stream<Notebook?> watchNotebook(String notebookId) =>
      _notebooks.doc(notebookId).snapshots().map((d) {
        final data = d.data();
        return data == null ? null : Notebook.fromMap(d.id, data);
      });

  @override
  Future<Notebook> createNotebook(NewNotebook spec) async {
    final ref = _notebooks.doc();
    final notebook = spec.build(ref.id, nowMillis());
    final section = _sections(ref.id).doc();
    final batch = ref.firestore.batch()
      ..set(ref, notebook.toMap())
      ..set(
        section,
        Section(
          id: section.id,
          notebookId: ref.id,
          title: 'Notes',
          order: 1,
        ).toMap(),
      );
    _commitInBackground(batch);
    return notebook;
  }

  @override
  Future<void> updateNotebook(
    String notebookId, {
    String? title,
    NotebookCover? cover,
    PaperStyle? paper,
    String? collectionId,
  }) async => _notebooks.doc(notebookId).update({
    'title': ?title,
    'cover': ?cover?.toMap(),
    'color': ?cover?.color,
    'paper': ?paper?.toMap(),
    'collectionId': ?collectionId,
    'updatedAt': nowMillis(),
  }).ignore();

  @override
  Future<void> deleteNotebook(String notebookId) async {
    final pages = await _pages.where('notebookId', isEqualTo: notebookId).get();
    for (final page in pages.docs) {
      await deletePage(page.id);
    }
    await _deleteAll(await _sections(notebookId).get());
    _notebooks.doc(notebookId).delete().ignore();
  }

  @override
  Future<void> markNotebookOpened(String notebookId) async =>
      _notebooks.doc(notebookId).update({'lastOpenedAt': nowMillis()}).ignore();

  @override
  Future<void> touchNotebook(String notebookId) async =>
      _notebooks.doc(notebookId).update({'updatedAt': nowMillis()}).ignore();

  // Shelf

  /// Only top-level items keep a category; see [NotebookGroup].
  static Object _categoryField(ShelfPlace place) =>
      place.groupId == null && place.categoryId != null
      ? place.categoryId!
      : FieldValue.delete();

  @override
  Stream<List<Category>> watchCategories() => _categories.snapshots().map(
    (snap) =>
        [for (final d in snap.docs) Category.fromMap(d.id, d.data())]
          ..sort((a, b) => a.order.compareTo(b.order)),
  );

  @override
  Future<Category> createCategory(String title) async {
    final existing = await _categories.get();
    final last = existing.docs
        .map((d) => (d.data()['order'] as num?)?.toDouble() ?? 0)
        .fold<double>(0, max);
    final ref = _categories.doc();
    final category = Category(id: ref.id, title: title, order: last + 1);
    _commitInBackground(ref.firestore.batch()..set(ref, category.toMap()));
    return category;
  }

  @override
  Future<void> renameCategory(String categoryId, String title) async =>
      _categories.doc(categoryId).update({'title': title}).ignore();

  @override
  Future<void> deleteCategory(String categoryId) async {
    final notebooks = await _notebooks
        .where('categoryId', isEqualTo: categoryId)
        .get();
    final groups = await _groups
        .where('categoryId', isEqualTo: categoryId)
        .get();
    final batch = _user.firestore.batch()..delete(_categories.doc(categoryId));
    for (final d in [...notebooks.docs, ...groups.docs]) {
      batch.update(d.reference, {'categoryId': FieldValue.delete()});
    }
    _commitInBackground(batch);
  }

  @override
  Stream<List<NotebookGroup>> watchGroups() => _groups.snapshots().map(
    (snap) =>
        [for (final d in snap.docs) NotebookGroup.fromMap(d.id, d.data())]
          ..sort((a, b) => a.order.compareTo(b.order)),
  );

  @override
  Future<NotebookGroup> createGroup(String title, ShelfPlace place) async {
    final now = nowMillis();
    final ref = _groups.doc();
    final group = NotebookGroup(
      id: ref.id,
      title: title,
      categoryId: place.groupId == null ? place.categoryId : null,
      parentGroupId: place.groupId,
      order: now.toDouble(),
      createdAt: now,
      updatedAt: now,
    );
    _commitInBackground(ref.firestore.batch()..set(ref, group.toMap()));
    return group;
  }

  @override
  Future<void> renameGroup(String groupId, String title) async => _groups
      .doc(groupId)
      .update({'title': title, 'updatedAt': nowMillis()})
      .ignore();

  @override
  Future<void> deleteGroup(String groupId) async {
    final group = await _groups.doc(groupId).get();
    final data = group.data();
    if (data == null) return;
    final up = NotebookGroup.fromMap(groupId, data);
    final place = (categoryId: up.categoryId, groupId: up.parentGroupId);
    final notebooks = await _notebooks
        .where('groupId', isEqualTo: groupId)
        .get();
    final children = await _groups
        .where('parentGroupId', isEqualTo: groupId)
        .get();
    final batch = _user.firestore.batch()..delete(group.reference);
    for (final d in notebooks.docs) {
      batch.update(d.reference, {
        'categoryId': _categoryField(place),
        'groupId': place.groupId ?? FieldValue.delete(),
      });
    }
    for (final d in children.docs) {
      batch.update(d.reference, {
        'categoryId': _categoryField(place),
        'parentGroupId': place.groupId ?? FieldValue.delete(),
      });
    }
    _commitInBackground(batch);
  }

  @override
  Future<void> moveNotebook(String notebookId, ShelfPlace place) async =>
      _notebooks.doc(notebookId).update({
        'categoryId': _categoryField(place),
        'groupId': place.groupId ?? FieldValue.delete(),
      }).ignore();

  @override
  Future<void> moveGroup(String groupId, ShelfPlace place) async =>
      _groups.doc(groupId).update({
        'categoryId': _categoryField(place),
        'parentGroupId': place.groupId ?? FieldValue.delete(),
        'updatedAt': nowMillis(),
      }).ignore();

  @override
  Future<void> setNotebookOrder(String notebookId, double order) async =>
      _notebooks.doc(notebookId).update({'order': order}).ignore();

  @override
  Future<void> setGroupOrder(String groupId, double order) async =>
      _groups.doc(groupId).update({'order': order}).ignore();

  // Sections

  @override
  Stream<List<Section>> watchSections(
    String notebookId,
  ) => _sections(notebookId).snapshots().map(
    (snap) =>
        [for (final d in snap.docs) Section.fromMap(d.id, notebookId, d.data())]
          ..sort((a, b) => a.order.compareTo(b.order)),
  );

  @override
  Future<Section> createSection(String notebookId, String title) async {
    final existing = await _sections(notebookId).get();
    final last = existing.docs
        .map((d) => (d.data()['order'] as num?)?.toDouble() ?? 0)
        .fold<double>(0, max);
    final ref = _sections(notebookId).doc();
    final section = Section(
      id: ref.id,
      notebookId: notebookId,
      title: title,
      order: last + 1,
    );
    _commitInBackground(ref.firestore.batch()..set(ref, section.toMap()));
    return section;
  }

  @override
  Future<void> renameSection(
    String notebookId,
    String sectionId,
    String title,
  ) async =>
      _sections(notebookId).doc(sectionId).update({'title': title}).ignore();

  @override
  Future<void> deleteSection(String notebookId, String sectionId) async {
    final pages = await _pages
        .where('notebookId', isEqualTo: notebookId)
        .where('sectionId', isEqualTo: sectionId)
        .get();
    for (final page in pages.docs) {
      await deletePage(page.id);
    }
    _sections(notebookId).doc(sectionId).delete().ignore();
  }

  // Pages

  @override
  Stream<List<NotePage>> watchPages(String notebookId, String sectionId) =>
      _pages
          .where('notebookId', isEqualTo: notebookId)
          .where('sectionId', isEqualTo: sectionId)
          .snapshots()
          .map(
            (snap) =>
                [for (final d in snap.docs) NotePage.fromMap(d.id, d.data())]
                  ..sort((a, b) => a.order.compareTo(b.order)),
          );

  @override
  Stream<NotePage?> watchPage(String pageId) =>
      _pages.doc(pageId).snapshots().map((d) {
        final data = d.data();
        return data == null ? null : NotePage.fromMap(d.id, data);
      });

  @override
  Future<NotePage> createPage(String notebookId, String sectionId) async {
    final existing = await _pages
        .where('notebookId', isEqualTo: notebookId)
        .where('sectionId', isEqualTo: sectionId)
        .get();
    final last = existing.docs
        .map((d) => (d.data()['order'] as num?)?.toDouble() ?? 0)
        .fold<double>(0, max);
    final now = nowMillis();
    final ref = _pages.doc();
    final page = NotePage(
      id: ref.id,
      notebookId: notebookId,
      sectionId: sectionId,
      title: '',
      order: last + 1,
      createdAt: now,
      updatedAt: now,
    );
    _commitInBackground(ref.firestore.batch()..set(ref, page.toMap()));
    return page;
  }

  @override
  Future<void> renamePage(String pageId, String title) async => _pages
      .doc(pageId)
      .update({'title': title, 'updatedAt': nowMillis()})
      .ignore();

  @override
  Future<void> setPagePaper(String pageId, PaperStyle? paper) async =>
      _pages.doc(pageId).update({
        'paper': paper?.toMap() ?? FieldValue.delete(),
        'updatedAt': nowMillis(),
      }).ignore();

  @override
  Future<void> deletePage(String pageId) async {
    await _deleteAll(await _strokes(pageId).get());
    _pages.doc(pageId).delete().ignore();
  }

  // Strokes

  @override
  String newStrokeId() => _pages.doc().id;

  @override
  Stream<List<Stroke>> watchStrokes(String pageId) =>
      _strokes(pageId).snapshots().map(
        (snap) =>
            [for (final d in snap.docs) Stroke.fromMap(d.id, d.data())]
              ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      );

  @override
  Future<void> addStroke(String pageId, Stroke stroke) async {
    final batch = _user.firestore.batch()
      ..set(_strokes(pageId).doc(stroke.id), stroke.toMap())
      ..update(_pages.doc(pageId), {'updatedAt': nowMillis()});
    _commitInBackground(batch);
  }

  @override
  Future<void> setDeleted(
    String pageId,
    List<String> strokeIds,
    bool deleted,
  ) async {
    for (var i = 0; i < strokeIds.length; i += _batchLimit) {
      final batch = _user.firestore.batch();
      for (final id in strokeIds.skip(i).take(_batchLimit)) {
        batch.update(_strokes(pageId).doc(id), {'deleted': deleted});
      }
      _commitInBackground(batch);
    }
  }

  static const _batchLimit = 450; // Firestore allows 500 writes per batch.

  Future<void> _deleteAll(QuerySnapshot<Map<String, dynamic>> snap) async {
    final docs = snap.docs;
    for (var i = 0; i < docs.length; i += _batchLimit) {
      final batch = _user.firestore.batch();
      for (final d in docs.skip(i).take(_batchLimit)) {
        batch.delete(d.reference);
      }
      _commitInBackground(batch);
    }
  }

  /// Applies [batch] to the local cache right away; the server copy syncs in
  /// the background (and after reconnecting, when offline). Awaiting the
  /// commit would wait for the server, which never comes while offline.
  void _commitInBackground(WriteBatch batch) {
    batch.commit().ignore();
  }
}
