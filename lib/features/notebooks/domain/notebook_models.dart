import 'package:flutter/foundation.dart';

/// A notebook holds sections, and each section holds pages.
@immutable
class Notebook {
  const Notebook({
    required this.id,
    required this.title,
    required this.color,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Notebook.fromMap(String id, Map<String, dynamic> map) => Notebook(
    id: id,
    title: map['title'] as String? ?? 'Untitled notebook',
    color: map['color'] as int? ?? notebookColors.first,
    createdAt: map['createdAt'] as int? ?? 0,
    updatedAt: map['updatedAt'] as int? ?? 0,
  );

  final String id;
  final String title;

  /// Cover color as ARGB, one of [notebookColors].
  final int color;

  /// Milliseconds since epoch.
  final int createdAt;
  final int updatedAt;

  Map<String, dynamic> toMap() => {
    'title': title,
    'color': color,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  Notebook copyWith({String? title, int? color, int? updatedAt}) => Notebook(
    id: id,
    title: title ?? this.title,
    color: color ?? this.color,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

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
  });

  factory NotePage.fromMap(String id, Map<String, dynamic> map) => NotePage(
    id: id,
    notebookId: map['notebookId'] as String,
    sectionId: map['sectionId'] as String,
    title: map['title'] as String? ?? '',
    order: (map['order'] as num?)?.toDouble() ?? 0,
    createdAt: map['createdAt'] as int? ?? 0,
    updatedAt: map['updatedAt'] as int? ?? 0,
  );

  final String id;
  final String notebookId;
  final String sectionId;

  /// May be empty; shown as "Untitled page".
  final String title;
  final double order;
  final int createdAt;
  final int updatedAt;

  String get displayTitle => title.trim().isEmpty ? 'Untitled page' : title;

  Map<String, dynamic> toMap() => {
    'notebookId': notebookId,
    'sectionId': sectionId,
    'title': title,
    'order': order,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
}
