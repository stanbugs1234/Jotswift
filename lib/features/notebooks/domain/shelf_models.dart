import 'package:flutter/foundation.dart';

/// A top-level folder in the sidebar, e.g. "School" or "Work".
@immutable
class Category {
  const Category({required this.id, required this.title, required this.order});

  factory Category.fromMap(String id, Map<String, dynamic> map) => Category(
    id: id,
    title: map['title'] as String? ?? 'Untitled category',
    order: (map['order'] as num?)?.toDouble() ?? 0,
  );

  final String id;
  final String title;
  final double order;

  Map<String, dynamic> toMap() => {'title': title, 'order': order};
}

/// A stack of notebooks on the shelf. Groups can hold other groups.
///
/// Only top-level groups have a [categoryId]; a group inside another group
/// belongs to its parent's category. That way moving a group is one write.
@immutable
class NotebookGroup {
  const NotebookGroup({
    required this.id,
    required this.title,
    required this.order,
    required this.createdAt,
    required this.updatedAt,
    this.categoryId,
    this.parentGroupId,
  });

  factory NotebookGroup.fromMap(String id, Map<String, dynamic> map) {
    final createdAt = map['createdAt'] as int? ?? 0;
    return NotebookGroup(
      id: id,
      title: map['title'] as String? ?? 'Untitled group',
      categoryId: map['categoryId'] as String?,
      parentGroupId: map['parentGroupId'] as String?,
      order: (map['order'] as num?)?.toDouble() ?? createdAt.toDouble(),
      createdAt: createdAt,
      updatedAt: map['updatedAt'] as int? ?? 0,
    );
  }

  final String id;
  final String title;
  final String? categoryId;
  final String? parentGroupId;
  final double order;
  final int createdAt;
  final int updatedAt;

  Map<String, dynamic> toMap() => {
    'title': title,
    'categoryId': ?categoryId,
    'parentGroupId': ?parentGroupId,
    'order': order,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
}

/// Where something sits on the shelf: inside a group, in a category, or
/// (both null) at the top level with no category.
typedef ShelfPlace = ({String? categoryId, String? groupId});

const ShelfPlace unfiled = (categoryId: null, groupId: null);
