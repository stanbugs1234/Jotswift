import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/paper/paper_style.dart';
import '../../shared/dialogs.dart';
import '../canvas/templates.dart';
import '../shelf/shelf_actions.dart';
import 'domain/notebook_models.dart';
import 'notes_providers.dart';
import 'paper_picker.dart';

/// One notebook: its sections as tabs, and the pages in the chosen section.
class NotebookScreen extends ConsumerStatefulWidget {
  const NotebookScreen({required this.notebookId, super.key});

  final String notebookId;

  @override
  ConsumerState<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends ConsumerState<NotebookScreen> {
  String? _sectionId;

  @override
  void initState() {
    super.initState();
    ref.read(notebookRepositoryProvider).markNotebookOpened(widget.notebookId);
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

  Future<void> _newPageFromTemplate(String sectionId) async {
    final spec = await showTemplatePageSheet(context);
    if (spec == null || !mounted) return;
    final page = await ref
        .read(notebookRepositoryProvider)
        .createPage(
          widget.notebookId,
          sectionId,
          template: spec.template,
          title: spec.title,
        );
    if (mounted) _openPage(page.id);
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

    final current = sections == null || sections.isEmpty
        ? null
        : sections.where((s) => s.id == _sectionId).firstOrNull ??
              sections.first;

    return Scaffold(
      appBar: AppBar(
        title: Text(notebook.value?.title ?? ''),
        actions: [
          if (notebook.value case final nb?)
            PopupMenuButton<String>(
              tooltip: 'Notebook options',
              onSelected: (action) => switch (action) {
                'edit' => editNotebook(context, ref, nb),
                'template' when current != null => _newPageFromTemplate(
                  current.id,
                ),
                _ when current != null => _newPageWithPaper(current.id),
                _ => null,
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: Text('Cover, paper & style'),
                ),
                PopupMenuItem(
                  value: 'page',
                  child: Text('New page with different paper'),
                ),
                PopupMenuItem(
                  value: 'template',
                  child: Text('New page from template'),
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
              onPressed: () => _newPage(current.id),
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('New page'),
            ),
      body: current == null
          ? const Center(child: CircularProgressIndicator())
          : _PageList(
              notebookId: widget.notebookId,
              section: current,
              onOpen: _openPage,
              onCreate: () => _newPage(current.id),
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

class _PageList extends ConsumerWidget {
  const _PageList({
    required this.notebookId,
    required this.section,
    required this.onOpen,
    required this.onCreate,
  });

  final String notebookId;
  final Section section;
  final ValueChanged<String> onOpen;
  final VoidCallback onCreate;

  Future<void> _pageMenu(
    BuildContext context,
    WidgetRef ref,
    NotePage page,
    String action,
  ) async {
    final repo = ref.read(notebookRepositoryProvider);
    if (action == 'rename') {
      final title = await askForText(
        context,
        title: 'Rename page',
        confirmLabel: 'Rename',
        initialValue: page.title,
      );
      if (title != null) await repo.renamePage(page.id, title);
    } else if (action == 'paper') {
      final choice = await showPagePaperSheet(
        context,
        current: page.paper ?? notebookPaper(ref, notebookId),
        offerNotebookPaper: true,
      );
      if (choice != null) await repo.setPagePaper(page.id, choice.paper);
    } else if (action == 'delete') {
      final ok = await confirmDelete(
        context,
        title: 'Delete "${page.displayTitle}"?',
        message: 'This deletes the page and everything written on it.',
      );
      if (ok) await repo.deletePage(page.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pages = ref
        .watch(pagesProvider((notebookId: notebookId, sectionId: section.id)))
        .value;
    if (pages == null) return const Center(child: CircularProgressIndicator());
    if (pages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('No pages in ${section.title} yet.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Add a page'),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: pages.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final page = pages[i];
        return ListTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(page.displayTitle),
          subtitle: Text('Edited ${_formatDate(page.updatedAt)}'),
          onTap: () => onOpen(page.id),
          trailing: PopupMenuButton<String>(
            tooltip: 'Page options',
            onSelected: (a) => _pageMenu(context, ref, page, a),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'paper', child: Text('Change paper')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        );
      },
    );
  }
}

String _formatDate(int millis) {
  final d = DateTime.fromMillisecondsSinceEpoch(millis);
  final now = DateTime.now();
  final time =
      '${d.hour % 12 == 0 ? 12 : d.hour % 12}:${d.minute.toString().padLeft(2, '0')} '
      '${d.hour < 12 ? 'AM' : 'PM'}';
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    return 'today at $time';
  }
  return '${d.month}/${d.day}/${d.year}';
}
