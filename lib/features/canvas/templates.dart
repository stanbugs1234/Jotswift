import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/catalog_item.dart';
import '../../core/catalog/catalog_providers.dart';
import '../../core/catalog/template_spec.dart';
import '../../core/paper/paper_style.dart';
import '../../core/pdf/pdf_renderer.dart';
import '../notebooks/data/notes_repository.dart';
import '../notebooks/domain/notebook_models.dart';
import '../notebooks/notes_providers.dart';

/// Which template PDF (an exact version of one item).
typedef TemplateFileKey = ({
  String itemId,
  int version,
  String pack,
  String sha256,
  int bytes,
  String file,
});

extension PageTemplateFile on PageTemplate {
  TemplateFileKey get fileKey => (
    itemId: itemId,
    version: version,
    pack: pack,
    sha256: sha256,
    bytes: bytes,
    file: file,
  );
}

/// A reference to [pdfPage] of [item]'s current version, for a new page.
/// [file] picks a colourway's PDF.
PageTemplate templatePage(
  CatalogItem item,
  int pdfPage, {
  String file = PageTemplate.defaultFile,
}) => PageTemplate(
  itemId: item.id,
  version: item.version,
  pdfPage: pdfPage,
  pack: item.files!.pack,
  sha256: item.files!.sha256,
  bytes: item.files!.bytes,
  file: file,
);

/// The listing of a template version, rebuilt from what a page saved, so
/// older versions can still be downloaded.
CatalogItem _itemFor(TemplateFileKey key) => CatalogItem(
  id: key.itemId,
  kind: CatalogKind.template,
  name: key.itemId,
  version: key.version,
  unlock: const CatalogUnlock(),
  visibility: CatalogVisibility.retired,
  files: CatalogFiles(pack: key.pack, sha256: key.sha256, bytes: key.bytes),
);

/// A template's opened PDF, downloaded on first use.
final templatePdfProvider = FutureProvider.family<PdfFile, TemplateFileKey>((
  ref,
  key,
) async {
  final files = await ref.watch(packCacheProvider).files(_itemFor(key));
  final pdf = files[key.file];
  if (pdf == null) throw StateError('${key.itemId} has no ${key.file}');
  return ref
      .watch(pdfRendererProvider)
      .open(
        pdf,
        name: key.file == PageTemplate.defaultFile
            ? '${key.itemId}@${key.version}'
            : '${key.itemId}@${key.version}/${key.file}',
      );
});

/// A template's `template.json`: its mode and its pages with titles.
final templateSpecProvider = FutureProvider.family<TemplateSpec, CatalogItem>((
  ref,
  item,
) async {
  final files = await ref.watch(packCacheProvider).files(item);
  final json = files['template.json'];
  if (json == null) throw StateError('${item.id} has no template.json');
  return TemplateSpec.fromJson(json);
});

/// A template's opened PDF, for its current version.
final catalogTemplatePdfProvider = FutureProvider.family<PdfFile, CatalogItem>(
  (ref, item) =>
      ref.watch(templatePdfProvider(templatePage(item, 1).fileKey).future),
);

/// One template page drawn [width] pixels wide. Freed when no longer shown.
final templateImageProvider = FutureProvider.autoDispose
    .family<ui.Image, ({PageTemplate template, int width})>((ref, key) async {
      final pdf = await ref.watch(
        templatePdfProvider(key.template.fileKey).future,
      );
      return pdf.render(key.template.pdfPage, width: key.width);
    });

/// The links on a template page.
final templateLinksProvider = FutureProvider.autoDispose
    .family<List<PdfPageLink>, PageTemplate>((ref, template) async {
      final pdf = await ref.watch(templatePdfProvider(template.fileKey).future);
      return pdf.links(template.pdfPage);
    });

/// A notebook's pages by the template page they show, to follow links:
/// (template id, PDF page) to page id.
final notebookTemplatePagesProvider =
    StreamProvider.family<Map<(String, int), String>, String>(
      (ref, notebookId) => ref
          .watch(notebookRepositoryProvider)
          .watchNotebookPages(notebookId)
          .map(
            (pages) => {
              for (final p in pages)
                if (p.template case final t?) (t.itemId, t.pdfPage): p.id,
            },
          ),
    );

/// The page size closest to a PDF page's shape (PDF points).
(PaperSize, PaperOrientation) closestPaperSize(ui.Size pdfPage) {
  final landscape = pdfPage.width > pdfPage.height;
  final orientation = landscape
      ? PaperOrientation.landscape
      : PaperOrientation.portrait;
  final ratio = pdfPage.width / pdfPage.height;
  final size = PaperSize.values.reduce((a, b) {
    double diff(PaperSize s) {
      final d = s.dimensions(orientation);
      return (d.width / d.height - ratio).abs();
    }

    return diff(a) <= diff(b) ? a : b;
  });
  return (size, orientation);
}

/// Makes [notebook] with every page of the planner [item], in the planner's
/// sections. Returns the new notebook.
Future<Notebook> createNotebookFromTemplate(
  Ref ref,
  NewNotebook notebook,
  CatalogItem item, {
  String file = PageTemplate.defaultFile,
}) async {
  final spec = await ref.read(templateSpecProvider(item).future);
  final repo = ref.read(notebookRepositoryProvider);
  final created = await repo.createNotebook(notebook);
  final first = (await repo.watchSections(created.id).first).first;
  for (final (i, section) in spec.sections.indexed) {
    final sectionId = i == 0
        ? first.id
        : (await repo.createSection(created.id, section.title)).id;
    if (i == 0) await repo.renameSection(created.id, sectionId, section.title);
    await repo.createPages(created.id, sectionId, [
      for (final p in section.pages)
        (
          title: p.title,
          paper: null,
          template: templatePage(item, p.pdfPage, file: file),
        ),
    ]);
  }
  return created;
}

/// What [createNotebookFromTemplate] needs, so widgets can call it.
final createFromTemplateProvider =
    Provider<
      Future<Notebook> Function(NewNotebook, CatalogItem, {String file})
    >(
      (ref) =>
          (notebook, item, {file = PageTemplate.defaultFile}) =>
              createNotebookFromTemplate(ref, notebook, item, file: file),
    );

/// The pages a NewPage list gets from a single-page template.
NewPage templateNewPage(CatalogItem item, TemplatePage page) => (
  title: page.title,
  paper: null,
  template: templatePage(item, page.pdfPage),
);

/// Asks which single template page to add. Returns null if cancelled.
Future<NewPage?> showTemplatePageSheet(BuildContext context) =>
    showModalBottomSheet<NewPage>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _TemplatePageSheet(),
    );

class _TemplatePageSheet extends ConsumerWidget {
  const _TemplatePageSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final templates = [
      for (final t in ref.watch(offeredCatalogProvider(CatalogKind.template)))
        if (t.templateMode == TemplateMode.pages) t,
    ];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: templates.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No page templates yet. Check your connection; free '
                    'templates appear here.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Text(
                    'New page from template',
                    style: theme.textTheme.titleLarge,
                  ),
                  for (final item in templates) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 8),
                      child: Text(item.name, style: theme.textTheme.titleSmall),
                    ),
                    switch (ref.watch(templateSpecProvider(item))) {
                      AsyncData(value: final spec) => Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final page in spec.pages)
                            _TemplatePageTile(item: item, page: page),
                        ],
                      ),
                      AsyncError() => const Text(
                        'Could not download these templates. Check your '
                        'connection.',
                      ),
                      _ => const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    },
                  ],
                ],
              ),
      ),
    );
  }
}

class _TemplatePageTile extends ConsumerWidget {
  const _TemplatePageTile({required this.item, required this.page});

  final CatalogItem item;
  final TemplatePage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final image = ref
        .watch(
          templateImageProvider((
            template: templatePage(item, page.pdfPage),
            width: 240,
          )),
        )
        .value;
    return Semantics(
      button: true,
      label: '${page.title} template',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => Navigator.pop(context, templateNewPage(item, page)),
        child: SizedBox(
          width: 110,
          child: Column(
            children: [
              Container(
                height: 140,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: theme.colorScheme.outline),
                ),
                child: image == null
                    ? const Center(child: CircularProgressIndicator())
                    : RawImage(image: image, fit: BoxFit.contain),
              ),
              const SizedBox(height: 4),
              Text(
                page.title,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
