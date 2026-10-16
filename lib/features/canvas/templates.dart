import 'dart:ui' as ui;

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

/// The pages of one PDF of a template (an exact version): template.json,
/// with the page list of that PDF's variant when it has its own.
final templateFileSpecProvider =
    FutureProvider.family<TemplateSpec, TemplateFileKey>((ref, key) async {
      final files = await ref.watch(packCacheProvider).files(_itemFor(key));
      final json = files['template.json'];
      if (json == null) throw StateError('${key.itemId} has no template.json');
      final spec = TemplateSpec.fromJson(json);
      final own = spec.variants
          .where((v) => v.file == key.file)
          .firstOrNull
          ?.spec;
      final ownJson = own == null ? null : files[own];
      return ownJson == null ? spec : spec.withSectionsFrom(ownJson);
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

/// Makes [notebook] with the pages of the planner [item] in the planner's
/// sections, from its PDF [file], leaving out the page groups in [skip]
/// (and sections left empty). Calls [onProgress] with pages made so far
/// and the total. Returns the new notebook.
Future<Notebook> createNotebookFromTemplate(
  Ref ref,
  NewNotebook notebook,
  CatalogItem item, {
  String file = PageTemplate.defaultFile,
  Set<String> skip = const {},
  void Function(int done, int total)? onProgress,
}) async {
  final created = await ref
      .read(notebookRepositoryProvider)
      .createNotebook(notebook);
  await addPlannerPages(
    ref,
    created.id,
    item,
    file: file,
    skip: skip,
    onProgress: onProgress,
  );
  return created;
}

/// Adds every page of the planner [item] to [notebookId], as the planner's
/// sections after the notebook's own (or in place of its only section if
/// that is empty, as in a new notebook). [file], [skip] and [onProgress]
/// as for [createNotebookFromTemplate]. Returns the first page added, or
/// null if none were.
Future<String?> addPlannerPages(
  Ref ref,
  String notebookId,
  CatalogItem item, {
  String file = PageTemplate.defaultFile,
  Set<String> skip = const {},
  void Function(int done, int total)? onProgress,
}) async {
  final spec = await ref.read(
    templateFileSpecProvider(templatePage(item, 1, file: file).fileKey).future,
  );
  final sections = [
    for (final s in spec.sections)
      (
        title: s.title,
        pages: [
          for (final p in s.pages)
            if (!skip.contains(p.group)) p,
        ],
      ),
  ].where((s) => s.pages.isNotEmpty).toList();
  final total = sections.fold(0, (n, s) => n + s.pages.length);
  final repo = ref.read(notebookRepositoryProvider);
  final existing = await repo.watchSections(notebookId).first;
  String? empty;
  if (existing.length == 1) {
    final pages = await repo.watchPages(notebookId, existing.single.id).first;
    if (pages.isEmpty) empty = existing.single.id;
  }
  var done = 0;
  String? firstSection;
  onProgress?.call(done, total);
  for (final (i, section) in sections.indexed) {
    final String sectionId;
    if (i == 0 && empty != null) {
      sectionId = empty;
      await repo.renameSection(notebookId, sectionId, section.title);
    } else {
      sectionId = (await repo.createSection(notebookId, section.title)).id;
    }
    firstSection ??= sectionId;
    await repo.createPages(
      notebookId,
      sectionId,
      [
        for (final p in section.pages)
          (
            title: p.title,
            paper: null,
            template: templatePage(item, p.pdfPage, file: file),
          ),
      ],
      periods: [for (final p in section.pages) p.period],
    );
    done += section.pages.length;
    onProgress?.call(done, total);
  }
  if (firstSection == null) return null;
  final pages = await repo.watchPages(notebookId, firstSection).first;
  return (pages.toList()..sort((a, b) => a.order.compareTo(b.order)))
      .firstOrNull
      ?.id;
}

/// [addPlannerPages], for widgets.
final addPlannerPagesProvider =
    Provider<
      Future<String?> Function(
        String notebookId,
        CatalogItem item, {
        String file,
        Set<String> skip,
        void Function(int done, int total)? onProgress,
      })
    >(
      (ref) =>
          (
            notebookId,
            item, {
            file = PageTemplate.defaultFile,
            skip = const {},
            onProgress,
          }) => addPlannerPages(
            ref,
            notebookId,
            item,
            file: file,
            skip: skip,
            onProgress: onProgress,
          ),
    );

/// What [createNotebookFromTemplate] needs, so widgets can call it.
final createFromTemplateProvider =
    Provider<
      Future<Notebook> Function(
        NewNotebook,
        CatalogItem, {
        String file,
        Set<String> skip,
        void Function(int done, int total)? onProgress,
      })
    >(
      (ref) =>
          (
            notebook,
            item, {
            file = PageTemplate.defaultFile,
            skip = const {},
            onProgress,
          }) => createNotebookFromTemplate(
            ref,
            notebook,
            item,
            file: file,
            skip: skip,
            onProgress: onProgress,
          ),
    );

/// The title of [template]'s page in its planner, if the planner lists it.
Future<String?> templatePageTitle(Ref ref, PageTemplate template) async {
  final spec = await ref.read(
    templateFileSpecProvider(template.fileKey).future,
  );
  return spec.pages
      .where((p) => p.pdfPage == template.pdfPage)
      .firstOrNull
      ?.title;
}

/// Adds the planner page [template] to [notebookId], where the planner
/// puts it: in its section (made if missing), after the planner pages
/// before it. For a page left out when the notebook was made, and then
/// linked to. Returns the new page's id, or null if the planner doesn't
/// list the page.
Future<String?> addTemplatePage(
  Ref ref,
  String notebookId,
  PageTemplate template,
) async {
  final spec = await ref.read(
    templateFileSpecProvider(template.fileKey).future,
  );
  final found = [
    for (final s in spec.sections)
      for (final p in s.pages)
        if (p.pdfPage == template.pdfPage) (section: s.title, page: p),
  ].firstOrNull;
  if (found == null) return null;
  final repo = ref.read(notebookRepositoryProvider);
  final sections = await repo.watchSections(notebookId).first;
  // Its section by name; or, if renamed, the section of the planner page
  // before it; or a new one.
  final earlier = [
    for (final p in await repo.watchNotebookPages(notebookId).first)
      if (p.template case final t?
          when t.itemId == template.itemId && t.pdfPage < template.pdfPage)
        p,
  ]..sort((a, b) => a.template!.pdfPage.compareTo(b.template!.pdfPage));
  final sectionId =
      sections.where((s) => s.title == found.section).firstOrNull?.id ??
      earlier.lastOrNull?.sectionId ??
      (await repo.createSection(notebookId, found.section)).id;
  await repo.createPages(
    notebookId,
    sectionId,
    [(title: found.page.title, paper: null, template: template)],
    periods: [found.page.period],
  );
  bool isNew(NotePage p) =>
      p.template?.itemId == template.itemId &&
      p.template?.pdfPage == template.pdfPage;
  final pages = await repo
      .watchPages(notebookId, sectionId)
      .firstWhere((pages) => pages.any(isNew));
  final created = pages.firstWhere(isNew);
  final others = [
    for (final p in pages)
      if (p.id != created.id) p,
  ]..sort((a, b) => a.order.compareTo(b.order));
  // After the last page of this planner that comes before it.
  final before = others.lastIndexWhere(
    (p) =>
        p.template?.itemId == template.itemId &&
        p.template!.pdfPage < template.pdfPage,
  );
  final double? order;
  if (before == -1) {
    order = others.isEmpty ? null : others.first.order - 1;
  } else if (before + 1 < others.length) {
    order = (others[before].order + others[before + 1].order) / 2;
  } else {
    order = null; // Already last.
  }
  if (order != null) {
    await repo.movePage(
      created.id,
      notebookId: notebookId,
      sectionId: sectionId,
      order: order,
    );
  }
  return created.id;
}

/// [addTemplatePage], for widgets.
final addTemplatePageProvider =
    Provider<Future<String?> Function(String notebookId, PageTemplate)>(
      (ref) =>
          (notebookId, template) => addTemplatePage(ref, notebookId, template),
    );

/// [templatePageTitle], for widgets.
final templatePageTitleProvider =
    Provider<Future<String?> Function(PageTemplate)>(
      (ref) =>
          (template) => templatePageTitle(ref, template),
    );

/// The pages a NewPage list gets from a single-page template.
NewPage templateNewPage(CatalogItem item, TemplatePage page) => (
  title: page.title,
  paper: null,
  template: templatePage(item, page.pdfPage),
);
