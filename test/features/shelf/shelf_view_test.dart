import 'package:flutter_test/flutter_test.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';
import 'package:notely/features/shelf/shelf_screen.dart';
import 'package:notely/features/shelf/shelf_view.dart';

Notebook notebook(
  String id, {
  String? categoryId,
  String? groupId,
  double? order,
  int createdAt = 0,
  int updatedAt = 0,
  int? lastOpenedAt,
  String? title,
}) => Notebook(
  id: id,
  title: title ?? id,
  cover: const NotebookCover.color(0),
  categoryId: categoryId,
  groupId: groupId,
  order: order,
  createdAt: createdAt,
  updatedAt: updatedAt,
  lastOpenedAt: lastOpenedAt,
);

NotebookGroup notebookGroup(
  String id, {
  String? categoryId,
  String? parentGroupId,
  double order = 0,
  String? title,
}) => NotebookGroup(
  id: id,
  title: title ?? id,
  categoryId: categoryId,
  parentGroupId: parentGroupId,
  order: order,
  createdAt: 0,
  updatedAt: 0,
);

void main() {
  // School (category)
  //   biology (notebook)
  //   semester1 (group)
  //     chem (notebook)
  //     labs (group)
  //       lab1 (notebook)
  // ideas (notebook, no category)
  final shelf = Shelf(
    [
      notebook('biology', categoryId: 'school', order: 1),
      notebook('chem', groupId: 'semester1'),
      notebook('lab1', groupId: 'labs'),
      notebook('ideas', order: 2),
    ],
    [
      notebookGroup('semester1', categoryId: 'school'),
      notebookGroup('labs', parentGroupId: 'semester1'),
    ],
  );

  List<String> ids(ShelfContents c) => [
    ...c.groups.map((g) => 'group:${g.id}'),
    ...c.notebooks.map((n) => n.id),
  ];

  group('contents', () {
    test('All shows the top level of every category', () {
      expect(ids(shelf.contents(const AllNotebooks(), ShelfSort.custom)), [
        'group:semester1',
        'biology',
        'ideas',
      ]);
    });

    test('a category shows only its own top level', () {
      expect(
        ids(shelf.contents(const InCategory('school'), ShelfSort.custom)),
        ['group:semester1', 'biology'],
      );
    });

    test('a group shows its notebooks and the groups inside it', () {
      expect(
        ids(shelf.contents(const InGroup('semester1'), ShelfSort.custom)),
        ['group:labs', 'chem'],
      );
      expect(ids(shelf.contents(const InGroup('labs'), ShelfSort.custom)), [
        'lab1',
      ]);
    });

    test('a notebook whose group is gone shows at the top level', () {
      final orphaned = Shelf([notebook('lost', groupId: 'deleted')], []);
      expect(ids(orphaned.contents(const AllNotebooks(), ShelfSort.custom)), [
        'lost',
      ]);
    });

    test('Recent lists opened notebooks, newest first, without groups', () {
      final recent = Shelf(
        [
          notebook('a', lastOpenedAt: 10),
          notebook('b'),
          notebook('c', groupId: 'g', lastOpenedAt: 30),
        ],
        [notebookGroup('g')],
      );
      expect(ids(recent.contents(const RecentNotebooks(), ShelfSort.name)), [
        'c',
        'a',
      ]);
    });
  });

  group('sorting', () {
    final mixed = Shelf([
      notebook('b', title: 'banana', createdAt: 1, updatedAt: 5),
      notebook('a', title: 'Apple', createdAt: 2, updatedAt: 9),
      notebook('c', title: 'cherry', createdAt: 3, lastOpenedAt: 7),
    ], []);
    List<String> sorted(ShelfSort sort) =>
        ids(mixed.contents(const AllNotebooks(), sort));

    test('custom order falls back to creation order', () {
      expect(sorted(ShelfSort.custom), ['b', 'a', 'c']);
    });

    test('by name ignores case', () {
      expect(sorted(ShelfSort.name), ['a', 'b', 'c']);
    });

    test('by last modified, newest first', () {
      expect(sorted(ShelfSort.modified), ['a', 'b', 'c']);
    });

    test('by last opened, never-opened last', () {
      expect(sorted(ShelfSort.lastOpened).first, 'c');
    });

    test('a group counts as opened when a notebook inside it was', () {
      final withGroups = Shelf(
        [notebook('n', groupId: 'late', lastOpenedAt: 50)],
        [notebookGroup('early', order: 1), notebookGroup('late', order: 2)],
      );
      expect(
        ids(withGroups.contents(const AllNotebooks(), ShelfSort.lastOpened)),
        ['group:late', 'group:early'],
      );
    });
  });

  group('groups', () {
    test('notebooksIn includes nested groups', () {
      expect(shelf.notebooksIn(shelf.group('semester1')!).map((n) => n.id), {
        'chem',
        'lab1',
      });
    });

    test('descendantGroupIds finds every level', () {
      expect(shelf.descendantGroupIds('semester1'), {'labs'});
      expect(shelf.descendantGroupIds('labs'), isEmpty);
    });

    test('back from a group goes to its parent, then its category', () {
      expect(shelf.parentOf(const InGroup('labs')), const InGroup('semester1'));
      expect(
        shelf.parentOf(const InGroup('semester1')),
        const InCategory('school'),
      );
      expect(shelf.parentOf(const InCategory('school')), const AllNotebooks());
    });

    test('a nested group belongs to its top-level group category', () {
      expect(shelf.categoryOfGroup('labs'), 'school');
    });

    test('a loop in the data does not hang', () {
      final loop = Shelf([], [
        notebookGroup('x', parentGroupId: 'y'),
        notebookGroup('y', parentGroupId: 'x'),
      ]);
      expect(loop.groupPath('x').length, 2);
    });
  });

  group('locations', () {
    test('survive the round trip through the URL', () {
      for (final location in [
        const AllNotebooks(),
        const RecentNotebooks(),
        const InCategory('c1'),
        const InGroup('g1'),
      ]) {
        final uri = Uri.parse(location.path);
        expect(ShelfLocation.fromQuery(uri.queryParameters), location);
      }
    });

    test('new things go where you are', () {
      expect(const InCategory('c').place, (categoryId: 'c', groupId: null));
      expect(const InGroup('g').place, (categoryId: null, groupId: 'g'));
      expect(const RecentNotebooks().place, unfiled);
    });
  });

  test('orderBetween puts an item between its neighbours', () {
    expect(orderBetween(1, 3), 2);
    expect(orderBetween(null, 3), 2);
    expect(orderBetween(5, null), 6);
  });

  test('shortDate', () {
    final now = DateTime(2026, 10, 14, 9);
    int at(DateTime d) => d.millisecondsSinceEpoch;
    expect(shortDate(at(DateTime(2026, 10, 14, 1)), now: now), 'today');
    expect(shortDate(at(DateTime(2026, 10, 13, 23)), now: now), 'yesterday');
    expect(shortDate(at(DateTime(2026, 3, 2)), now: now), 'Mar 2');
    expect(shortDate(at(DateTime(2025, 12, 31)), now: now), 'Dec 31, 2025');
  });
}
