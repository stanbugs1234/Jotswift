import 'package:flutter/foundation.dart';

enum CoverKind {
  /// A plain color.
  color,

  /// A designed cover from a collection or the catalog.
  art,

  /// The user's own photo.
  photo,
}

/// The front of a notebook.
///
/// Every cover has a [color]: for art and photo covers it is shown while the
/// image loads, and by older app versions that only know colors.
@immutable
class NotebookCover {
  const NotebookCover.color(this.color)
    : kind = CoverKind.color,
      coverId = null,
      photoPath = null;

  const NotebookCover.art(this.coverId, {required this.color})
    : kind = CoverKind.art,
      photoPath = null;

  const NotebookCover.photo(this.photoPath, {required this.color})
    : kind = CoverKind.photo,
      coverId = null;

  /// Reads a saved cover. Notebooks saved before covers existed only have a
  /// `color` field, which [fallbackColor] carries. An art or photo cover
  /// missing its image becomes a color cover.
  factory NotebookCover.fromMap(Object? map, {required int fallbackColor}) {
    if (map is! Map) return NotebookCover.color(fallbackColor);
    final color = map['color'] is int ? map['color'] as int : fallbackColor;
    final coverId = map['coverId'];
    final photoPath = map['photoPath'];
    return switch (map['kind']) {
      'art' when coverId is String => NotebookCover.art(coverId, color: color),
      'photo' when photoPath is String => NotebookCover.photo(
        photoPath,
        color: color,
      ),
      _ => NotebookCover.color(color),
    };
  }

  final CoverKind kind;

  /// ARGB.
  final int color;

  /// The catalog id of an art cover.
  final String? coverId;

  /// Where a photo cover is stored, in the user's Cloud Storage folder.
  final String? photoPath;

  Map<String, Object?> toMap() => {
    'kind': kind.name,
    'color': color,
    'coverId': ?coverId,
    'photoPath': ?photoPath,
  };

  @override
  bool operator ==(Object other) =>
      other is NotebookCover &&
      other.kind == kind &&
      other.color == color &&
      other.coverId == coverId &&
      other.photoPath == photoPath;

  @override
  int get hashCode => Object.hash(kind, color, coverId, photoPath);
}
