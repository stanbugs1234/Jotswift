import 'dart:math';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/catalog/catalog_item.dart';
import '../../core/catalog/catalog_providers.dart';
import '../../core/catalog/pack_cache.dart';
import '../../core/pdf/pdf_renderer.dart';
import '../notebooks/data/notes_repository.dart';
import '../notebooks/domain/notebook_models.dart';
import '../notebooks/notes_providers.dart';

/// A file chosen to import: a PDF, or a JPEG or PNG image.
@immutable
class ImportFile {
  const ImportFile(this.name, this.bytes);

  /// The file's name, with its extension.
  final String name;
  final Uint8List bytes;

  bool get isPdf =>
      name.toLowerCase().endsWith('.pdf') ||
      (bytes.length > 4 &&
          bytes[0] == 0x25 && // %PDF
          bytes[1] == 0x50 &&
          bytes[2] == 0x44 &&
          bytes[3] == 0x46);

  /// The name without its extension, to title a notebook.
  String get title {
    final dot = name.lastIndexOf('.');
    return (dot > 0 ? name.substring(0, dot) : name).trim();
  }
}

/// Why an import didn't work, in words for the user.
class ImportException implements Exception {
  ImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Where imported documents are kept: a one-file pack (a zip holding
/// `document.pdf`), at `users/{uid}/documents/{id}.zip` in Cloud Storage
/// (see firebase/storage.rules). Other devices download it like a template
/// pack.
abstract interface class DocumentStore {
  /// Saves [zip] for [uid] and returns its path.
  Future<String> upload(String uid, String id, Uint8List zip);
}

class FirebaseDocumentStore implements DocumentStore {
  FirebaseDocumentStore(this._storage);

  final FirebaseStorage _storage;

  @override
  Future<String> upload(String uid, String id, Uint8List zip) async {
    final path = 'users/$uid/documents/$id.zip';
    await _storage
        .ref(path)
        .putData(zip, SettableMetadata(contentType: 'application/zip'));
    return path;
  }
}

/// Keeps documents in memory. Used in tests and without Firebase.
class InMemoryDocumentStore implements DocumentStore {
  final documents = <String, Uint8List>{};

  @override
  Future<String> upload(String uid, String id, Uint8List zip) async {
    final path = 'users/$uid/documents/$id.zip';
    documents[path] = zip;
    return path;
  }
}

/// Overridden in `main()` with Cloud Storage when Firebase is set up.
final documentStoreProvider = Provider<DocumentStore>(
  (ref) => InMemoryDocumentStore(),
);

/// Lets the user choose PDFs and images from Files. Returns null if they
/// cancel. Replaced in tests.
final importFilesPickerProvider =
    Provider<Future<List<ImportFile>?> Function()>(
      (ref) => () async {
        final files = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
        );
        if (files.isEmpty) return null;
        return [
          for (final f in files) ImportFile(f.name, await f.readAsBytes()),
        ];
      },
    );

/// Lets the user choose photos. Returns null if they cancel. Replaced in
/// tests.
final importPhotosPickerProvider =
    Provider<Future<List<ImportFile>?> Function()>(
      (ref) => () async {
        final photos = await ImagePicker().pickMultiImage(
          maxWidth: 2400,
          maxHeight: 2400,
          imageQuality: 85,
        );
        if (photos.isEmpty) return null;
        return [
          for (final p in photos) ImportFile(p.name, await p.readAsBytes()),
        ];
      },
    );

/// A PDF with one page per image, each as wide as a Letter page and as
/// tall as the image's shape needs. Throws [ImportException] for a file
/// that isn't a JPEG or PNG.
Future<Uint8List> imagesToPdf(List<ImportFile> images) {
  final doc = pw.Document(title: images.first.title);
  for (final file in images) {
    final pw.MemoryImage image;
    final double width, height;
    try {
      image = pw.MemoryImage(file.bytes);
      width = (image.width ?? 0).toDouble();
      height = (image.height ?? 0).toDouble();
      if (width <= 0 || height <= 0) throw const FormatException();
    } catch (_) {
      throw ImportException(
        '${file.name} could not be read. Choose a JPEG or PNG image.',
      );
    }
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(612, 612 * height / width),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
      ),
    );
  }
  return doc.save();
}

/// One imported document, kept and ready to make pages from.
@immutable
class ImportedDocument {
  const ImportedDocument({
    required this.title,
    required this.pages,
    required this.firstPageSize,
  });

  /// From the file's name.
  final String title;

  /// A template for each of its pages, in order.
  final List<PageTemplate> pages;

  /// In PDF points, to choose the notebook's page size.
  final ui.Size firstPageSize;
}

/// Turns chosen files into kept documents: each PDF on its own, and each
/// run of images together as one PDF.
class DocumentImporter {
  DocumentImporter({
    required this.uid,
    required this.store,
    required this.packs,
    required this.renderer,
  });

  final String uid;
  final DocumentStore store;
  final PackCache packs;
  final PdfRenderer renderer;
  final _random = Random();

  Future<List<ImportedDocument>> import(List<ImportFile> files) async {
    final documents = <ImportedDocument>[];
    var images = <ImportFile>[];
    Future<void> flushImages() async {
      if (images.isEmpty) return;
      final run = images;
      images = [];
      documents.add(
        await _keep(
          run.length == 1 ? run.first.title : 'Imported images',
          await imagesToPdf(run),
        ),
      );
    }

    for (final file in files) {
      if (file.isPdf) {
        await flushImages();
        documents.add(await _keep(file.title, file.bytes));
      } else {
        images.add(file);
      }
    }
    await flushImages();
    return documents;
  }

  /// Checks [pdf] opens, then saves it and keeps it on this device.
  Future<ImportedDocument> _keep(String title, Uint8List pdf) async {
    if (pdf.length > PackCache.maxImportBytes) {
      throw ImportException(
        '"$title" is too large to import (the limit is '
        '${PackCache.maxImportBytes ~/ (1024 * 1024)} MB).',
      );
    }
    final PdfFile opened;
    try {
      opened = await renderer.open(pdf, name: title);
    } catch (_) {
      throw ImportException(
        '"$title" could not be opened. It may be damaged or protected with '
        'a password.',
      );
    }
    final int pageCount;
    final ui.Size firstPageSize;
    try {
      pageCount = opened.pageCount;
      if (pageCount == 0) throw ImportException('"$title" has no pages.');
      firstPageSize = opened.pageSize(1);
    } finally {
      await opened.dispose();
    }

    final id =
        '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
        '${_random.nextInt(1 << 30).toRadixString(36)}';
    final files = {PageTemplate.importFile: pdf};
    final zip = Uint8List.fromList(
      ZipEncoder().encode(
        Archive()..add(ArchiveFile.bytes(PageTemplate.importFile, pdf)),
      ),
    );
    final path = await store.upload(uid, id, zip);
    final itemId = '${PageTemplate.importPrefix}$id';
    final hash = sha256.convert(zip).toString();
    await packs.put(
      CatalogItem(
        id: itemId,
        kind: CatalogKind.template,
        name: title,
        version: 1,
        unlock: const CatalogUnlock(),
        visibility: CatalogVisibility.retired,
        files: CatalogFiles(pack: path, sha256: hash, bytes: zip.length),
      ),
      files,
    );
    return ImportedDocument(
      title: title,
      firstPageSize: firstPageSize,
      pages: [
        for (var i = 1; i <= pageCount; i++)
          PageTemplate(
            itemId: itemId,
            version: 1,
            pdfPage: i,
            pack: path,
            sha256: hash,
            bytes: zip.length,
            file: PageTemplate.importFile,
          ),
      ],
    );
  }
}

final documentImporterProvider = Provider<DocumentImporter>(
  (ref) => DocumentImporter(
    uid: ref.watch(currentUidProvider),
    store: ref.watch(documentStoreProvider),
    packs: ref.watch(packCacheProvider),
    renderer: ref.watch(pdfRendererProvider),
  ),
);

/// The pages [documents] become, titled "Page 1", "Page 2"... within each
/// document (or by the document's name when it has one page).
List<NewPage> importedPages(List<ImportedDocument> documents) => [
  for (final doc in documents)
    for (final (i, template) in doc.pages.indexed)
      (
        title: doc.pages.length == 1 ? doc.title : 'Page ${i + 1}',
        paper: null,
        template: template,
      ),
];
