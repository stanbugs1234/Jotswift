import 'dart:async';
import 'dart:math';

import '../../../core/paper/paper_style.dart';
import '../../canvas/domain/page_element.dart';
import '../../canvas/domain/stroke.dart';
import '../domain/notebook_models.dart';
import 'notes_repository.dart';

/// Keeps everything in memory. Used in tests and while a platform has no
/// Firebase config. Nothing survives a restart.
class InMemoryNotesBackend implements NotesBackend {
  final _users = <String, _InMemoryUserData>{};

  _InMemoryUserData _user(String uid) =>
      _users.putIfAbsent(uid, _InMemoryUserData.new);

  @override
  NotebookRepository notebooks(String uid) => _user(uid);

  @override
  ShelfRepository shelf(String uid) => _user(uid);

  @override
  FavoritePapersRepository favoritePapers(String uid) => _user(uid);

  @override
  StrokeRepository strokes(String uid) => _user(uid);

  @override
  ElementRepository elements(String uid) => _user(uid);
}

class _InMemoryUserData
    implements
        NotebookRepository,
        ShelfRepository,
        FavoritePapersRepository,
        StrokeRepository,
        ElementRepository {
  final _favoritePapers = <String, PaperStyle>{};
  final _notebooks = <String, Notebook>{};
  final _categories = <String, Category>{};
  final _groups = <String, NotebookGroup>{};
  final _sections = <String, Section>{};
  final _pages = <String, NotePage>{};
  final _strokes = <String, Map<String, Stroke>>{}; // pageId -> id -> stroke
  // pageId -> element id -> element
  final _elements = <String, Map<String, PageElement>>{};
  final _changes = StreamController<void>.broadcast();
  final _random = Random();
  var _counter = 0;

  String _id() =>
      '${(_counter++).toRadixString(36)}${_random.nextInt(1 << 30).toRadixString(36)}';

  void _changed() => _changes.add(null);

  /// Emits [read] now and again after every change.
  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    await for (final _ in _changes.stream) {
      yield read();
    }
  }

  // Notebooks

  @override
  Stream<List<Notebook>> watchNotebooks() => _watch(
    () =>
        _notebooks.values.toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
  );

  @override
  Stream<Notebook?> watchNotebook(String notebookId) =>
      _watch(() => _notebooks[notebookId]);

  @override
  Future<Notebook> createNotebook(NewNotebook spec) async {
    final notebook = spec.build(_id(), nowMillis());
    _notebooks[notebook.id] = notebook;
    await createSection(notebook.id, 'Notes');
    return notebook;
  }

  @override
  Future<void> updateNotebook(
    String notebookId, {
    String? title,
    NotebookCover? cover,
    PaperStyle? paper,
    String? collectionId,
  }) async {
    final notebook = _notebooks[notebookId];
    if (notebook == null) return;
    _notebooks[notebookId] = notebook.copyWith(
      title: title,
      cover: cover,
      paper: paper,
      collectionId: collectionId,
      updatedAt: nowMillis(),
    );
    _changed();
  }

  @override
  Future<void> deleteNotebook(String notebookId) async {
    _notebooks.remove(notebookId);
    _sections.removeWhere((_, s) => s.notebookId == notebookId);
    final pageIds = [
      for (final p in _pages.values)
        if (p.notebookId == notebookId) p.id,
    ];
    pageIds.forEach(_removePage);
    _changed();
  }

  @override
  Future<void> markNotebookOpened(String notebookId) async =>
      _updateNotebook(notebookId, (n) => n.copyWith(lastOpenedAt: nowMillis()));

  @override
  Future<void> touchNotebook(String notebookId) async =>
      _updateNotebook(notebookId, (n) => n.copyWith(updatedAt: nowMillis()));

  void _updateNotebook(String id, Notebook Function(Notebook) change) {
    final notebook = _notebooks[id];
    if (notebook == null) return;
    _notebooks[id] = change(notebook);
    _changed();
  }

  // Shelf

  @override
  Stream<List<Category>> watchCategories() => _watch(
    () =>
        _categories.values.toList()..sort((a, b) => a.order.compareTo(b.order)),
  );

  @override
  Future<Category> createCategory(String title) async {
    final last = _categories.values.fold<double>(0, (m, c) => max(m, c.order));
    final category = Category(id: _id(), title: title, order: last + 1);
    _categories[category.id] = category;
    _changed();
    return category;
  }

  @override
  Future<void> renameCategory(String categoryId, String title) async {
    final c = _categories[categoryId];
    if (c == null) return;
    _categories[categoryId] = Category(id: c.id, title: title, order: c.order);
    _changed();
  }

  @override
  Future<void> deleteCategory(String categoryId) async {
    _categories.remove(categoryId);
    for (final n in [..._notebooks.values]) {
      if (n.categoryId == categoryId) {
        _notebooks[n.id] = n.copyWith(place: unfiled);
      }
    }
    for (final g in [..._groups.values]) {
      if (g.categoryId == categoryId) {
        _groups[g.id] = _copyGroup(g, place: unfiled);
      }
    }
    _changed();
  }

  @override
  Stream<List<NotebookGroup>> watchGroups() => _watch(
    () => _groups.values.toList()..sort((a, b) => a.order.compareTo(b.order)),
  );

  @override
  Future<NotebookGroup> createGroup(String title, ShelfPlace place) async {
    final now = nowMillis();
    final group = _copyGroup(
      NotebookGroup(
        id: _id(),
        title: title,
        order: now.toDouble(),
        createdAt: now,
        updatedAt: now,
      ),
      place: place,
    );
    _groups[group.id] = group;
    _changed();
    return group;
  }

  @override
  Future<void> renameGroup(String groupId, String title) async {
    final g = _groups[groupId];
    if (g == null) return;
    _groups[groupId] = _copyGroup(g, title: title);
    _changed();
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    final group = _groups.remove(groupId);
    if (group == null) return;
    final up = (categoryId: group.categoryId, groupId: group.parentGroupId);
    for (final n in [..._notebooks.values]) {
      if (n.groupId == groupId) _notebooks[n.id] = n.copyWith(place: up);
    }
    for (final g in [..._groups.values]) {
      if (g.parentGroupId == groupId) _groups[g.id] = _copyGroup(g, place: up);
    }
    _changed();
  }

  @override
  Future<void> moveNotebook(String notebookId, ShelfPlace place) async =>
      _updateNotebook(notebookId, (n) => n.copyWith(place: place));

  @override
  Future<void> moveGroup(String groupId, ShelfPlace place) async {
    final g = _groups[groupId];
    if (g == null) return;
    _groups[groupId] = _copyGroup(g, place: place);
    _changed();
  }

  @override
  Future<void> setNotebookOrder(String notebookId, double order) async =>
      _updateNotebook(notebookId, (n) => n.copyWith(order: order));

  @override
  Future<void> setGroupOrder(String groupId, double order) async {
    final g = _groups[groupId];
    if (g == null) return;
    _groups[groupId] = _copyGroup(g, order: order);
    _changed();
  }

  @override
  Future<void> setStarred(String notebookId, bool starred) async =>
      _updateNotebook(notebookId, (n) => n.copyWith(starred: starred));

  @override
  Future<void> setTrashed(String notebookId, bool trashed) async =>
      _updateNotebook(
        notebookId,
        (n) => trashed
            ? n.copyWith(trashedAt: nowMillis())
            : n.copyWith(restore: true),
      );

  NotebookGroup _copyGroup(
    NotebookGroup g, {
    String? title,
    double? order,
    ShelfPlace? place,
  }) => NotebookGroup(
    id: g.id,
    title: title ?? g.title,
    order: order ?? g.order,
    createdAt: g.createdAt,
    updatedAt: nowMillis(),
    categoryId: place == null
        ? g.categoryId
        : (place.groupId == null ? place.categoryId : null),
    parentGroupId: place == null ? g.parentGroupId : place.groupId,
  );

  // Favorite papers

  @override
  Stream<List<PaperStyle>> watchFavoritePapers() =>
      _watch(() => _favoritePapers.values.toList().reversed.toList());

  @override
  Future<void> setFavoritePaper(
    PaperStyle paper, {
    required bool favorite,
  }) async {
    _favoritePapers.remove(paper.key);
    if (favorite) _favoritePapers[paper.key] = paper;
    _changed();
  }

  // Sections

  @override
  Stream<List<Section>> watchSections(String notebookId) => _watch(
    () =>
        _sections.values.where((s) => s.notebookId == notebookId).toList()
          ..sort((a, b) => a.order.compareTo(b.order)),
  );

  @override
  Future<Section> createSection(String notebookId, String title) async {
    final last = _sections.values
        .where((s) => s.notebookId == notebookId)
        .fold<double>(0, (m, s) => max(m, s.order));
    final section = Section(
      id: _id(),
      notebookId: notebookId,
      title: title,
      order: last + 1,
    );
    _sections[section.id] = section;
    _changed();
    return section;
  }

  @override
  Future<void> renameSection(
    String notebookId,
    String sectionId,
    String title,
  ) async {
    final s = _sections[sectionId];
    if (s == null) return;
    _sections[sectionId] = Section(
      id: s.id,
      notebookId: s.notebookId,
      title: title,
      order: s.order,
    );
    _changed();
  }

  @override
  Future<void> deleteSection(String notebookId, String sectionId) async {
    _sections.remove(sectionId);
    final pageIds = [
      for (final p in _pages.values)
        if (p.sectionId == sectionId) p.id,
    ];
    pageIds.forEach(_removePage);
    _changed();
  }

  // Pages

  @override
  Stream<List<NotePage>> watchPages(String notebookId, String sectionId) =>
      _watch(
        () =>
            _pages.values
                .where(
                  (p) => p.notebookId == notebookId && p.sectionId == sectionId,
                )
                .toList()
              ..sort((a, b) => a.order.compareTo(b.order)),
      );

  @override
  Stream<NotePage?> watchPage(String pageId) => _watch(() => _pages[pageId]);

  @override
  Future<NotePage> createPage(
    String notebookId,
    String sectionId, {
    PaperStyle? paper,
    PageTemplate? template,
    String title = '',
  }) async {
    final last = _pages.values
        .where((p) => p.sectionId == sectionId)
        .fold<double>(0, (m, p) => max(m, p.order));
    final now = nowMillis();
    final page = NotePage(
      id: _id(),
      notebookId: notebookId,
      sectionId: sectionId,
      title: title,
      order: last + 1,
      createdAt: now,
      updatedAt: now,
      paper: paper,
      template: template,
    );
    _pages[page.id] = page;
    _changed();
    return page;
  }

  @override
  Future<void> createPages(
    String notebookId,
    String sectionId,
    List<NewPage> pages,
  ) async {
    var last = _pages.values
        .where((p) => p.sectionId == sectionId)
        .fold<double>(0, (m, p) => max(m, p.order));
    final now = nowMillis();
    for (final spec in pages) {
      final page = NotePage(
        id: _id(),
        notebookId: notebookId,
        sectionId: sectionId,
        title: spec.title,
        order: ++last,
        createdAt: now,
        updatedAt: now,
        paper: spec.paper,
        template: spec.template,
      );
      _pages[page.id] = page;
    }
    _changed();
  }

  @override
  Stream<List<NotePage>> watchNotebookPages(String notebookId) => _watch(
    () => _pages.values.where((p) => p.notebookId == notebookId).toList(),
  );

  @override
  Future<void> ensurePage(
    String pageId, {
    required String notebookId,
    required String title,
  }) async {
    if (_pages.containsKey(pageId)) return;
    final now = nowMillis();
    _pages[pageId] = NotePage(
      id: pageId,
      notebookId: notebookId,
      sectionId: notebookId,
      title: title,
      order: 0,
      createdAt: now,
      updatedAt: now,
    );
    _changed();
  }

  @override
  Future<void> renamePage(String pageId, String title) async {
    final p = _pages[pageId];
    if (p == null) return;
    _pages[pageId] = p.copyWith(title: title, updatedAt: nowMillis());
    _changed();
  }

  @override
  Future<void> setPagePaper(String pageId, PaperStyle? paper) async {
    final p = _pages[pageId];
    if (p == null) return;
    _pages[pageId] = p.copyWith(paper: () => paper, updatedAt: nowMillis());
    _changed();
  }

  @override
  Future<void> deletePage(String pageId) async {
    _removePage(pageId);
    _changed();
  }

  void _removePage(String pageId) {
    _pages.remove(pageId);
    _strokes.remove(pageId);
    _elements.remove(pageId);
  }

  // Strokes

  @override
  String newStrokeId() => _id();

  @override
  Stream<List<Stroke>> watchStrokes(String pageId) => _watch(
    () =>
        (_strokes[pageId]?.values.toList() ?? <Stroke>[])
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
  );

  @override
  Future<void> addStroke(String pageId, Stroke stroke) async {
    _strokes.putIfAbsent(pageId, () => {})[stroke.id] = stroke;
    _changed();
  }

  @override
  Future<void> setDeleted(
    String pageId,
    List<String> strokeIds,
    bool deleted,
  ) async {
    final strokes = _strokes[pageId];
    if (strokes == null) return;
    for (final id in strokeIds) {
      final s = strokes[id];
      if (s != null) strokes[id] = s.copyWith(deleted: deleted);
    }
    _changed();
  }

  @override
  Future<void> replaceStrokes(
    String pageId, {
    required List<String> remove,
    required List<Stroke> add,
  }) async {
    final strokes = _strokes.putIfAbsent(pageId, () => {});
    for (final id in remove) {
      final s = strokes[id];
      if (s != null) strokes[id] = s.copyWith(deleted: true);
    }
    for (final s in add) {
      strokes[s.id] = s;
    }
    _changed();
  }

  // Elements

  @override
  String newElementId() => _id();

  @override
  Stream<List<PageElement>> watchElements(String pageId) => _watch(
    () =>
        (_elements[pageId]?.values.toList() ?? <PageElement>[])
          ..sort((a, b) => a.z.compareTo(b.z)),
  );

  @override
  Future<void> addElement(String pageId, PageElement element) async {
    _elements.putIfAbsent(pageId, () => {})[element.id] = element;
    _changed();
  }

  @override
  Future<void> setElementFrame(
    String pageId,
    String elementId,
    ElementFrame frame,
  ) async => _updateElement(pageId, elementId, (e) => e.copyWith(frame: frame));

  @override
  Future<void> setElementContent(
    String pageId,
    String elementId,
    ElementContent content,
    ElementFrame frame,
  ) async => _updateElement(
    pageId,
    elementId,
    (e) => e.copyWith(content: content, frame: frame),
  );

  @override
  Future<void> setElementDeleted(
    String pageId,
    String elementId, {
    required bool deleted,
  }) async =>
      _updateElement(pageId, elementId, (e) => e.copyWith(deleted: deleted));

  void _updateElement(
    String pageId,
    String id,
    PageElement Function(PageElement) change,
  ) {
    final e = _elements[pageId]?[id];
    if (e == null) return;
    _elements[pageId]![id] = change(e);
    _changed();
  }
}
