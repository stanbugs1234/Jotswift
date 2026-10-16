import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../notebooks/notes_providers.dart';
import '../notebooks/page_order.dart';
import 'page_export.dart';

/// A file to share: its name, contents and type.
typedef SharedFile = ({String name, Uint8List bytes, String mimeType});

/// Opens the share sheet with [files], pointing at [origin] (where the
/// share button is, for the iPad's popover). Replaced in tests.
final shareFilesProvider =
    Provider<Future<void> Function(List<SharedFile> files, Rect? origin)>(
      (ref) => (files, origin) async {
        await SharePlus.instance.share(
          ShareParams(
            files: [
              for (final f in files)
                XFile.fromData(f.bytes, mimeType: f.mimeType, name: f.name),
            ],
            fileNameOverrides: [for (final f in files) f.name],
            sharePositionOrigin: origin,
          ),
        );
      },
    );

/// Opens the system print dialog for [pdf]. Replaced in tests.
final printPdfProvider =
    Provider<Future<void> Function(Uint8List pdf, String name)>(
      (ref) => (pdf, name) async {
        await Printing.layoutPdf(onLayout: (_) async => pdf, name: name);
      },
    );

/// Which pages to export.
enum ExportScope { page, section, notebook }

/// What to make of them.
enum ExportFormat { pdf, png, print }

/// Asks what to export (this page, its section or the whole notebook) and
/// how (PDF, images or print), then does it. Without [pageId], offers the
/// notebook and [sectionId]'s section.
Future<void> showExportSheet(
  BuildContext context,
  WidgetRef ref, {
  required String notebookId,
  String? sectionId,
  String? pageId,
}) async {
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null || !box.hasSize
      ? null
      : box.localToGlobal(Offset.zero) & box.size;
  final choice = await showModalBottomSheet<(ExportScope, ExportFormat)>(
    context: context,
    showDragHandle: true,
    builder: (context) => _ExportSheet(
      scopes: [
        if (pageId != null) ExportScope.page,
        if (sectionId != null || pageId != null) ExportScope.section,
        ExportScope.notebook,
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  final (scope, format) = choice;
  final repo = ref.read(notebookRepositoryProvider);

  // The pages, in reading order, and a name for the file.
  final notebook = await repo.watchNotebook(notebookId).first;
  final page = pageId == null ? null : await repo.watchPage(pageId).first;
  final sections = await repo.watchSections(notebookId).first;
  final all = sortPages(
    sections,
    await repo.watchNotebookPages(notebookId).first,
  );
  final inSection = sectionId ?? page?.sectionId;
  final (pages, title) = switch (scope) {
    ExportScope.page => (
      [pageId!],
      '${notebook?.title ?? 'Notebook'} - ${page?.displayTitle ?? 'Page'}',
    ),
    ExportScope.section => (
      [
        for (final p in all)
          if (p.sectionId == inSection) p.id,
      ],
      '${notebook?.title ?? 'Notebook'} - '
          '${sections.where((s) => s.id == inSection).firstOrNull?.title ?? 'Section'}',
    ),
    ExportScope.notebook => (
      [for (final p in all) p.id],
      notebook?.title ?? 'Notebook',
    ),
  };
  if (pages.isEmpty || !context.mounted) return;

  final renderer = PageRenderer(context);
  final progress = ValueNotifier(0);
  final navigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: progress,
                builder: (context, done, _) => Text(
                  pages.length == 1
                      ? 'Preparing the page…'
                      : 'Preparing page ${done + 1 > pages.length ? pages.length : done + 1} '
                            'of ${pages.length}…',
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  var open = true;
  void close() {
    if (open) navigator.pop();
    open = false;
  }

  try {
    switch (format) {
      case ExportFormat.pdf || ExportFormat.print:
        final pdf = await pagesToPdf(
          renderer,
          pages,
          title: title,
          progress: (n) => progress.value = n,
        );
        close();
        if (format == ExportFormat.pdf) {
          await ref.read(shareFilesProvider)([
            (
              name: exportFileName(title, 'pdf'),
              bytes: pdf,
              mimeType: 'application/pdf',
            ),
          ], origin);
        } else {
          await ref.read(printPdfProvider)(pdf, title);
        }
      case ExportFormat.png:
        final pngs = await pagesToPng(
          renderer,
          pages,
          progress: (n) => progress.value = n,
        );
        close();
        await ref.read(shareFilesProvider)([
          for (final (i, png) in pngs.indexed)
            (
              name: exportFileName(
                pngs.length == 1 ? title : '$title ${i + 1}',
                'png',
              ),
              bytes: png,
              mimeType: 'image/png',
            ),
        ], origin);
    }
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not export. Please try again.')),
    );
  } finally {
    close();
    progress.dispose();
  }
}

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.scopes});

  final List<ExportScope> scopes;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  late ExportScope _scope = widget.scopes.first;

  @override
  Widget build(BuildContext context) {
    void done(ExportFormat format) => Navigator.pop(context, (_scope, format));
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Share or print',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (widget.scopes.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SegmentedButton<ExportScope>(
                segments: [
                  for (final s in widget.scopes)
                    ButtonSegment(
                      value: s,
                      label: Text(switch (s) {
                        ExportScope.page => 'This page',
                        ExportScope.section => 'Section',
                        ExportScope.notebook => 'Notebook',
                      }),
                    ),
                ],
                selected: {_scope},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _scope = s.single),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('Share as PDF'),
            onTap: () => done(ExportFormat.pdf),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Share as image'),
            subtitle: const Text('A PNG for each page'),
            onTap: () => done(ExportFormat.png),
          ),
          ListTile(
            leading: const Icon(Icons.print_outlined),
            title: const Text('Print'),
            onTap: () => done(ExportFormat.print),
          ),
        ],
      ),
    );
  }
}

/// The share button: exports [pageId] (when given), its section or the
/// whole notebook as a PDF or images, or prints them.
class ExportButton extends ConsumerWidget {
  const ExportButton({
    required this.notebookId,
    this.sectionId,
    this.pageId,
    super.key,
  });

  final String notebookId;
  final String? sectionId;
  final String? pageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Builder(
    // Its own context, so the iPad's share popover points at the button.
    builder: (context) => IconButton(
      tooltip: 'Share or print',
      icon: const Icon(Icons.ios_share),
      onPressed: () => showExportSheet(
        context,
        ref,
        notebookId: notebookId,
        sectionId: sectionId,
        pageId: pageId,
      ),
    ),
  );
}
