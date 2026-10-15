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
  StrokeRepository strokes(String uid) =>
      _FirestoreUserNotes(_firestore.doc('users/$uid'));
}

class _FirestoreUserNotes implements NotebookRepository, StrokeRepository {
  _FirestoreUserNotes(this._user);

  final DocumentReference<Map<String, dynamic>> _user;

  CollectionReference<Map<String, dynamic>> get _notebooks =>
      _user.collection('notebooks');
  CollectionReference<Map<String, dynamic>> _sections(String notebookId) =>
      _notebooks.doc(notebookId).collection('sections');
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
  }) async => _notebooks.doc(notebookId).update({
    'title': ?title,
    'cover': ?cover?.toMap(),
    'color': ?cover?.color,
    'paper': ?paper?.toMap(),
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
