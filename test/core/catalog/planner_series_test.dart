import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/catalog/catalog_item.dart';
import 'package:notely/core/catalog/planner_series.dart';
import 'package:notely/core/catalog/template_spec.dart';

CatalogItem planner(String id, String name) => CatalogItem(
  id: id,
  kind: CatalogKind.template,
  name: name,
  version: 1,
  unlock: const CatalogUnlock(free: true),
  visibility: CatalogVisibility.public,
  templateMode: TemplateMode.notebook,
);

void main() {
  final y2026 = planner('autumn_planner_2026', 'Autumn 2026 Planner');
  final y2627 = planner(
    'autumn_planner_2026_27',
    'Autumn Planner Oct 2026 - Dec 2027',
  );
  final y2027 = planner('autumn_planner_2027', 'Autumn 2027 Planner');
  final undated = planner('life_planner_undated', 'Life Planner (undated)');
  final life = planner('life_planner_2027', 'Life Planner 2027');
  final budget = planner('budget_planner', 'Monthly Budget Planner');

  test('editions of a planner are one series, in date order', () {
    final series = plannerSeries([y2027, budget, undated, y2627, life, y2026]);
    expect([for (final s in series) s.name], [
      'Autumn Planner',
      'Monthly Budget Planner',
      'Life Planner',
    ]);
    expect(series[0].editions, [y2026, y2627, y2027]);
    expect(series[2].editions, [life, undated], reason: 'undated last');
  });

  test('editions are labelled by their dates', () {
    expect(editionLabel(y2026), '2026');
    expect(editionLabel(y2627), 'Oct 2026 – Dec 2027');
    expect(editionLabel(undated), 'Undated');
    expect(
      editionLabel(planner('academic_planner_2026_27', 'Academic 2026-27')),
      '2026–27',
    );
    expect(editionLabel(budget), isNull);
    expect(undatedName('2027 Weekly Planner'), 'Weekly Planner');
    expect(undatedName('Goals & Projects (undated)'), 'Goals & Projects');
  });

  test('a new notebook starts as the edition running longest from today', () {
    final s = plannerSeries([y2026, y2627, y2027]).single;
    expect(s.defaultEdition(DateTime(2026, 10, 17)), y2627);
    expect(s.defaultEdition(DateTime(2026, 3, 1)), y2026);
    expect(s.defaultEdition(DateTime(2028, 2, 1)), y2027);
    expect(
      s.defaultEdition(DateTime(2026, 10, 17), usable: (e) => e != y2627),
      y2026,
    );
    final l = plannerSeries([life, undated]).single;
    expect(l.defaultEdition(DateTime(2026, 10, 17)), life, reason: 'next');
    expect(l.defaultEdition(DateTime(2029)), undated);
  });

  group('a planner started later in its year', () {
    final spec = TemplateSpec.fromJson(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'mode': 'notebook',
            'sections': [
              {
                'title': 'Start',
                'pages': [
                  {'pdfPage': 1, 'title': 'Cover'},
                ],
              },
              {
                'title': 'Months',
                'pages': [
                  {
                    'pdfPage': 2,
                    'title': 'October',
                    'from': '2026-10-01',
                    'to': '2026-10-31',
                  },
                  {'pdfPage': 3, 'title': 'Oct goals', 'group': 'goals'},
                  {
                    'pdfPage': 4,
                    'title': 'Week 44',
                    'from': '2026-10-26',
                    'to': '2026-11-01',
                  },
                  {
                    'pdfPage': 5,
                    'title': 'November',
                    'from': '2026-11-01',
                    'to': '2026-11-30',
                  },
                  {'pdfPage': 6, 'title': 'Nov goals', 'group': 'goals'},
                ],
              },
              {
                'title': 'Notes',
                'pages': [
                  {'pdfPage': 7, 'title': 'Notes'},
                ],
              },
            ],
          }),
        ),
      ),
    );

    test('can start in any month it has', () {
      expect(spec.months, [DateTime(2026, 10), DateTime(2026, 11)]);
    });

    test('leaves out what ends before it starts', () {
      final made = spec.made(from: DateTime(2026, 11));
      expect(
        [
          for (final s in made)
            for (final p in s.pages) p.title,
        ],
        ['Cover', 'Week 44', 'November', 'Nov goals', 'Notes'],
        reason: "a month's goals go with it; a week into November stays",
      );
      expect(spec.pageCount(from: DateTime(2026, 11)), 5);
      expect(spec.pageCount(skip: {'goals'}), 5);
    });

    test('continued, leaves out what has no dates', () {
      expect(
        [for (final s in spec.made(datedOnly: true)) s.title],
        ['Months'],
      );
    });
  });
}
