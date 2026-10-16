import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/synced_setting.dart';
import '../../shared/ui/tokens.dart';
import '../canvas/handwriting.dart';
import '../notebooks/domain/notebook_models.dart';
import '../notebooks/notes_providers.dart';

/// Pages whose handwriting has been read, in every notebook.
final handwrittenPagesProvider = StreamProvider<List<NotePage>>(
  (ref) => ref.watch(notebookRepositoryProvider).watchHandwrittenPages(),
);

/// A page whose handwriting matches a search, with the words around the
/// match and where the match is in them.
typedef HandwritingHit = ({
  NotePage page,
  Notebook notebook,
  String snippet,
  int start,
  int end,
});

/// The pages, in notebooks not in the Trash, whose handwriting contains
/// [query] (any case), newest first.
List<HandwritingHit> searchHandwriting(
  List<NotePage> pages,
  List<Notebook> notebooks,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final byId = {
    for (final n in notebooks)
      if (!n.inTrash) n.id: n,
  };
  final hits = <HandwritingHit>[];
  for (final page in pages) {
    final notebook = byId[page.notebookId];
    final text = page.inkText?.replaceAll(RegExp(r'\s+'), ' ') ?? '';
    final at = text.toLowerCase().indexOf(q);
    if (notebook == null || at < 0) continue;
    // Some words either side.
    const around = 36;
    var from = (at - around).clamp(0, text.length);
    var to = (at + q.length + around).clamp(0, text.length);
    if (from > 0) from = text.lastIndexOf(' ', from) + 1;
    if (to < text.length) {
      final space = text.indexOf(' ', to);
      to = space < 0 ? text.length : space;
    }
    final lead = from > 0 ? '…' : '';
    hits.add((
      page: page,
      notebook: notebook,
      snippet: '$lead${text.substring(from, to)}${to < text.length ? '…' : ''}',
      start: lead.length + at - from,
      end: lead.length + at - from + q.length,
    ));
  }
  hits.sort((a, b) => b.page.updatedAt.compareTo(a.page.updatedAt));
  return hits;
}

/// "In your handwriting": the pages that match, to open.
class HandwritingResults extends StatelessWidget {
  const HandwritingResults({required this.hits, super.key});

  final List<HandwritingHit> hits;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gutter = gutterOf(context);
    return SliverList.list(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, Insets.xl, gutter, Insets.sm),
          child: Text(
            'In your handwriting',
            style: theme.textTheme.titleMedium,
          ),
        ),
        for (final hit in hits)
          ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: gutter),
            leading: const Icon(Icons.draw_outlined),
            title: Text(
              '${hit.notebook.title} · ${hit.page.displayTitle}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: hit.snippet.substring(0, hit.start)),
                  TextSpan(
                    text: hit.snippet.substring(hit.start, hit.end),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  TextSpan(text: hit.snippet.substring(hit.end)),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => context.push(
              '/notebooks/${hit.page.notebookId}/pages/${hit.page.id}',
            ),
          ),
      ],
    );
  }
}

const _caughtUpKey = 'handwritingCaughtUp';

/// Whether pages written before search could read handwriting still need
/// reading on this device (it only needs doing once; new writing is read
/// as it's written).
bool needsCatchingUp(WidgetRef ref) =>
    ref.read(handwritingReaderProvider) != null &&
    !(ref.read(sharedPreferencesProvider).getBool(_caughtUpKey) ?? false);

/// Reads the handwriting on every page that hasn't been read, showing
/// progress, so search finds older notes too.
Future<void> catchUpHandwriting(BuildContext context, WidgetRef ref) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final prefs = ref.read(sharedPreferencesProvider);
  final pages = [
    for (final p in await ref.read(notebookRepositoryProvider).allPages())
      if (p.inkText == null) p,
  ];
  if (!context.mounted) return;
  final done = ValueNotifier(0);
  var cancelled = false;
  final dialog = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Reading your handwriting'),
      content: ValueListenableBuilder<int>(
        valueListenable: done,
        builder: (context, n, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: pages.isEmpty ? null : n / pages.length,
            ),
            const SizedBox(height: Insets.md),
            Text('$n of ${pages.length} pages. It stays on this device.'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            cancelled = true;
            Navigator.of(context).pop();
          },
          child: const Text('Stop'),
        ),
      ],
    ),
  );
  for (final page in pages) {
    if (cancelled) break;
    try {
      await indexPageInk(container, page.id);
    } catch (_) {
      // A page that can't be read is left for next time.
    }
    done.value++;
  }
  if (!cancelled) {
    await prefs.setBool(_caughtUpKey, true);
    if (context.mounted) Navigator.of(context).pop();
  }
  await dialog;
  done.dispose();
}
