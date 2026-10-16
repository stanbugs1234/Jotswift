import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
Future<JumpTo?> showPageJumper(
  BuildContext context, {
  required String notebookId,
  required String currentPageId,
}) => showModalBottomSheet<JumpTo>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) =>
      _PageJumper(notebookId: notebookId, currentPageId: currentPageId),
);

class _PageJumper extends ConsumerStatefulWidget {
  const _PageJumper({required this.notebookId, required this.currentPageId});

  final String notebookId;
  final String currentPageId;

  @override
  ConsumerState<_PageJumper> createState() => _PageJumperState();
}

class _PageJumperState extends ConsumerState<_PageJumper> {
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    // Open with the current page in view (rows are about 48 high).
    final pages = ref.read(orderedPagesProvider(widget.notebookId));
    final index = pages.indexWhere((p) => p.id == widget.currentPageId);
    _scroll = ScrollController(
      initialScrollOffset: index <= 4 ? 0.0 : (index - 3) * 48.0,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notebookId = widget.notebookId, currentPageId = widget.currentPageId;
    final theme = Theme.of(context);
    final pages = ref.watch(orderedPagesProvider(notebookId));
    final sections = ref.watch(sectionsProvider(notebookId)).value ?? const [];
    final today = todaysPage(pages, ref.watch(todayProvider).toDateTime());
    final bookmarks = [
      for (final p in pages)
        if (p.bookmarked) p,
    ];

    Widget pageTile(NotePage p, {IconData? icon}) {
      final current = p.id == currentPageId;
      return ListTile(
        dense: true,
        selected: current,
        leading: icon == null ? null : Icon(icon, size: 20),
        title: Text(p.displayTitle),
        trailing: current ? const Text('Open now') : null,
        onTap: () => Navigator.pop(context, JumpToPage(p.id)),
      );
    }

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: theme.textTheme.titleSmall),
    );

    final children = <Widget>[
      if (today != null) pageTile(today, icon: Icons.today),
      if (bookmarks.isNotEmpty) ...[
        heading('Bookmarks'),
        for (final p in bookmarks) pageTile(p, icon: Icons.bookmark),
      ],
      for (final s in sections)
        if (pages.any((p) => p.sectionId == s.id)) ...[
          heading(s.title),
          for (final p in pages)
            if (p.sectionId == s.id) pageTile(p),
        ],
    ];
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
                      'Go to page',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.pop(context, const JumpToAllPages()),
                    icon: const Icon(Icons.grid_view),
                    label: const Text('All pages'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(controller: _scroll, children: children),
            ),
          ],
        ),
      ),
    );
  }
}
