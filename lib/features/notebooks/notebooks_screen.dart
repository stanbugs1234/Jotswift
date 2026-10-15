import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/dialogs.dart';
import 'domain/notebook_models.dart';
import 'notes_providers.dart';

/// The shelf: every notebook the user has.
class NotebooksScreen extends ConsumerWidget {
  const NotebooksScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref, int count) async {
    final title = await askForText(
      context,
      title: 'New notebook',
      confirmLabel: 'Create',
      hint: 'e.g. School, Work, Journal',
    );
    if (title == null || !context.mounted) return;
    final notebook = await ref
        .read(notebookRepositoryProvider)
        .createNotebook(
          NewNotebook(
            title: title.isEmpty ? 'Untitled notebook' : title,
            cover: NotebookCover.color(
              notebookColors[count % notebookColors.length],
            ),
          ),
        );
    if (context.mounted) context.go('/notebooks/${notebook.id}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notebooks = ref.watch(notebooksProvider);
    final count = notebooks.value?.length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notebooks'),
        actions: [
          IconButton(
            tooltip: 'Notebook styles',
            icon: const Icon(Icons.palette_outlined),
            onPressed: () => context.push('/settings/skins'),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref, count),
        icon: const Icon(Icons.add),
        label: const Text('New notebook'),
      ),
      body: switch (notebooks) {
        AsyncData(value: final list) when list.isEmpty => _EmptyShelf(
          onCreate: () => _create(context, ref, 0),
        ),
        AsyncData(value: final list) => GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 200,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.72,
          ),
          itemCount: list.length,
          itemBuilder: (context, i) => NotebookTile(notebook: list[i]),
        ),
        AsyncError(:final error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load notebooks.\n$error'),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('No notebooks yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Create a notebook to start writing.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Create a notebook'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _NotebookAction { rename, color, delete }

/// A notebook drawn as a book cover.
class NotebookTile extends ConsumerWidget {
  const NotebookTile({required this.notebook, super.key});

  final Notebook notebook;

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    _NotebookAction action,
  ) async {
    final repo = ref.read(notebookRepositoryProvider);
    switch (action) {
      case _NotebookAction.rename:
        final title = await askForText(
          context,
          title: 'Rename notebook',
          confirmLabel: 'Rename',
          initialValue: notebook.title,
        );
        if (title != null && title.isNotEmpty) {
          await repo.updateNotebook(notebook.id, title: title);
        }
      case _NotebookAction.color:
        final i = notebookColors.indexOf(notebook.cover.color);
        await repo.updateNotebook(
          notebook.id,
          cover: NotebookCover.color(
            notebookColors[(i + 1) % notebookColors.length],
          ),
        );
      case _NotebookAction.delete:
        final ok = await confirmDelete(
          context,
          title: 'Delete "${notebook.title}"?',
          message:
              'This deletes the notebook and every page in it. '
              'It cannot be undone.',
        );
        if (ok) await repo.deleteNotebook(notebook.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = Color(notebook.cover.color);
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;

    return Semantics(
      button: true,
      label: '${notebook.title} notebook',
      child: Material(
        color: color,
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(4),
          right: Radius.circular(12),
        ),
        elevation: 2,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.go('/notebooks/${notebook.id}'),
          child: Stack(
            children: [
              // Spine.
              Positioned(
                left: 10,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 3,
                  color: onColor.withValues(alpha: 0.25),
                ),
              ),
              Positioned(
                left: 24,
                right: 8,
                top: 24,
                child: Text(
                  notebook.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: onColor, fontWeight: FontWeight.w600),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: PopupMenuButton<_NotebookAction>(
                  tooltip: 'Notebook options',
                  iconColor: onColor,
                  onSelected: (a) => _onAction(context, ref, a),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _NotebookAction.rename,
                      child: Text('Rename'),
                    ),
                    PopupMenuItem(
                      value: _NotebookAction.color,
                      child: Text('Change color'),
                    ),
                    PopupMenuItem(
                      value: _NotebookAction.delete,
                      child: Text('Delete'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
