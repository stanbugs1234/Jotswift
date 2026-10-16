import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notebooks/notes_providers.dart';
import 'document_import.dart';

/// Asks where to import from (Files or Photos), then lets the user choose.
/// Returns null if they cancel.
Future<List<ImportFile>?> chooseImportFiles(
  BuildContext context,
  WidgetRef ref,
) async {
  final source = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: const Text('From Files'),
            subtitle: const Text('PDFs and images'),
            onTap: () => Navigator.pop(context, 'files'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('From Photos'),
            subtitle: const Text('One page for each photo'),
            onTap: () => Navigator.pop(context, 'photos'),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;
  final files = await (source == 'files'
      ? ref.read(importFilesPickerProvider)()
      : ref.read(importPhotosPickerProvider)());
  return files == null || files.isEmpty ? null : files;
}

/// Imports [files], showing progress while it works. Returns the
/// documents, or null (after telling the user why) if it failed.
Future<List<ImportedDocument>?> importWithProgress(
  BuildContext context,
  WidgetRef ref,
  List<ImportFile> files,
) async {
  final importer = ref.read(documentImporterProvider);
  final navigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (context) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Importing…')),
          ],
        ),
      ),
    ),
  );
  try {
    return await importer.import(files);
  } on ImportException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Could not import. Check your connection and try again.'),
      ),
    );
  } finally {
    navigator.pop();
  }
  return null;
}

/// Asks for PDFs or images and adds their pages to the end of a section.
/// Returns the first new page's id, or null if nothing was imported.
Future<String?> importIntoSection(
  BuildContext context,
  WidgetRef ref,
  String notebookId,
  String sectionId,
) async {
  final files = await chooseImportFiles(context, ref);
  if (files == null || !context.mounted) return null;
  final documents = await importWithProgress(context, ref, files);
  if (documents == null) return null;
  final repo = ref.read(notebookRepositoryProvider);
  final before = await repo.watchPages(notebookId, sectionId).first;
  await repo.createPages(notebookId, sectionId, importedPages(documents));
  final after = await repo.watchPages(notebookId, sectionId).first;
  final known = {for (final p in before) p.id};
  return after.where((p) => !known.contains(p.id)).firstOrNull?.id;
}
