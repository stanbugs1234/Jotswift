import 'package:flutter/foundation.dart';

import '../../../core/paper/paper_style.dart';
import 'notebook_cover.dart';

export 'notebook_cover.dart';

/// A notebook holds sections, and each section holds pages.
@immutable
class Notebook {
  const Notebook({
    required this.id,
    required this.title,
    required this.cover,
    required this.createdAt,
    required this.updatedAt,
    this.paper,
    this.paperSize = PaperSize.letter,
    this.orientation = PaperOrientation.portrait,
    this.collectionId,
  });

  factory Notebook.fromMap(String id, Map<String, dynamic> map) => Notebook(
    id: id,
    title: map['title'] as String? ?? 'Untitled notebook',
    cover: NotebookCover.fromMap(
      map['cover'],
      fallbackColor: map['color'] as int? ?? notebookColors.first,
    ),
    paper: PaperStyle.fromMap(map['paper']),
    paperSize: _enumByName(
      PaperSize.values,
      map['paperSize'],
      PaperSize.letter,
    ),
    orientation: _enumByName(
      PaperOrientation.values,
      map['orientation'],
      PaperOrientation.portrait,
    ),
    collectionId: map['collectionId'] as String?,
    createdAt: map['createdAt'] as int? ?? 0,
    updatedAt: map['updatedAt'] as int? ?? 0,
  );

  final String id;
  final String title;
  final NotebookCover cover;

  /// The paper new pages get. Null means the active skin's paper, which is
  /// how notebooks made before paper choices existed keep their look.
  final PaperStyle? paper;
  final PaperSize paperSize;
  final PaperOrientation orientation;

  /// The style (collection) the pages are drawn in. Null means the user's
  /// default style.
  final String? collectionId;

  /// Milliseconds since epoch.
  final int createdAt;
  final int updatedAt;

  Map<String, dynamic> toMap() => {
    'title': title,
    'cover': cover.toMap(),
    // Kept for app versions that only read the cover color.
    'color': cover.color,
    'paper': ?paper?.toMap(),
    'paperSize': paperSize.name,
    'orientation': orientation.name,
    'collectionId': ?collectionId,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  Notebook copyWith({
    String? title,
    NotebookCover? cover,
    PaperStyle? paper,
    String? collectionId,
    int? updatedAt,
  }) => Notebook(
    id: id,
    title: title ?? this.title,
    cover: cover ?? this.cover,
    paper: paper ?? this.paper,
    paperSize: paperSize,
    orientation: orientation,
    collectionId: collectionId ?? this.collectionId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// What to create a notebook with.
@immutable
class NewNotebook {
  const NewNotebook({
    required this.title,
    required this.cover,
    this.paper,
    this.paperSize = PaperSize.letter,
    this.orientation = PaperOrientation.portrait,
    this.collectionId,
  });

  final String title;
  final NotebookCover cover;
  final PaperStyle? paper;
  final PaperSize paperSize;
  final PaperOrientation orientation;
  final String? collectionId;

  Notebook build(String id, int now) => Notebook(
    id: id,
    title: title,
    cover: cover,
    paper: paper,
    paperSize: paperSize,
    orientation: orientation,
    collectionId: collectionId,
    createdAt: now,
    updatedAt: now,
  );
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.where((v) => v.name == name).firstOrNull ?? fallback;

/// Cover colors to choose from. They don't change with the skin, so a
/// notebook keeps its color everywhere.
const notebookColors = [
  0xFF2C4A7C, // navy
  0xFFC8553D, // brick
  0xFF2E7D5B, // green
  0xFF7B4FA0, // purple
  0xFFD4A017, // mustard
  0xFF1F8A99, // teal
  0xFFB5658F, // rose
  0xFF5B5B5B, // graphite
];

@immutable
class Section {
  const Section({
    required this.id,
    required this.notebookId,
    required this.title,
    required this.order,
  });

  factory Section.fromMap(
    String id,
    String notebookId,
    Map<String, dynamic> map,
  ) => Section(
    id: id,
    notebookId: notebookId,
    title: map['title'] as String? ?? 'Untitled section',
    order: (map['order'] as num?)?.toDouble() ?? 0,
  );

  final String id;
  final String notebookId;
  final String title;

  /// Sort key. A double so items can be moved between two others later.
  final double order;

  Map<String, dynamic> toMap() => {'title': title, 'order': order};
}

@immutable
class NotePage {
  const NotePage({
    required this.id,
    required this.notebookId,
    required this.sectionId,
    required this.title,
    required this.order,
    required this.createdAt,
    required this.updatedAt,
    this.paper,
  });

  factory NotePage.fromMap(String id, Map<String, dynamic> map) => NotePage(
    id: id,
    notebookId: map['notebookId'] as String,
    sectionId: map['sectionId'] as String,
    title: map['title'] as String? ?? '',
    order: (map['order'] as num?)?.toDouble() ?? 0,
    createdAt: map['createdAt'] as int? ?? 0,
    updatedAt: map['updatedAt'] as int? ?? 0,
    paper: PaperStyle.fromMap(map['paper']),
  );

  final String id;
  final String notebookId;
  final String sectionId;

  /// May be empty; shown as "Untitled page".
  final String title;
  final double order;
  final int createdAt;
  final int updatedAt;

  /// This page's paper when it differs from its notebook's.
  final PaperStyle? paper;

  String get displayTitle => title.trim().isEmpty ? 'Untitled page' : title;

  Map<String, dynamic> toMap() => {
    'notebookId': notebookId,
    'sectionId': sectionId,
    'title': title,
    'order': order,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'paper': ?paper?.toMap(),
  };

  NotePage copyWith({
    String? title,
    PaperStyle? Function()? paper,
    int? updatedAt,
  }) => NotePage(
    id: id,
    notebookId: notebookId,
    sectionId: sectionId,
    title: title ?? this.title,
    order: order,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    paper: paper == null ? this.paper : paper(),
  );
}
