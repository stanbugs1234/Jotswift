import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/catalog_providers.dart';
import '../notebooks/data/cover_photos.dart';
import '../notebooks/domain/notebook_models.dart';
import 'cover_designs.dart';

/// The front of a notebook, drawn as a book with a spine.
///
/// Design covers are drawn in code (see [CoverDesign]). Photo and catalog
/// covers show their color until the image has loaded (catalog covers are
/// downloaded once, then kept). Covers this version can't draw show their
/// color.
class CoverView extends ConsumerWidget {
  const CoverView({
    required this.cover,
    this.elevation = 2,
    this.title,
    super.key,
  });

  final NotebookCover cover;
  final double elevation;

  /// The notebook's name, printed on a label on the front, as on a paper
  /// notebook. Left off when the cover is too small to read it.
  final String? title;

  /// Width / height of every cover.
  static const aspectRatio = 0.72;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = Color(cover.color);
    final design = CoverDesign.byId(cover.coverId);
    final image = switch (cover) {
      NotebookCover(kind: CoverKind.photo, :final photoPath?) =>
        ref.watch(coverPhotoProvider(photoPath)).value,
      NotebookCover(kind: CoverKind.art, :final coverId?) when design == null =>
        ref.watch(catalogCoverProvider(coverId)).value,
      _ => null,
    };
    final spine = ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Material(
        color: color,
        elevation: elevation,
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(3),
          right: Radius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            if (image != null)
              Positioned.fill(
                child: Image(image: image, fit: BoxFit.cover),
              ),
            if (design != null && cover.kind == CoverKind.art)
              Positioned.fill(
                child: CustomPaint(painter: CoverDesignPainter(design, color)),
              ),
            // Shading along the spine, then the binding line.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 18,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.22),
                      Colors.black.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 10,
              top: 0,
              bottom: 0,
              width: 2,
              child: ColoredBox(color: spine.withValues(alpha: 0.22)),
            ),
            if (title case final title? when title.trim().isNotEmpty)
              Positioned.fill(child: _CoverLabel(title: title.trim())),
          ],
        ),
      ),
    );
  }
}

/// A notebook's name on a cream label a third of the way down its cover.
/// Painted, not a [Text]: the tile under the cover already names the
/// notebook for screen readers.
class _CoverLabel extends StatelessWidget {
  const _CoverLabel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // Too small to read (list rows, stacked groups).
      if (box.maxWidth < 72) return const SizedBox.shrink();
      return CustomPaint(painter: _LabelPainter(title));
    },
  );
}

class _LabelPainter extends CustomPainter {
  _LabelPainter(this.title);

  final String title;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final labelWidth = width * 0.68;
    final pad = width * 0.05;
    final text = TextPainter(
      text: TextSpan(
        text: title,
        style: TextStyle(
          color: const Color(0xFF2A2A2A),
          fontSize: (width * 0.085).clamp(9, 18),
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: labelWidth - pad * 2);
    final height = text.height + width * 0.08;
    // A little right of center, clear of the spine.
    final rect = Rect.fromCenter(
      center: Offset(width * 0.54, size.height * 0.3),
      width: labelWidth,
      height: height,
    );
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(width * 0.025));
    canvas
      ..drawRRect(
        shape.shift(const Offset(0, 1)),
        Paint()
          ..color = Colors.black26
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      )
      ..drawRRect(shape, Paint()..color = const Color(0xFFFBF8F1));
    text.paint(
      canvas,
      Offset(
        rect.left + (labelWidth - text.width) / 2,
        rect.top + (height - text.height) / 2,
      ),
    );
    text.dispose();
  }

  @override
  bool shouldRepaint(_LabelPainter old) => old.title != title;
}

/// A group: up to three of its covers, fanned out like a stack of books.
class GroupStackView extends StatelessWidget {
  const GroupStackView({required this.covers, super.key});

  /// The first few covers in the group (may be empty).
  final List<NotebookCover> covers;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = covers.take(3).toList().reversed.toList();

    return AspectRatio(
      aspectRatio: CoverView.aspectRatio,
      child: LayoutBuilder(
        builder: (context, box) {
          final step = box.maxWidth * 0.07;
          final width = box.maxWidth - step * 2;
          if (shown.isEmpty) {
            return Center(
              child: SizedBox(
                width: width,
                child: AspectRatio(
                  aspectRatio: CoverView.aspectRatio,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: scheme.outline),
                    ),
                    child: Icon(Icons.folder_outlined, color: scheme.outline),
                  ),
                ),
              ),
            );
          }
          return Stack(
            children: [
              for (var i = 0; i < shown.length; i++)
                Positioned(
                  // The front cover sits lowest and furthest left.
                  left: step * (shown.length - 1 - i),
                  top: step * i,
                  width: width,
                  child: CoverView(cover: shown[i], elevation: 1.5),
                ),
            ],
          );
        },
      ),
    );
  }
}
