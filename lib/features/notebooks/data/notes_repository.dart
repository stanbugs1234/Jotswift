import '../../../core/paper/paper_style.dart';
import '../../canvas/domain/stroke.dart';
import '../domain/notebook_models.dart';

/// Notebooks, sections and pages for one signed-in user.
abstract interface class NotebookRepository {
  Stream<List<Notebook>> watchNotebooks();
  Stream<Notebook?> watchNotebook(String notebookId);

  /// Creates a notebook with one empty section.
  Future<Notebook> createNotebook(NewNotebook notebook);
  Future<void> updateNotebook(
    String notebookId, {
    String? title,
    NotebookCover? cover,
    PaperStyle? paper,
    String? collectionId,
  });

  /// Deletes the notebook with all its sections, pages and ink.
  Future<void> deleteNotebook(String notebookId);

  Stream<List<Section>> watchSections(String notebookId);
  Future<Section> createSection(String notebookId, String title);
  Future<void> renameSection(String notebookId, String sectionId, String title);

  /// Deletes the section with all its pages and ink.
  Future<void> deleteSection(String notebookId, String sectionId);

  Stream<List<NotePage>> watchPages(String notebookId, String sectionId);
  Stream<NotePage?> watchPage(String pageId);
  Future<NotePage> createPage(String notebookId, String sectionId);
  Future<void> renamePage(String pageId, String title);

  /// Gives one page its own paper, or (with null) goes back to the
  /// notebook's paper.
  Future<void> setPagePaper(String pageId, PaperStyle? paper);
  Future<void> deletePage(String pageId);
}

/// Ink strokes for one signed-in user's pages.
abstract interface class StrokeRepository {
  /// A new unique stroke id.
  String newStrokeId();

  /// Every stroke on the page, including erased ones (see [Stroke.deleted]).
  Stream<List<Stroke>> watchStrokes(String pageId);
  Future<void> addStroke(String pageId, Stroke stroke);

  /// Erases ([deleted] = true) or restores strokes, in one write.
  Future<void> setDeleted(String pageId, List<String> strokeIds, bool deleted);
}

/// Creates the repositories for a user. In the app this is backed by
/// Firestore; tests and platforms without Firebase use memory.
abstract interface class NotesBackend {
  NotebookRepository notebooks(String uid);
  StrokeRepository strokes(String uid);
}

int nowMillis() => DateTime.now().millisecondsSinceEpoch;
