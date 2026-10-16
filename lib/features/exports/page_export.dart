import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../canvas/domain/page_element.dart';
import '../canvas/page_canvas.dart';
import '../canvas/templates.dart';
import '../notebooks/notes_providers.dart';

/// PDF points per page unit: a Letter page (1404 units) is 612 points.
const pointsPerUnit = 612 / 1404;

/// Pixels per page unit when exporting: about 240 dots per inch, sharp
/// enough to print.
const exportPixelRatio = 1.5;

/// Draws pages as images, off screen, with the theme and data of the
/// [context] it's made from.
class PageRenderer {
  PageRenderer(BuildContext context)
    : _view = View.of(context),
      _container = ProviderScope.containerOf(context),
      _wrap = ((child) => InheritedTheme.captureAll(context, child));

  final ui.FlutterView _view;
  final ProviderContainer _container;
  final Widget Function(Widget) _wrap;

  /// [pageId] drawn [pixelRatio] pixels per page unit.
  Future<ui.Image> render(
    String pageId, {
    double pixelRatio = exportPixelRatio,
  }) async {
    // Load what the page shows first, and keep it loaded while drawing.
    final subscriptions = [
      _container.listen(pageProvider(pageId), (_, _) {}),
      _container.listen(strokesProvider(pageId), (_, _) {}),
      _container.listen(elementsProvider(pageId), (_, _) {}),
    ];
    try {
      final page = await _container.read(pageProvider(pageId).future);
      if (page != null) {
        subscriptions.add(
          _container.listen(notebookProvider(page.notebookId), (_, _) {}),
        );
        await _container.read(notebookProvider(page.notebookId).future);
      }
      if (page?.template case final template?) {
        final key = (template: template, width: templateDrawWidth);
        subscriptions.add(
          _container.listen(templateImageProvider(key), (_, _) {}),
        );
        await _container.read(templateImageProvider(key).future);
      }
      await _container.read(strokesProvider(pageId).future);
      final elements = await _container.read(elementsProvider(pageId).future);
      final size = _container.read(pageDimensionsProvider(pageId));
      // Photos and stickers load as they're drawn; give them a moment.
      final hasPictures = elements.any(
        (e) => !e.deleted && e.content is! TextContent,
      );
      return await renderOffscreen(
        view: _view,
        size: size,
        pixelRatio: pixelRatio,
        frames: hasPictures ? 12 : 2,
        child: UncontrolledProviderScope(
          container: _container,
          child: _wrap(
            MediaQuery(
              data: MediaQueryData(size: size),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: PagePrint(pageId: pageId),
              ),
            ),
          ),
        ),
      );
    } finally {
      for (final s in subscriptions) {
        s.close();
      }
    }
  }
}

/// Builds [child] in a tree of its own, [size] logical pixels, and draws it
/// [pixelRatio] times larger. Lays it out [frames] times, a little apart,
/// so images that load meanwhile are drawn.
Future<ui.Image> renderOffscreen({
  required ui.FlutterView view,
  required Widget child,
  required Size size,
  double pixelRatio = 1,
  int frames = 2,
}) async {
  final boundary = RenderRepaintBoundary();
  final renderView = RenderView(
    view: view,
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(size),
      physicalConstraints: BoxConstraints.tight(size),
      devicePixelRatio: 1,
    ),
    child: RenderPositionedBox(child: boundary),
  );
  final pipeline = PipelineOwner()..rootNode = renderView;
  renderView.prepareInitialFrame();
  final focus = FocusManager();
  final owner = BuildOwner(focusManager: focus, onBuildScheduled: () {});
  final root = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: child,
  ).attachToRenderTree(owner);

  void frame() {
    owner
      ..buildScope(root)
      ..finalizeTree();
    pipeline
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();
  }

  try {
    frame();
    for (var i = 1; i < frames; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      frame();
    }
    return await boundary.toImage(pixelRatio: pixelRatio);
  } finally {
    // Unmount the tree, so its widgets let go of their providers.
    RenderObjectToWidgetAdapter<RenderBox>(container: boundary)
        .attachToRenderTree(owner, root);
    owner.finalizeTree();
    focus.dispose();
  }
}

/// Pages drawn by [renderer] as one PDF, each page its own size.
/// [progress] hears how many pages are done.
Future<Uint8List> pagesToPdf(
  PageRenderer renderer,
  List<String> pageIds, {
  String? title,
  void Function(int done)? progress,
}) async {
  final doc = pw.Document(title: title, creator: 'Jotswift');
  for (final (i, id) in pageIds.indexed) {
    final image = await renderer.render(id);
    try {
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final picture = pw.RawImage(
        bytes: rgba!.buffer.asUint8List(),
        width: image.width,
        height: image.height,
      );
      final format = PdfPageFormat(
        image.width / exportPixelRatio * pointsPerUnit,
        image.height / exportPixelRatio * pointsPerUnit,
      );
      doc.addPage(
        pw.Page(
          pageFormat: format,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Image(picture, fit: pw.BoxFit.fill),
        ),
      );
    } finally {
      image.dispose();
    }
    progress?.call(i + 1);
  }
  return doc.save();
}

/// Each page drawn by [renderer] as a PNG.
Future<List<Uint8List>> pagesToPng(
  PageRenderer renderer,
  List<String> pageIds, {
  void Function(int done)? progress,
}) async {
  final out = <Uint8List>[];
  for (final (i, id) in pageIds.indexed) {
    final image = await renderer.render(id);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      out.add(png!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
    progress?.call(i + 1);
  }
  return out;
}

/// A file name made from [title]: letters, digits, spaces and dashes.
String exportFileName(String title, String extension) {
  final clean = title
      .replaceAll(RegExp(r'[^A-Za-z0-9 _\-]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
  return '${clean.isEmpty ? 'Jotswift' : clean}.$extension';
}
