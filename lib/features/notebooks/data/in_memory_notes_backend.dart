import 'dart:async';
import 'dart:math';

import '../../../core/paper/paper_style.dart';
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
  StrokeRepository strokes(String uid) => _user(uid);
}

class _InMemoryUserData implements NotebookRepository, StrokeRepository {
  final _notebooks = <String, Notebook>{};
  final _sections = <String, Section>{};
  final _pages = <String, NotePage>{};
  final _strokes = <String, Map<String, Stroke>>{}; // pageId -> id -> stroke
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
  }) async {
    final notebook = _notebooks[notebookId];
    if (notebook == null) return;
    _notebooks[notebookId] = notebook.copyWith(
      title: title,
      cover: cover,
      paper: paper,
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
  Future<NotePage> createPage(String notebookId, String sectionId) async {
    final last = _pages.values
        .where((p) => p.sectionId == sectionId)
        .fold<double>(0, (m, p) => max(m, p.order));
    final now = nowMillis();
    final page = NotePage(
      id: _id(),
      notebookId: notebookId,
      sectionId: sectionId,
      title: '',
      order: last + 1,
      createdAt: now,
      updatedAt: now,
    );
    _pages[page.id] = page;
    _changed();
    return page;
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
}
