import 'package:flutter/foundation.dart';

/// A page drawn from a page of a catalog template's PDF, or of a PDF the
/// user imported.
///
/// It keeps the exact version (and its pack) the page was made with, so a
/// later version of the template never shifts writing on a filled page.
/// Imported PDFs are kept the same way, as one-file packs in the user's
/// own storage (see [importPrefix]).
@immutable
class PageTemplate {
  const PageTemplate({
    required this.itemId,
    required this.version,
    required this.pdfPage,
    required this.pack,
    required this.sha256,
    required this.bytes,
    this.file = defaultFile,
  });

  /// The PDF in the pack most templates have; colourways add others.
  static const defaultFile = 'template.pdf';

  /// Imported documents have ids starting with this, and keep their PDF as
  /// [importFile].
  static const importPrefix = 'import-';
  static const importFile = 'document.pdf';

  static PageTemplate? fromMap(Object? map) {
    if (map is! Map) return null;
    final itemId = map['itemId'], version = map['version'];
    final pdfPage = map['pdfPage'], pack = map['pack'];
    final sha256 = map['sha256'], bytes = map['bytes'];
    if (itemId is! String ||
        version is! int ||
        pdfPage is! int ||
        pack is! String ||
        sha256 is! String ||
        bytes is! int) {
      return null;
    }
    return PageTemplate(
      itemId: itemId,
      version: version,
      pdfPage: pdfPage,
      pack: pack,
      sha256: sha256,
      bytes: bytes,
      file: map['file'] as String? ?? defaultFile,
    );
  }

  final String itemId;
  final int version;

  /// The PDF page drawn (1 = the first).
  final int pdfPage;

  /// The template's pack at [version], to download it again if needed.
  final String pack;
  final String sha256;
  final int bytes;

  /// Which PDF in the pack: a colourway's, or [defaultFile].
  final String file;

  /// From a PDF or images the user imported, not the catalog.
  bool get isImported => itemId.startsWith(importPrefix);

  Map<String, Object?> toMap() => {
    'itemId': itemId,
    'version': version,
    'pdfPage': pdfPage,
    'pack': pack,
    'sha256': sha256,
    'bytes': bytes,
    if (file != defaultFile) 'file': file,
  };

  @override
  bool operator ==(Object other) =>
      other is PageTemplate &&
      other.itemId == itemId &&
      other.version == version &&
      other.pdfPage == pdfPage &&
      other.file == file;

  @override
  int get hashCode => Object.hash(itemId, version, pdfPage, file);
}
