import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/dialogs.dart';
import '../../shared/ui/empty_state.dart';
import '../tasks/task_providers.dart' show todayProvider;
import 'domain/notebook_models.dart';
import 'notes_providers.dart';
import 'open_page.dart';
import 'page_order.dart';

/// What the jumper was asked to do.
sealed class JumpTo {
  const JumpTo();
}

/// Open this page.
final class JumpToPage extends JumpTo {
  const JumpToPage(this.pageId);

  final String pageId;
}

/// Show the notebook's page list.
final class JumpToAllPages extends JumpTo {
  const JumpToAllPages();
}

/// Lists a notebook's pages to jump to: today's page, bookmarks, then each
/// section. Returns what was picked, or null.
///
/// [choosing] a page for something else (a link), there's no "All pages".
Future<JumpTo?> showPageJumper(
  BuildContext context, {
  required String notebookId,
  required String currentPageId,
  String title = 'Go to page',
  bool choosing = false,
}) => showModalBottomSheet<JumpTo>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => _PageJumper(
    notebookId: notebookId,
    currentPageId: currentPageId,
    title: title,
    choosing: choosing,
  ),
);

class _PageJumper extends ConsumerStatefulWidget {
  const _PageJumper({
    required this.notebookId,
    required this.currentPageId,
    required this.title,
    required this.choosing,
  });

  final String notebookId;
  final String currentPageId;
  final String title;
  final bool choosing;

  @override
  ConsumerState<_PageJumper> createState() => _PageJumperState();
}

class _PageJumperState extends ConsumerState<_PageJumper> {
  final _scroll = ScrollController();
  final _current = GlobalKey();
  final _search = TextEditingController();
  String _query = '';

  /// Sections shown open, in a notebook long enough to fold them.
  late final Set<String> _open = {
    ?ref
        .read(orderedPagesProvider(widget.notebookId))
        .where((p) => p.id == widget.currentPageId)
        .firstOrNull
        ?.sectionId,
  };

  /// Notebooks with more pages than this fold their sections.
  static const foldFrom = 40;

  @override
  void initState() {
    super.initState();
    // Open with the current page in view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _current.currentContext;
      if (row != null && mounted) {
        Scrollable.ensureVisible(row, alignment: 0.3);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notebookId = widget.notebookId, currentPageId = widget.currentPageId;
    final theme = Theme.of(context);
    final pages = ref.watch(orderedPagesProvider(notebookId));
    final sections = ref.watch(sectionsProvider(notebookId)).value ?? const [];
    final today = todaysPage(pages, ref.watch(todayProvider).toDateTime());
    final first = pages.firstOrNull;
    final bookmarks = [
      for (final p in pages)
        if (p.bookmarked) p,
    ];
    final outline = [
      for (final p in pages)
        if (p.outline != null) p,
    ];
    final here = pages.where((p) => p.id == currentPageId).firstOrNull;
    final repo = ref.read(notebookRepositoryProvider);
    final fold = pages.length > foldFrom;
    final words = _query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final sectionTitles = {for (final s in sections) s.id: s.title};

    Future<void> nameEntry(NotePage p) async {
      final name = await askForText(
        context,
        title: p.outline == null ? 'Add to outline' : 'Rename outline entry',
        confirmLabel: p.outline == null ? 'Add' : 'Rename',
        initialValue: p.outline ?? p.title,
        hint: 'e.g. Chapter 2, Lab reports',
      );
      if (name != null && name.trim().isNotEmpty) {
        await repo.setPageOutline(p.id, name.trim());
      }
    }

    Widget outlineTile(NotePage p) => ListTile(
      dense: true,
      selected: p.id == currentPageId,
      leading: const Icon(Icons.format_list_bulleted, size: 20),
      title: Text(p.outline!),
      subtitle: Text(p.displayTitle),
      onTap: () => Navigator.pop(context, JumpToPage(p.id)),
      trailing: widget.choosing
          ? null
          : PopupMenuButton<bool>(
              tooltip: 'Outline entry options',
              onSelected: (rename) =>
                  rename ? nameEntry(p) : repo.setPageOutline(p.id, null),
              itemBuilder: (context) => const [
                PopupMenuItem(value: true, child: Text('Rename')),
                PopupMenuItem(value: false, child: Text('Remove from outline')),
              ],
            ),
    );

    Widget pageTile(
      NotePage p, {
      IconData? icon,
      String? subtitle,
      bool mark = true,
    }) {
      final current = p.id == currentPageId;
      return ListTile(
        key: current && mark ? _current : null,
        dense: true,
        selected: current,
        leading: icon == null ? null : Icon(icon, size: 20),
        title: Text(p.displayTitle),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: current
            ? Text(widget.choosing ? 'This page' : 'Open now')
            : null,
        onTap: () => Navigator.pop(context, JumpToPage(p.id)),
      );
    }

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: theme.textTheme.titleSmall),
    );

    // A section's heading; in a long notebook it opens and closes.
    Widget sectionHeading(Section s, int count) {
      if (!fold) return heading(s.title);
      final open = _open.contains(s.id);
      return ListTile(
        dense: true,
        title: Text(s.title, style: theme.textTheme.titleSmall),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$count',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            Icon(open ? Icons.expand_less : Icons.expand_more),
          ],
        ),
        onTap: () => setState(() {
          if (!_open.remove(s.id)) _open.add(s.id);
        }),
      );
    }

    final List<Widget> children;
    if (words.isNotEmpty) {
      // Searching: every page whose title or section has every word.
      final found = [
        for (final p in pages)
          if (words.every(
            ('${p.displayTitle} ${p.outline ?? ''} '
                    '${sectionTitles[p.sectionId] ?? ''}')
                .toLowerCase()
                .contains,
          ))
            p,
      ];
      children = found.isEmpty
          ? [
              const Padding(
                padding: EdgeInsets.only(top: 32),
                child: EmptyState(
                  icon: Icons.search_off,
                  title: 'No pages match.',
                ),
              ),
            ]
          : [
              for (final p in found)
                pageTile(p, subtitle: sectionTitles[p.sectionId]),
            ];
    } else {
      children = [
        if (today != null)
          pageTile(today, icon: Icons.today, subtitle: 'Today', mark: false),
        // A planner's first page is its Home.
        if (fold &&
            first != null &&
            first.id != today?.id &&
            first.id != currentPageId)
          pageTile(
            first,
            icon: Icons.home_outlined,
            subtitle: 'First page',
            mark: false,
          ),
        if (bookmarks.isNotEmpty) ...[
          heading('Bookmarks'),
          for (final p in bookmarks)
            pageTile(p, icon: Icons.bookmark, mark: false),
        ],
        if (outline.isNotEmpty) ...[
          heading('Outline'),
          for (final p in outline) outlineTile(p),
        ],
        for (final s in sections)
          if (pages.where((p) => p.sectionId == s.id).toList()
              case final inSection when inSection.isNotEmpty) ...[
            sectionHeading(s, inSection.length),
            if (!fold || _open.contains(s.id))
              for (final p in inSection) pageTile(p),
          ],
      ];
    }
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  if (!widget.choosing && here != null && here.outline == null)
                    IconButton(
                      tooltip: 'Add this page to the outline',
                      icon: const Icon(Icons.playlist_add),
                      onPressed: () => nameEntry(here),
                    ),
                  if (!widget.choosing)
                    TextButton.icon(
                      onPressed: () =>
                          Navigator.pop(context, const JumpToAllPages()),
                      icon: const Icon(Icons.grid_view),
                      label: const Text('All pages'),
                    ),
                ],
              ),
            ),
            if (pages.length > 12)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search pages',
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() {
                              _search.clear();
                              _query = '';
                            }),
                          ),
                  ),
                  onChanged: (q) => setState(() => _query = q),
                ),
              ),
            Expanded(
              child: ListView(
                controller: _scroll,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
