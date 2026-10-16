import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/catalog/template_spec.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';
import 'package:notely/features/notebooks/open_page.dart';

void main() {
  NotePage page(String id, {PagePeriod? period}) => NotePage(
    id: id,
    notebookId: 'n',
    sectionId: 's',
    title: id,
    order: 0,
    createdAt: 0,
    updatedAt: 0,
    period: period,
  );

  PagePeriod span(DateTime from, DateTime to) => PagePeriod.dates(from, to);

  Notebook notebook({String? lastPageId, DateTime? lastPageAt}) => Notebook(
    id: 'n',
    title: 'Planner',
    cover: const NotebookCover.color(0),
    createdAt: 0,
    updatedAt: 0,
    lastPageId: lastPageId,
    lastPageAt: lastPageAt?.millisecondsSinceEpoch,
  );

  // A small 2027 planner: the year, October, and two weeks of it.
  final year = page(
    '2027',
    period: span(DateTime(2027), DateTime(2027, 12, 31)),
  );
  final october = page(
    'October',
    period: span(DateTime(2027, 10), DateTime(2027, 10, 31)),
  );
  final week41 = page(
    'Week 41',
    period: span(DateTime(2027, 10, 4), DateTime(2027, 10, 10)),
  );
  final week42 = page(
    'Week 42',
    period: span(DateTime(2027, 10, 11), DateTime(2027, 10, 17)),
  );
  final notes = page('Notes');
  final planner = [year, october, week41, week42, notes];
  final oct12 = DateTime(2027, 10, 12, 9, 30);

  group('PagePeriod', () {
    test('reads dates and months, and ignores bad ones', () {
      expect(
        PagePeriod.fromMap({'from': '2027-10-11', 'to': '2027-10-17'}),
        span(DateTime(2027, 10, 11), DateTime(2027, 10, 17)),
      );
      expect(PagePeriod.fromMap({'month': 10}), const PagePeriod.month(10));
      for (final bad in [
        null,
        {'from': '2027-02-30', 'to': '2027-03-01'},
        {'from': '2027-10-17', 'to': '2027-10-11'},
        {'from': '11/10/2027', 'to': '2027-10-17'},
        {'month': 13},
        {'title': 'Notes'},
      ]) {
        expect(PagePeriod.fromMap(bad), isNull, reason: '$bad');
      }
    });

    test('round-trips through a map', () {
      final week = week42.period!;
      expect(PagePeriod.fromMap(week.toMap()), week);
      expect(
        PagePeriod.fromMap(const PagePeriod.month(3).toMap()),
        const PagePeriod.month(3),
      );
    });

    test('a page keeps its period and bookmark', () {
      final saved = NotePage.fromMap(
        'p',
        page('p', period: week42.period).copyWith(bookmarked: true).toMap(),
      );
      expect(saved.period, week42.period);
      expect(saved.bookmarked, isTrue);
    });
  });

  test('template.json pages carry their dates', () {
    final spec = TemplateSpec.fromJson(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'mode': 'notebook',
            'sections': [
              {
                'title': 'Weeks',
                'pages': [
                  {
                    'pdfPage': 1,
                    'title': 'Week 42',
                    'from': '2027-10-11',
                    'to': '2027-10-17',
                  },
                  {'pdfPage': 2, 'title': 'October', 'month': 10},
                  {'pdfPage': 3, 'title': 'Notes'},
                ],
              },
            ],
          }),
        ),
      ),
    );
    expect(spec.pages.map((p) => p.period), [
      week42.period,
      const PagePeriod.month(10),
      null,
    ]);
  });

  test('pages made with dates keep them', () async {
    final repo = InMemoryNotesBackend().notebooks('u');
    final nb = await repo.createNotebook(
      const NewNotebook(title: 'P', cover: NotebookCover.color(0)),
    );
    final section = (await repo.watchSections(nb.id).first).single;
    await repo.createPages(
      nb.id,
      section.id,
      [
        (title: 'Week 42', paper: null, template: null),
        (title: 'Notes', paper: null, template: null),
      ],
      periods: [week42.period],
    );
    final pages = await repo.watchPages(nb.id, section.id).first;
    expect(pages.map((p) => p.period), [week42.period, null]);
  });

  group("today's page", () {
    test('the narrowest page wins: a week over its month and year', () {
      expect(todaysPage(planner, oct12), week42);
      expect(todaysPage(planner, DateTime(2027, 10, 25)), october);
      expect(todaysPage(planner, DateTime(2027, 3, 1)), year);
      expect(todaysPage(planner, DateTime(2026, 10, 15)), isNull);
    });

    test('undated month pages match that month in any year', () {
      final months = [
        for (var m = 1; m <= 12; m++) page('M$m', period: PagePeriod.month(m)),
      ];
      expect(todaysPage(months, DateTime(2026, 10, 15))!.id, 'M10');
      expect(todaysPage(months, DateTime(2031, 2, 3))!.id, 'M2');
    });

    test('a planner for next year gives its first page nearest today', () {
      expect(nearestDatedPage(planner, DateTime(2026, 10, 15)), year);
      final weeksOnly = [week41, week42, notes];
      expect(nearestDatedPage(weeksOnly, DateTime(2026, 10, 15)), week41);
      expect(nearestDatedPage([notes], oct12), isNull);
    });
  });

  group('pageToOpen', () {
    test('on a new day, a planner opens on today', () {
      final nb = notebook(
        lastPageId: notes.id,
        lastPageAt: oct12.subtract(const Duration(days: 1)),
      );
      expect(pageToOpen(nb, planner, oct12), week42);
    });

    test('on the same day, it opens where you left off', () {
      final nb = notebook(
        lastPageId: notes.id,
        lastPageAt: DateTime(2027, 10, 12, 8),
      );
      expect(pageToOpen(nb, planner, oct12), notes);
    });

    test('never opened: today, or the nearest dated page', () {
      expect(pageToOpen(notebook(), planner, oct12), week42);
      expect(pageToOpen(notebook(), planner, DateTime(2026, 10, 15)), year);
    });

    test('a planner that has not started opens on its first page', () {
      // Its Home, not Week 1 (which starts in late December).
      final home = page('Home');
      final week1 = page(
        'Week 1',
        period: span(DateTime(2026, 12, 28), DateTime(2027, 1, 3)),
      );
      final january = page(
        'January',
        period: span(DateTime(2027), DateTime(2027, 1, 31)),
      );
      expect(
        pageToOpen(notebook(), [home, january, week1], DateTime(2026, 10, 16)),
        home,
      );
    });

    test('a notebook without dates opens where you left off, or first', () {
      final plain = [page('a'), page('b'), page('c')];
      final nb = notebook(
        lastPageId: 'b',
        lastPageAt: oct12.subtract(const Duration(days: 3)),
      );
      expect(pageToOpen(nb, plain, oct12)!.id, 'b');
      expect(pageToOpen(notebook(), plain, oct12)!.id, 'a');
    });

    test('a deleted last page falls back; no pages gives null', () {
      final nb = notebook(lastPageId: 'gone', lastPageAt: oct12);
      expect(pageToOpen(nb, planner, oct12), week42);
      expect(pageToOpen(nb, [page('a')], oct12)!.id, 'a');
      expect(pageToOpen(nb, const [], oct12), isNull);
    });
  });
}
