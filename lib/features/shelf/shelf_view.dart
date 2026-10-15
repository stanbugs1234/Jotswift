import 'dart:math';

import 'package:flutter/foundation.dart';

import '../notebooks/domain/notebook_models.dart';

/// Which part of the shelf is shown.
sealed class ShelfLocation {
  const ShelfLocation();

  /// Reads the location from the shelf URL's query, e.g.
  /// `/notebooks?category=abc`.
  factory ShelfLocation.fromQuery(Map<String, String> query) {
    if (query['group'] case final id?) return InGroup(id);
    if (query['category'] case final id?) return InCategory(id);
    return switch (query['view']) {
      'recent' => const RecentNotebooks(),
      'starred' => const StarredNotebooks(),
      'unfiled' => const UnfiledNotebooks(),
      'trash' => const TrashedNotebooks(),
      _ => const AllNotebooks(),
    };
  }

  String get path => switch (this) {
    AllNotebooks() => '/notebooks',
    RecentNotebooks() => '/notebooks?view=recent',
    StarredNotebooks() => '/notebooks?view=starred',
    UnfiledNotebooks() => '/notebooks?view=unfiled',
    TrashedNotebooks() => '/notebooks?view=trash',
    InCategory(:final id) => '/notebooks?category=$id',
    InGroup(:final id) => '/notebooks?group=$id',
  };

  /// Where a notebook or group made here goes.
  ShelfPlace get place => switch (this) {
    InCategory(:final id) => (categoryId: id, groupId: null),
    InGroup(:final id) => (categoryId: null, groupId: id),
    AllNotebooks() ||
    RecentNotebooks() ||
    StarredNotebooks() ||
    UnfiledNotebooks() ||
    TrashedNotebooks() => unfiled,
  };

  /// Whether notebooks and groups can be made here. The lists that are
  /// picked out of the rest (recent, starred, trash) can't.
  bool get canCreate => switch (this) {
    RecentNotebooks() || StarredNotebooks() || TrashedNotebooks() => false,
    _ => true,
  };
}

final class AllNotebooks extends ShelfLocation {
  const AllNotebooks();

  @override
  bool operator ==(Object other) => other is AllNotebooks;

  @override
  int get hashCode => 1;
}

/// The notebooks opened most recently.
final class RecentNotebooks extends ShelfLocation {
  const RecentNotebooks();

  @override
  bool operator ==(Object other) => other is RecentNotebooks;

  @override
  int get hashCode => 2;
}

/// Every starred notebook, wherever it is.
final class StarredNotebooks extends ShelfLocation {
  const StarredNotebooks();

  @override
  bool operator ==(Object other) => other is StarredNotebooks;

  @override
  int get hashCode => 5;
}

/// What isn't in any category.
final class UnfiledNotebooks extends ShelfLocation {
  const UnfiledNotebooks();

  @override
  bool operator ==(Object other) => other is UnfiledNotebooks;

  @override
  int get hashCode => 6;
}

/// Notebooks moved to the Trash, newest first.
final class TrashedNotebooks extends ShelfLocation {
  const TrashedNotebooks();

  @override
  bool operator ==(Object other) => other is TrashedNotebooks;

  @override
  int get hashCode => 7;
}

final class InCategory extends ShelfLocation {
  const InCategory(this.id);

  final String id;

  @override
  bool operator ==(Object other) => other is InCategory && other.id == id;

  @override
  int get hashCode => Object.hash(3, id);
}

final class InGroup extends ShelfLocation {
  const InGroup(this.id);

  final String id;

  @override
  bool operator ==(Object other) => other is InGroup && other.id == id;

  @override
  int get hashCode => Object.hash(4, id);
}

enum ShelfSort {
  custom('Custom'),
  lastOpened('Last opened'),
  modified('Last modified'),
  name('Name');

  const ShelfSort(this.label);

  final String label;
}

enum ShelfLayout { grid, list }

enum ShelfSize { large, small }

/// What a shelf location shows: groups first, then notebooks.
@immutable
class ShelfContents {
  const ShelfContents(this.groups, this.notebooks);

  final List<NotebookGroup> groups;
  final List<Notebook> notebooks;

  bool get isEmpty => groups.isEmpty && notebooks.isEmpty;
}

/// Everything the shelf knows, with lookups used to lay it out. Notebooks
/// in the Trash show only under [TrashedNotebooks].
class Shelf {
  Shelf(List<Notebook> notebooks, List<NotebookGroup> groups)
    : _notebooks = [
        for (final n in notebooks)
          if (!n.inTrash) n,
      ],
      _trashed = [
        for (final n in notebooks)
          if (n.inTrash) n,
      ]..sort((a, b) => b.trashedAt!.compareTo(a.trashedAt!)),
      _groups = {for (final g in groups) g.id: g};

  final List<Notebook> _notebooks;
  final List<Notebook> _trashed;
  final Map<String, NotebookGroup> _groups;

  static const recentLimit = 20;

  /// Notebooks not in the Trash.
  int get notebookCount => _notebooks.length;

  int get trashCount => _trashed.length;

  int get starredCount => _notebooks.where((n) => n.starred).length;

  NotebookGroup? group(String id) => _groups[id];

  /// The category a notebook is in, directly or through its group.
  String? categoryOfNotebook(Notebook n) =>
      _notebookIsTopLevel(n) ? n.categoryId : categoryOfGroup(n.groupId!);

  /// A group's parent, or null at the top level. A parent that no longer
  /// exists counts as the top level, so nothing is ever lost.
  NotebookGroup? _parent(NotebookGroup g) =>
      g.parentGroupId == null ? null : _groups[g.parentGroupId];

  bool _isTopLevel(NotebookGroup g) => _parent(g) == null;

  bool _notebookIsTopLevel(Notebook n) =>
      n.groupId == null || !_groups.containsKey(n.groupId);

  ShelfContents contents(ShelfLocation location, ShelfSort sort) {
    switch (location) {
      case RecentNotebooks():
        final opened = _notebooks.where((n) => n.lastOpenedAt != null).toList()
          ..sort((a, b) => b.lastOpenedAt!.compareTo(a.lastOpenedAt!));
        return ShelfContents(const [], opened.take(recentLimit).toList());
      case StarredNotebooks():
        return _sorted(const [], _notebooks.where((n) => n.starred), sort);
      case TrashedNotebooks():
        return ShelfContents(const [], _trashed);
      case UnfiledNotebooks():
        return _sorted(
          _groups.values.where((g) => _isTopLevel(g) && g.categoryId == null),
          _notebooks.where(
            (n) => _notebookIsTopLevel(n) && n.categoryId == null,
          ),
          sort,
        );
      case AllNotebooks():
        return _sorted(
          _groups.values.where(_isTopLevel),
          _notebooks.where(_notebookIsTopLevel),
          sort,
        );
      case InCategory(:final id):
        return _sorted(
          _groups.values.where((g) => _isTopLevel(g) && g.categoryId == id),
          _notebooks.where((n) => _notebookIsTopLevel(n) && n.categoryId == id),
          sort,
        );
      case InGroup(:final id):
        return _sorted(
          _groups.values.where((g) => g.parentGroupId == id),
          _notebooks.where((n) => n.groupId == id),
          sort,
        );
    }
  }

  /// Notebooks (not in the Trash) whose title contains [query].
  List<Notebook> search(String query) {
    final q = query.trim().toLowerCase();
    return _notebooks.where((n) => n.title.toLowerCase().contains(q)).toList()
      ..sort(
        (a, b) => (b.lastOpenedAt ?? b.updatedAt).compareTo(
          a.lastOpenedAt ?? a.updatedAt,
        ),
      );
  }

  ShelfContents _sorted(
    Iterable<NotebookGroup> groups,
    Iterable<Notebook> notebooks,
    ShelfSort sort,
  ) {
    int byTime(int? a, int? b) => (b ?? 0).compareTo(a ?? 0);
    int byName(String a, String b) =>
        a.toLowerCase().compareTo(b.toLowerCase());

    final g = groups.toList()
      ..sort(
        (a, b) => switch (sort) {
          ShelfSort.custom => a.order.compareTo(b.order),
          ShelfSort.lastOpened => byTime(_lastOpened(a), _lastOpened(b)),
          ShelfSort.modified => byTime(_modified(a), _modified(b)),
          ShelfSort.name => byName(a.title, b.title),
        },
      );
    final n = notebooks.toList()
      ..sort(
        (a, b) => switch (sort) {
          ShelfSort.custom => a.sortOrder.compareTo(b.sortOrder),
          ShelfSort.lastOpened => byTime(a.lastOpenedAt, b.lastOpenedAt),
          ShelfSort.modified => byTime(a.updatedAt, b.updatedAt),
          ShelfSort.name => byName(a.title, b.title),
        },
      );
    return ShelfContents(g, n);
  }

  /// Every notebook inside [group], at any depth.
  List<Notebook> notebooksIn(NotebookGroup group) {
    final ids = {group.id, ...descendantGroupIds(group.id)};
    return _notebooks.where((n) => ids.contains(n.groupId)).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  int? _lastOpened(NotebookGroup g) =>
      notebooksIn(g).map((n) => n.lastOpenedAt ?? 0).fold(null, _later);

  int _modified(NotebookGroup g) =>
      notebooksIn(g).map((n) => n.updatedAt).fold(g.updatedAt, max);

  static int? _later(int? a, int b) => a == null ? b : max(a, b);

  /// Ids of the groups inside [groupId], at any depth.
  Set<String> descendantGroupIds(String groupId) {
    final found = <String>{};
    var frontier = {groupId};
    while (frontier.isNotEmpty) {
      final next = {
        for (final g in _groups.values)
          if (frontier.contains(g.parentGroupId) && !found.contains(g.id)) g.id,
      };
      found.addAll(next);
      frontier = next;
    }
    return found;
  }

  /// The groups from the top level down to [groupId] (for breadcrumbs and
  /// the back button).
  List<NotebookGroup> groupPath(String groupId) {
    final path = <NotebookGroup>[];
    var current = _groups[groupId];
    while (current != null && !path.contains(current)) {
      path.insert(0, current);
      current = _parent(current);
    }
    return path;
  }

  /// The category a group belongs to: its top-level group's.
  String? categoryOfGroup(String groupId) {
    final path = groupPath(groupId);
    return path.isEmpty ? null : path.first.categoryId;
  }

  /// Where to go "up" from [location].
  ShelfLocation parentOf(ShelfLocation location) {
    if (location is! InGroup) return const AllNotebooks();
    final path = groupPath(location.id);
    if (path.length > 1) return InGroup(path[path.length - 2].id);
    final category = path.firstOrNull?.categoryId;
    return category == null ? const AllNotebooks() : InCategory(category);
  }
}

/// An order value that sorts between [before] and [after] (either may be
/// missing at the ends of a list).
double orderBetween(double? before, double? after) => switch ((before, after)) {
  (null, null) => DateTime.now().millisecondsSinceEpoch.toDouble(),
  (null, final a?) => a - 1,
  (final b?, null) => b + 1,
  (final b?, final a?) => (b + a) / 2,
};
