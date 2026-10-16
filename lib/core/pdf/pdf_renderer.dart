import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

/// A link on a PDF page to another page of the same PDF.
@immutable
class PdfPageLink {
  const PdfPageLink(this.area, this.targetPage);

  /// Where the link is, as fractions of the page (0-1, from the top left).
  final ui.Rect area;

  /// The page it goes to (1 = the first page).
  final int targetPage;
}

/// An open PDF. Pages are numbered from 1.
abstract interface class PdfFile {
  int get pageCount;

  /// The size of [page] in PDF points (72 per inch).
  ui.Size pageSize(int page);

  /// [page]'s links to other pages (links to web pages are left out).
  Future<List<PdfPageLink>> links(int page);

  /// Draws [page] [width] pixels wide (height follows its shape).
  Future<ui.Image> render(int page, {required int width});

  /// Frees the PDF; nothing may be asked of it afterwards.
  Future<void> dispose();
}

/// Opens PDFs. Behind an interface so tests don't need the PDF engine.
abstract interface class PdfRenderer {
  Future<PdfFile> open(Uint8List bytes, {required String name});
}

/// PDFium through pdfrx, on iOS, Android, desktop and the web.
class PdfrxRenderer implements PdfRenderer {
  @override
  Future<PdfFile> open(Uint8List bytes, {required String name}) async {
    await pdfrxFlutterInitialize();
    return _PdfrxFile(await PdfDocument.openData(bytes, sourceName: name));
  }
}

class _PdfrxFile implements PdfFile {
  _PdfrxFile(this._doc);

  final PdfDocument _doc;

  PdfPage _page(int number) => _doc.pages[number - 1];

  @override
  int get pageCount => _doc.pages.length;

  @override
  ui.Size pageSize(int page) => ui.Size(_page(page).width, _page(page).height);

  @override
  Future<List<PdfPageLink>> links(int page) async {
    final p = _page(page);
    final links = await p.loadLinks(enableAutoLinkDetection: false);
    return [
      for (final link in links)
        if (link.dest case final dest?)
          for (final r in link.rects)
            PdfPageLink(
              // PDF coordinates start at the bottom left.
              ui.Rect.fromLTRB(
                r.left / p.width,
                1 - r.top / p.height,
                r.right / p.width,
                1 - r.bottom / p.height,
              ),
              dest.pageNumber,
            ),
    ];
  }

  @override
  Future<ui.Image> render(int page, {required int width}) async {
    final p = _page(page);
    final height = (width * p.height / p.width).round();
    final image = await p.render(
      fullWidth: width.toDouble(),
      fullHeight: height.toDouble(),
    );
    if (image == null) throw StateError('Could not draw page $page');
    try {
      return await image.createImage();
    } finally {
      image.dispose();
    }
  }

  @override
  Future<void> dispose() => _doc.dispose();
}

final pdfRendererProvider = Provider<PdfRenderer>((ref) => PdfrxRenderer());
