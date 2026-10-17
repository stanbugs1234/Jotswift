import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notebooks/domain/notebook_models.dart';
import '../notebooks/notes_providers.dart';
import '../shelf/cover_view.dart';

/// Asks which notebook to use, most recently opened first. Returns null if
/// cancelled.
Future<Notebook?> pickNotebook(BuildContext context, {required String title}) =>
    showDialog<Notebook>(
      context: context,
      builder: (context) => _NotebookPicker(title: title),
    );

class _NotebookPicker extends ConsumerWidget {
  const _NotebookPicker({required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notebooks = [...?ref.watch(notebooksProvider).value]
      ..sort(
        (a, b) => (b.lastOpenedAt ?? b.updatedAt).compareTo(
          a.lastOpenedAt ?? a.updatedAt,
        ),
      );
    return AlertDialog(
      title: Text(title),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: SizedBox(
        width: 420,
        height: notebooks.isEmpty ? null : 420,
        child: notebooks.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text('Make a notebook first, then add these pages.'),
              )
            : ListView.builder(
                itemCount: notebooks.length,
                itemBuilder: (context, i) {
                  final n = notebooks[i];
                  return ListTile(
                    leading: SizedBox(
                      width: 32,
                      child: CoverView(cover: n.cover, elevation: 0),
                    ),
                    title: Text(
                      n.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.pop(context, n),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
