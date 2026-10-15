import 'package:flutter/material.dart';

import '../notebooks/domain/notebook_models.dart';

/// The front of a notebook, drawn as a book with a spine.
///
/// Art and photo covers show their color until their images arrive with the
/// new-notebook screen (milestone 4 in docs/noteshelf-implementation.md).
class CoverView extends StatelessWidget {
  const CoverView({required this.cover, this.elevation = 2, super.key});

  final NotebookCover cover;
  final double elevation;

  /// Width / height of every cover.
  static const aspectRatio = 0.72;

  @override
  Widget build(BuildContext context) {
    final color = Color(cover.color);
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
