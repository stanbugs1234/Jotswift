import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notebooks/data/cover_photos.dart';
import '../notebooks/domain/notebook_models.dart';
import 'cover_designs.dart';

/// The front of a notebook, drawn as a book with a spine.
///
/// Design covers are drawn in code (see [CoverDesign]); photo covers show
/// their color until the photo has loaded. Covers this version can't draw
/// show their color.
class CoverView extends ConsumerWidget {
  const CoverView({required this.cover, this.elevation = 2, super.key});

  final NotebookCover cover;
  final double elevation;

  /// Width / height of every cover.
  static const aspectRatio = 0.72;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = Color(cover.color);
    final photo = cover.photoPath == null
        ? null
        : ref.watch(coverPhotoProvider(cover.photoPath!)).value;
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
            if (photo != null)
              Positioned.fill(
                child: Image(image: photo, fit: BoxFit.cover),
              ),
            if (CoverDesign.byId(cover.coverId) case final design?
                when cover.kind == CoverKind.art)
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
          ],
        ),
      ),
    );
  }
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
