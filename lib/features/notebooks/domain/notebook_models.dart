import 'package:flutter/foundation.dart';

import '../../../core/paper/paper_style.dart';
import 'notebook_cover.dart';
import 'page_period.dart';
import 'page_template.dart';
import 'shelf_models.dart';

export 'notebook_cover.dart';
export 'page_period.dart';
export 'page_template.dart';
export 'shelf_models.dart';

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
    this.categoryId,
    this.groupId,
    this.order,
    this.lastOpenedAt,
    this.lastPageId,
    this.lastPageTitle,
    this.lastPageAt,
    this.starred = false,
    this.trashedAt,
    this.isTemplate = false,
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
    categoryId: map['categoryId'] as String?,
    groupId: map['groupId'] as String?,
    order: (map['order'] as num?)?.toDouble(),
    lastOpenedAt: map['lastOpenedAt'] as int?,
    lastPageId: map['lastPageId'] as String?,
    lastPageTitle: map['lastPageTitle'] as String?,
    lastPageAt: map['lastPageAt'] as int?,
    starred: map['starred'] as bool? ?? false,
    trashedAt: map['trashedAt'] as int?,
    isTemplate: map['isTemplate'] as bool? ?? false,
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

  /// The category of a notebook at the top of the shelf. Notebooks inside a
  /// group leave it null and belong to their group's category.
  final String? categoryId;
  final String? groupId;

  /// Position in the custom shelf order. Notebooks saved before it existed
  /// sort by when they were made.
  final double? order;

  /// Milliseconds since epoch.
  final int createdAt;

  /// Changes when the notebook or its pages are edited.
  final int updatedAt;
  final int? lastOpenedAt;

  /// The page open most recently, to open the notebook there again.
  final String? lastPageId;

  /// Its title, for "Continue · Week 42" on the shelf.
  final String? lastPageTitle;

  /// When that page was opened (milliseconds since epoch).
  final int? lastPageAt;

  /// Shown under Starred on the shelf.
  final bool starred;

  /// When it was moved to the Trash (milliseconds since epoch), or null
  /// when it isn't in the Trash.
  final int? trashedAt;

  bool get inTrash => trashedAt != null;

  /// One of the user's own templates (see "Save as template"): kept off the
  /// shelf, and copied to start new notebooks.
  final bool isTemplate;

  double get sortOrder => order ?? createdAt.toDouble();

  Map<String, dynamic> toMap() => {
    'title': title,
    'cover': cover.toMap(),
    // Kept for app versions that only read the cover color.
    'color': cover.color,
    'paper': ?paper?.toMap(),
    'paperSize': paperSize.name,
    'orientation': orientation.name,
    'collectionId': ?collectionId,
    'categoryId': ?categoryId,
    'groupId': ?groupId,
    'order': ?order,
    'lastOpenedAt': ?lastOpenedAt,
    'lastPageId': ?lastPageId,
    'lastPageTitle': ?lastPageTitle,
    'lastPageAt': ?lastPageAt,
    if (starred) 'starred': true,
    'trashedAt': ?trashedAt,
    if (isTemplate) 'isTemplate': true,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  Notebook copyWith({
    String? title,
    NotebookCover? cover,
    PaperStyle? paper,
    String? collectionId,
    ShelfPlace? place,
    double? order,
    int? lastOpenedAt,
    ({String id, String title, int at})? lastPage,
    int? updatedAt,
    bool? starred,
    int? trashedAt,
    bool restore = false,
  }) => Notebook(
    id: id,
    title: title ?? this.title,
    cover: cover ?? this.cover,
    paper: paper ?? this.paper,
    paperSize: paperSize,
    orientation: orientation,
    collectionId: collectionId ?? this.collectionId,
    categoryId: place == null
        ? categoryId
        : (place.groupId == null ? place.categoryId : null),
    groupId: place == null ? groupId : place.groupId,
    order: order ?? this.order,
    lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    lastPageId: lastPage?.id ?? lastPageId,
    lastPageTitle: lastPage?.title ?? lastPageTitle,
    lastPageAt: lastPage?.at ?? lastPageAt,
    starred: starred ?? this.starred,
    trashedAt: restore ? null : trashedAt ?? this.trashedAt,
    isTemplate: isTemplate,
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
    this.place = unfiled,
    this.isTemplate = false,
  });

  final String title;
  final NotebookCover cover;
  final PaperStyle? paper;
  final PaperSize paperSize;
  final PaperOrientation orientation;
  final String? collectionId;

  /// Where on the shelf it goes.
  final ShelfPlace place;

  /// Made as one of the user's own templates.
  final bool isTemplate;

  Notebook build(String id, int now) => Notebook(
    id: id,
    title: title,
    cover: cover,
    paper: paper,
    paperSize: paperSize,
    orientation: orientation,
    collectionId: collectionId,
    categoryId: place.groupId == null ? place.categoryId : null,
    groupId: place.groupId,
    order: now.toDouble(),
    isTemplate: isTemplate,
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

/// Every color a cover can have: [notebookColors] (given to new notebooks
/// in turn), then softer and deeper ones.
const coverColors = [
  ...notebookColors,
  0xFF8FAF9A, // sage
  0xFFD9C3A0, // sand
  0xFFE8957F, // coral
  0xFF8FB0E8, // sky
  0xFF5C3B5E, // plum
  0xFF1F3A2E, // forest
  0xFFF2EBDD, // cream
  0xFF2B2B2B, // black
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
    this.template,
    this.period,
    this.bookmarked = false,
    this.outline,
    this.inkText,
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
    template: PageTemplate.fromMap(map['template']),
    period: PagePeriod.fromMap(map['period']),
    bookmarked: map['bookmarked'] as bool? ?? false,
    outline: map['outline'] as String?,
    inkText: map['inkText'] as String?,
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

  /// The template page it's drawn on, instead of paper.
  final PageTemplate? template;

  /// The days a planner page covers, if it's for a date.
  final PagePeriod? period;

  /// Listed under Bookmarks in the page jumper.
  final bool bookmarked;

  /// Its entry in the notebook's outline (a heading the user gave it), or
  /// null when it has none.
  final String? outline;

  /// The page's handwriting, as read on a device that can (for search):
  /// empty when it has none, null when it hasn't been read.
  final String? inkText;

  String get displayTitle => title.trim().isEmpty ? 'Untitled page' : title;

  Map<String, dynamic> toMap() => {
    'notebookId': notebookId,
    'sectionId': sectionId,
    'title': title,
    'order': order,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'paper': ?paper?.toMap(),
    'template': ?template?.toMap(),
    'period': ?period?.toMap(),
    if (bookmarked) 'bookmarked': true,
    'outline': ?outline,
    'inkText': ?inkText,
  };

  NotePage copyWith({
    String? id,
    String? notebookId,
    String? sectionId,
    double? order,
    int? createdAt,
    String? title,
    PaperStyle? Function()? paper,
    int? updatedAt,
    bool? bookmarked,
    String? Function()? outline,
    String? Function()? inkText,
  }) => NotePage(
    id: id ?? this.id,
    notebookId: notebookId ?? this.notebookId,
    sectionId: sectionId ?? this.sectionId,
    title: title ?? this.title,
    order: order ?? this.order,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    paper: paper == null ? this.paper : paper(),
    template: template,
    period: period,
    bookmarked: bookmarked ?? this.bookmarked,
    outline: outline == null ? this.outline : outline(),
    inkText: inkText == null ? this.inkText : inkText(),
  );
}
