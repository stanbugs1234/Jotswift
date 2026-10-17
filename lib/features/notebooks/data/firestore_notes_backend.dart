import 'dart:math';

import '../../audio/recording.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/paper/paper_style.dart';
import '../../canvas/domain/page_element.dart';
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
/// users/{uid}/favoritePapers/{paperKey}
/// users/{uid}/pages/{pageId}
/// users/{uid}/pages/{pageId}/strokes/{strokeId}
/// users/{uid}/pages/{pageId}/elements/{elementId}
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
  FavoritePapersRepository favoritePapers(String uid) =>
      _FirestoreUserNotes(_firestore.doc('users/$uid'));

  @override
  StrokeRepository strokes(String uid) =>
      _FirestoreUserNotes(_firestore.doc('users/$uid'));

  @override
  ElementRepository elements(String uid) =>
      _FirestoreUserNotes(_firestore.doc('users/$uid'));
}

class _FirestoreUserNotes
    implements
        NotebookRepository,
        ShelfRepository,
        FavoritePapersRepository,
        StrokeRepository,
        ElementRepository {
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
  CollectionReference<Map<String, dynamic>> get _favoritePapers =>
      _user.collection('favoritePapers');
  CollectionReference<Map<String, dynamic>> get _pages =>
      _user.collection('pages');
  CollectionReference<Map<String, dynamic>> _strokes(String pageId) =>
      _pages.doc(pageId).collection('strokes');
  CollectionReference<Map<String, dynamic>> _elements(String pageId) =>
      _pages.doc(pageId).collection('elements');

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
    // The notebook goes first, so it leaves the shelf at once; its pages
    // and ink are cleaned up after, all at the same time rather than one
    // page after another (a planner has dozens of pages).
    _notebooks.doc(notebookId).delete().ignore();
    final (pages, sections) = await (
      _pages.where('notebookId', isEqualTo: notebookId).get(),
      _sections(notebookId).get(),
    ).wait;
    await _deleteAll(sections);
    await Future.wait([for (final page in pages.docs) deletePage(page.id)]);
  }

  @override
  Future<void> markPageOpened(NotePage page) async {
    final now = nowMillis();
    _notebooks.doc(page.notebookId).update({
      'lastOpenedAt': now,
      'lastPageId': page.id,
      'lastPageTitle': page.displayTitle,
      'lastPageAt': now,
    }).ignore();
  }

  CollectionReference<Map<String, dynamic>> _recordings(String notebookId) =>
      _notebooks.doc(notebookId).collection('recordings');

  @override
  Stream<List<Recording>> watchRecordings(String notebookId) =>
      _recordings(notebookId).snapshots().map(
        (snap) =>
            [for (final d in snap.docs) ?Recording.fromMap(d.id, d.data())]
              ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      );

  @override
  Future<void> addRecording(String notebookId, Recording recording) async =>
      _recordings(notebookId).doc(recording.id).set(recording.toMap()).ignore();

  @override
  Future<void> deleteRecording(String notebookId, String recordingId) async =>
      _recordings(notebookId).doc(recordingId).delete().ignore();

  @override
  String newRecordingId() => _notebooks.doc().id;

  @override
  Future<void> setPageInkText(String pageId, String text) async =>
      _pages.doc(pageId).update({'inkText': text}).ignore();

  @override
  Stream<List<NotePage>> watchHandwrittenPages() => _pages
      .where('inkText', isGreaterThan: '')
      .snapshots()
      .map(
        (snap) => [for (final d in snap.docs) NotePage.fromMap(d.id, d.data())],
      );

  @override
  Future<List<NotePage>> allPages() async => [
    for (final d in (await _pages.get()).docs) NotePage.fromMap(d.id, d.data()),
  ];

  @override
  Future<void> setPageOutline(String pageId, String? outline) async => _pages
      .doc(pageId)
      .update({'outline': outline ?? FieldValue.delete()})
      .ignore();

  @override
  Future<void> setPageBookmarked(String pageId, bool bookmarked) async => _pages
      .doc(pageId)
      .update({'bookmarked': bookmarked ? true : FieldValue.delete()})
      .ignore();

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

  @override
  Future<void> setStarred(String notebookId, bool starred) async => _notebooks
      .doc(notebookId)
      .update({'starred': starred ? true : FieldValue.delete()})
      .ignore();

  @override
  Future<void> setTags(String notebookId, List<String> tags) async => _notebooks
      .doc(notebookId)
      .update({'tags': tags.isEmpty ? FieldValue.delete() : tags})
      .ignore();

  @override
  Future<void> setTrashed(String notebookId, bool trashed) async => _notebooks
      .doc(notebookId)
      .update({'trashedAt': trashed ? nowMillis() : FieldValue.delete()})
      .ignore();

  // Favorite papers

  @override
  Stream<List<PaperStyle>> watchFavoritePapers() => _favoritePapers
      .orderBy('addedAt', descending: true)
      .snapshots()
      .map(
        (snap) => [
          for (final d in snap.docs) ?PaperStyle.fromMap(d.data()['paper']),
        ],
      );

  @override
  Future<void> setFavoritePaper(
    PaperStyle paper, {
    required bool favorite,
  }) async {
    final ref = _favoritePapers.doc(paper.key);
    final batch = _user.firestore.batch();
    if (favorite) {
      batch.set(ref, {'paper': paper.toMap(), 'addedAt': nowMillis()});
    } else {
      batch.delete(ref);
    }
    _commitInBackground(batch);
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
    _sections(notebookId).doc(sectionId).delete().ignore();
    await Future.wait([for (final page in pages.docs) deletePage(page.id)]);
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
  Future<void> ensurePage(
    String pageId, {
    required String notebookId,
    required String title,
  }) async {
    // A merge with fixed values, so two devices doing this at once agree.
    _pages.doc(pageId).set({
      'notebookId': notebookId,
      'sectionId': notebookId,
      'title': title,
      'order': 0,
    }, SetOptions(merge: true)).ignore();
  }

  @override
  Future<NotePage> createPage(
    String notebookId,
    String sectionId, {
    PaperStyle? paper,
    PageTemplate? template,
    String title = '',
  }) async {
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
      title: title,
      order: last + 1,
      createdAt: now,
      updatedAt: now,
      paper: paper,
      template: template,
    );
    _commitInBackground(ref.firestore.batch()..set(ref, page.toMap()));
    return page;
  }

  @override
  Future<void> createPages(
    String notebookId,
    String sectionId,
    List<NewPage> pages, {
    List<PagePeriod?> periods = const [],
  }) async {
    final existing = await _pages
        .where('notebookId', isEqualTo: notebookId)
        .where('sectionId', isEqualTo: sectionId)
        .get();
    var last = existing.docs
        .map((d) => (d.data()['order'] as num?)?.toDouble() ?? 0)
        .fold<double>(0, max);
    final now = nowMillis();
    for (var i = 0; i < pages.length; i += _batchLimit) {
      final batch = _user.firestore.batch();
      for (final (j, spec) in pages.skip(i).take(_batchLimit).indexed) {
        final ref = _pages.doc();
        final n = i + j;
        batch.set(
          ref,
          NotePage(
            id: ref.id,
            notebookId: notebookId,
            sectionId: sectionId,
            title: spec.title,
            order: ++last,
            createdAt: now,
            updatedAt: now,
            paper: spec.paper,
            template: spec.template,
            period: n < periods.length ? periods[n] : null,
          ).toMap(),
        );
      }
      _commitInBackground(batch);
    }
  }

  @override
  Stream<List<NotePage>> watchNotebookPages(String notebookId) => _pages
      .where('notebookId', isEqualTo: notebookId)
      .snapshots()
      .map(
        (snap) => [for (final d in snap.docs) NotePage.fromMap(d.id, d.data())],
      );

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
  Future<void> setPageBackground(
    String pageId, {
    PageTemplate? template,
    PaperStyle? paper,
  }) async => _pages.doc(pageId).update({
    'template': template?.toMap() ?? FieldValue.delete(),
    'paper': paper?.toMap() ?? FieldValue.delete(),
    'updatedAt': nowMillis(),
  }).ignore();

  @override
  Future<void> deletePage(String pageId) async {
    _pages.doc(pageId).delete().ignore();
    final (strokes, elements) = await (
      _strokes(pageId).get(),
      _elements(pageId).get(),
    ).wait;
    await _deleteAll(strokes);
    await _deleteAll(elements);
  }

  @override
  Future<void> movePage(
    String pageId, {
    required String notebookId,
    required String sectionId,
    required double order,
  }) async => _pages.doc(pageId).update({
    'notebookId': notebookId,
    'sectionId': sectionId,
    'order': order,
    'updatedAt': nowMillis(),
  }).ignore();

  @override
  Future<String> copyPage(
    String pageId, {
    required String notebookId,
    required String sectionId,
    required double order,
  }) async {
    final source = await _pages.doc(pageId).get();
    final data = source.data();
    if (data == null) throw StateError('No page $pageId');
    final strokes = await _strokes(pageId).get();
    final elements = await _elements(pageId).get();
    final ref = _pages.doc();
    final now = nowMillis();
    final writes = <void Function(WriteBatch)>[
      (b) => b.set(ref, {
        ...data,
        'notebookId': notebookId,
        'sectionId': sectionId,
        'order': order,
        'createdAt': now,
        'updatedAt': now,
      }),
      for (final d in strokes.docs)
        if (d.data()['deleted'] != true)
          (b) => b.set(_strokes(ref.id).doc(d.id), d.data()),
      for (final d in elements.docs)
        if (d.data()['deleted'] != true)
          (b) => b.set(_elements(ref.id).doc(d.id), d.data()),
    ];
    for (var i = 0; i < writes.length; i += _batchLimit) {
      final batch = _user.firestore.batch();
      for (final write in writes.skip(i).take(_batchLimit)) {
        write(batch);
      }
      _commitInBackground(batch);
    }
    return ref.id;
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

  @override
  Future<void> replaceStrokes(
    String pageId, {
    required List<String> remove,
    required List<Stroke> add,
  }) async {
    final writes = <void Function(WriteBatch)>[
      for (final id in remove)
        (b) => b.update(_strokes(pageId).doc(id), {'deleted': true}),
      for (final s in add) (b) => b.set(_strokes(pageId).doc(s.id), s.toMap()),
    ];
    for (var i = 0; i < writes.length; i += _batchLimit) {
      final batch = _user.firestore.batch();
      for (final write in writes.skip(i).take(_batchLimit)) {
        write(batch);
      }
      if (i == 0) batch.update(_pages.doc(pageId), {'updatedAt': nowMillis()});
      _commitInBackground(batch);
    }
  }

  // Elements

  @override
  String newElementId() => _pages.doc().id;

  @override
  Stream<List<PageElement>> watchElements(String pageId) =>
      _elements(pageId).snapshots().map(
        (snap) =>
            [for (final d in snap.docs) ?PageElement.fromMap(d.id, d.data())]
              ..sort((a, b) => a.z.compareTo(b.z)),
      );

  @override
  Future<void> addElement(String pageId, PageElement element) async {
    final batch = _user.firestore.batch()
      ..set(_elements(pageId).doc(element.id), element.toMap())
      ..update(_pages.doc(pageId), {'updatedAt': nowMillis()});
    _commitInBackground(batch);
  }

  @override
  Future<void> setElementFrame(
    String pageId,
    String elementId,
    ElementFrame frame,
  ) async =>
      _elements(pageId)
          .doc(elementId)
          .update(PageElement.frameToMap(frame))
          .ignore();

  @override
  Future<void> setElementContent(
    String pageId,
    String elementId,
    ElementContent content,
    ElementFrame frame,
  ) async =>
      _elements(pageId)
          .doc(elementId)
          .update({...content.toMap(), ...PageElement.frameToMap(frame)})
          .ignore();

  @override
  Future<void> setElementDeleted(
    String pageId,
    String elementId, {
    required bool deleted,
  }) async =>
      _elements(pageId).doc(elementId).update({'deleted': deleted}).ignore();

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
