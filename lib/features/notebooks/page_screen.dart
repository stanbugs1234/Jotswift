import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/skins/skin_providers.dart';
import '../../core/skins/widgets/page_style.dart';
import '../../shared/dialogs.dart';
import '../canvas/ink_toolbar.dart';
import '../canvas/page_canvas.dart';
import 'notes_providers.dart';
import 'paper_picker.dart';

/// A single page: handwriting on phones and tablets, view-only on the web.
class PageScreen extends ConsumerWidget {
  const PageScreen({required this.pageId, this.readOnly = kIsWeb, super.key});

  final String pageId;

  /// Defaults to true on the web, where ink is view-only.
  final bool readOnly;

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final title = await askForText(
      context,
      title: 'Page title',
      confirmLabel: 'Save',
      initialValue: current,
    );
    if (title != null) {
      await ref.read(notebookRepositoryProvider).renamePage(pageId, title);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(pageProvider(pageId));

    if (page case AsyncData(value: null)) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This page was deleted.')),
      );
    }

    final title = page.value?.title ?? '';
    return PageStyle(
      style: ref.watch(pageStyleProvider(pageId)),
      child: Scaffold(
        appBar: AppBar(
          title: InkWell(
            onTap: () => _rename(context, ref, title),
            child: Text(page.value?.displayTitle ?? ''),
          ),
          actions: [
            if (!readOnly && page.value != null)
              IconButton(
                tooltip: 'Page paper',
                icon: const Icon(Icons.texture),
                onPressed: () async {
                  final p = page.value!;
                  final choice = await showPagePaperSheet(
                    context,
                    current: p.paper ?? notebookPaper(ref, p.notebookId),
                    offerNotebookPaper: true,
                  );
                  if (choice != null) {
                    await ref
                        .read(notebookRepositoryProvider)
                        .setPagePaper(pageId, choice.paper);
                  }
                },
              ),
            IconButton(
              tooltip: 'Rename page',
              icon: const Icon(Icons.edit_note),
              onPressed: () => _rename(context, ref, title),
            ),
          ],
        ),
        body: Column(
          children: [
            if (readOnly)
              const _ViewOnlyBanner()
            else
              InkToolbar(pageId: pageId),
            const Divider(height: 1),
            Expanded(
              child: PageCanvas(
                pageId: pageId,
                readOnly: readOnly,
                onOpenPage: (id) => context.go(
                  '/notebooks/${page.value!.notebookId}/pages/$id',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewOnlyBanner extends StatelessWidget {
  const _ViewOnlyBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        'Handwriting is view-only on the web. Use the Notely app on your '
        'phone or tablet to write.',
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}
