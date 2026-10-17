import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/catalog/catalog_item.dart';
import '../../core/paper/paper_style.dart';
import '../../shared/dialogs.dart';
import '../canvas/templates.dart';
import '../exports/export_sheet.dart';
import '../imports/import_actions.dart';
import '../shelf/shelf_actions.dart';
import 'domain/notebook_models.dart';
import 'new_page_sheet.dart';
import 'notes_providers.dart';
import 'page_grid.dart';
import 'paper_picker.dart';
import 'planner_builder.dart';
import 'my_templates.dart';

/// One notebook: its sections as tabs, and the pages in the chosen section.
class NotebookScreen extends ConsumerStatefulWidget {
  const NotebookScreen({
    required this.notebookId,
    this.newPageSearch,
    super.key,
  });

  final String notebookId;

  /// Opens the New page sheet straight away, searching for these words: a
  /// template's name, when it was chosen in the store.
  final String? newPageSearch;

  @override
  ConsumerState<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends ConsumerState<NotebookScreen> {
  String? _sectionId;

  @override
  void initState() {
    super.initState();
    ref.read(notebookRepositoryProvider).markNotebookOpened(widget.notebookId);
    if (widget.newPageSearch case final search?) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final sections = await ref
            .read(notebookRepositoryProvider)
            .watchSections(widget.notebookId)
            .first;
        if (!mounted || sections.isEmpty) return;
        await _newPageFromSheet(
          (_sectionId ?? sections.last.id),
          search: search,
        );
      });
    }
  }

  Future<void> _addSection() async {
    final title = await askForText(
      context,
      title: 'New section',
      confirmLabel: 'Add',
      hint: 'e.g. Lectures, Ideas',
    );
    if (title == null || !mounted) return;
    final section = await ref
        .read(notebookRepositoryProvider)
        .createSection(
          widget.notebookId,
          title.isEmpty ? 'Untitled section' : title,
        );
    setState(() => _sectionId = section.id);
  }

  Future<void> _sectionMenu(Section section, int sectionCount) async {
    final repo = ref.read(notebookRepositoryProvider);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename section'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            if (sectionCount > 1)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete section'),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'rename') {
      final title = await askForText(
        context,
        title: 'Rename section',
        confirmLabel: 'Rename',
        initialValue: section.title,
      );
      if (title != null && title.isNotEmpty) {
        await repo.renameSection(widget.notebookId, section.id, title);
      }
    } else if (action == 'delete') {
      final ok = await confirmDelete(
        context,
        title: 'Delete "${section.title}"?',
        message: 'This deletes the section and all its pages.',
      );
      if (ok) {
        setState(() => _sectionId = null);
        await repo.deleteSection(widget.notebookId, section.id);
      }
    }
  }

  Future<void> _newPage(String sectionId, {PaperStyle? paper}) async {
    final page = await ref
        .read(notebookRepositoryProvider)
        .createPage(widget.notebookId, sectionId, paper: paper);
    if (mounted) _openPage(page.id);
  }

  /// Asks what to add: a blank page, another paper or a template page.
  Future<void> _newPageFromSheet(String sectionId, {String? search}) async {
    final choice = await showNewPageSheet(
      context,
      paper: notebookPaper(ref, widget.notebookId),
      search: search,
    );
    if (!mounted) return;
    switch (choice) {
      case null:
        return;
      case BlankPageChoice():
        await _newPage(sectionId);
      case OtherPaperChoice():
        await _newPageWithPaper(sectionId);
      case TemplatePageChoice(:final page):
        final created = await ref
            .read(notebookRepositoryProvider)
            .createPage(
              widget.notebookId,
              sectionId,
              template: page.template,
              title: page.title,
            );
        if (mounted) _openPage(created.id);
      case WholePlannerChoice(:final item):
        await _addWholePlanner(item);
    }
  }

  /// Adds every page of the planner [item], as new sections, after asking
  /// its layout and which pages; then opens its first page.
  Future<void> _addWholePlanner(CatalogItem item) async {
    final choice = await showAddPlannerSheet(context, item);
    if (choice == null || !mounted) return;
    final add = ref.read(addPlannerPagesProvider);
    final first = await withPlannerProgress(
      context,
      (onProgress) => add(
        widget.notebookId,
        item,
        file: choice.file,
        skip: choice.skip,
        onProgress: onProgress,
      ),
    );
    if (first != null && mounted) _openPage(first);
  }

  Future<void> _importPages(String sectionId) async {
    final pageId = await importIntoSection(
      context,
      ref,
      widget.notebookId,
      sectionId,
    );
    if (pageId != null && mounted) _openPage(pageId);
  }

  Future<void> _newPageWithPaper(String sectionId) async {
    final choice = await showPagePaperSheet(
      context,
      current: notebookPaper(ref, widget.notebookId),
      title: 'New page',
      confirmLabel: 'Add page',
    );
    if (choice != null) await _newPage(sectionId, paper: choice.paper);
  }

  void _openPage(String pageId) =>
      context.go('/notebooks/${widget.notebookId}/pages/$pageId');

  @override
  Widget build(BuildContext context) {
    final notebook = ref.watch(notebookProvider(widget.notebookId));
    final sections = ref.watch(sectionsProvider(widget.notebookId)).value;

    if (notebook case AsyncData(value: null)) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This notebook was deleted.')),
      );
    }

    // Until a tab is picked, the section of the page open last.
    final lastPageId = notebook.value?.lastPageId;
    final lastSectionId = lastPageId == null
        ? null
        : ref.watch(pageProvider(lastPageId)).value?.sectionId;
    final current = sections == null || sections.isEmpty
        ? null
        : sections
                  .where((s) => s.id == (_sectionId ?? lastSectionId))
                  .firstOrNull ??
              sections.first;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          notebook.value?.isTemplate ?? false
              ? 'Template: ${notebook.value!.title}'
              : notebook.value?.title ?? '',
        ),
        actions: [
          ExportButton(notebookId: widget.notebookId, sectionId: current?.id),
          if (notebook.value case final nb?)
            PopupMenuButton<String>(
              tooltip: 'Notebook options',
              onSelected: (action) => switch (action) {
                'edit' => editNotebook(context, ref, nb),
                'save_template' => saveAsTemplate(context, ref, nb),
                'template' when current != null => _newPageFromSheet(
                  current.id,
                ),
                'import' when current != null => _importPages(current.id),
                _ when current != null => _newPageWithPaper(current.id),
                _ => null,
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Cover, paper & style'),
                ),
                if (!nb.isTemplate)
                  const PopupMenuItem(
                    value: 'save_template',
                    child: Text('Save as template'),
                  ),
                const PopupMenuItem(
                  value: 'page',
                  child: Text('New page with different paper'),
                ),
                const PopupMenuItem(
                  value: 'template',
                  child: Text('New page from template'),
                ),
                const PopupMenuItem(
                  value: 'import',
                  child: Text('Import PDF or images'),
                ),
              ],
            ),
        ],
        bottom: sections == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: _SectionTabs(
                  sections: sections,
                  selected: current,
                  onSelect: (s) => setState(() => _sectionId = s.id),
                  onLongPress: (s) => _sectionMenu(s, sections.length),
                  onAdd: _addSection,
                ),
              ),
      ),
      floatingActionButton: current == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _newPageFromSheet(current.id),
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('New page'),
            ),
      body: current == null
          ? const Center(child: CircularProgressIndicator())
          : PageGrid(
              notebookId: widget.notebookId,
              section: current,
              onOpen: _openPage,
              onCreate: () => _newPageFromSheet(current.id),
            ),
    );
  }
}

class _SectionTabs extends StatelessWidget {
  const _SectionTabs({
    required this.sections,
    required this.selected,
    required this.onSelect,
    required this.onLongPress,
    required this.onAdd,
  });

  final List<Section> sections;
  final Section? selected;
  final ValueChanged<Section> onSelect;
  final ValueChanged<Section> onLongPress;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          for (final s in sections)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onLongPress: () => onLongPress(s),
                child: ChoiceChip(
                  label: Text(s.title),
                  selected: s.id == selected?.id,
                  onSelected: (_) => onSelect(s),
                ),
              ),
            ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('Section'),
            tooltip: 'Add a section',
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}
