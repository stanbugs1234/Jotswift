import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/planner/book.dart';
import 'package:notely/core/planner/presets.dart';
import 'package:notely/core/planner/recipe.dart';

import 'pdf_parse.dart';

/// Every link in [pdf], as (page index, target page object id), and the
/// page object ids.
(List<int>, List<int>) links(Map<int, String> objs) {
  final kids = RegExp(r'/Kids \[([^\]]*)\]').firstMatch(objs[2]!)!.group(1)!;
  final pages = [
    for (final m in RegExp(r'(\d+) 0 R').allMatches(kids))
      int.parse(m.group(1)!),
  ];
  final targets = [
    for (final o in objs.values)
      if (RegExp(r'/Dest \[(\d+) 0 R').firstMatch(o) case final m?)
        int.parse(m.group(1)!),
  ];
  return (pages, targets);
}

void main() {
  test('the Focus recipe makes the catalog planner', () {
    final recipe = lifePlannerRecipes['focus']!().copyWith(
      start: () => day(2027, 1, 1),
    );
    final made = makePlanner(recipe);
    final spec = jsonDecode(
      File('catalog/focus_planner_2027/template.json').readAsStringSync(),
    ) as Map<String, Object?>;
    // Front pages have groups of their own here, to be left out.
    final sections = made.spec['sections']! as List;
    for (final page in (sections.first as Map)['pages'] as List) {
      (page as Map).remove('group');
    }
    expect(jsonEncode(sections), jsonEncode(spec['sections']));
    expect(
      [for (final g in made.spec['groups']! as List) (g as Map)['id']],
      containsAll([
        'habits',
        'month_review',
        'weeks',
        'week_review',
        'days',
        'checkin',
        'dumps',
        'notes',
      ]),
    );
  });

  test('a recipe survives being saved', () {
    for (final make in lifePlannerRecipes.values) {
      final recipe = make().copyWith(
        start: () => day(2026, 10, 1),
        months: 15,
        weekStart: 6,
      );
      final again = PlannerRecipe.fromMap(
        jsonDecode(jsonEncode(recipe.toMap())) as Map<String, Object?>,
      );
      expect(again.toMap(), recipe.toMap());
      expect(again.pageCount, recipe.pageCount);
    }
  });

  test('a planner without week or day pages has no links to them', () {
    final recipe = standardRecipe(start: day(2027, 1, 1))
        .copyWith(week: [], day: []);
    final made = makePlanner(recipe);
    final (pages, targets) = links(pdfObjects(made.pdf));
    expect(pages, hasLength(made.pages));
    expect(targets, isNotEmpty);
    expect(targets.every(pages.contains), isTrue);
    final titles = [
      for (final s in made.spec['sections']! as List)
        for (final p in (s as Map)['pages'] as List) (p as Map)['title'],
    ];
    expect(titles.where((t) => '$t'.startsWith('Week ')), isEmpty);
    expect(made.pages, 2 + 2 + 12 * 3 + 21 + 7);
  });

  test('an undated notebook of sections only', () {
    final made = makePlanner(sectionsRecipe().copyWith(month: [], front: []));
    final (pages, targets) = links(pdfObjects(made.pdf));
    expect(targets.every(pages.contains), isTrue);
    expect(made.pages, 2 + 1 + 40);
  });

  test('a page can be drawn alone, to show it', () {
    final recipe = lifePlannerRecipes['life']!();
    for (final g in ['home', 'year', 'months', 'days', 'finance']) {
      expect(pdfObjects(previewPage(recipe, g)).length, greaterThan(4));
    }
  });

  test('parts of a page can be left off, and the rest fill it', () {
    final recipe = standardRecipe(start: day(2027, 1, 1));
    String dayPage(PlannerRecipe r) =>
        pdfObjects(previewPage(r, 'day_life')).values.join('\n');
    expect(dayPage(recipe), contains('(6am)'));
    final noSchedule = recipe.copyWith(
      day: [const KindRef('day_life', off: {'schedule', 'affirmation'})],
    );
    final page = dayPage(noSchedule);
    expect(page, isNot(contains('(6am)')));
    expect(page, isNot(contains('(Affirmation)')));
    expect(page, contains('(To-do)'));
    final again = PlannerRecipe.fromMap(
      jsonDecode(jsonEncode(noSchedule.toMap())) as Map<String, Object?>,
    );
    expect(again.day.single.off, {'schedule', 'affirmation'});
  });
}
