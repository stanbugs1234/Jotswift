import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/planner/book.dart';
import 'package:notely/core/planner/pages.dart';
import 'package:notely/core/planner/pdf_ops.dart';

import 'pdf_parse.dart';

/// The Focus planner as tool/make_life_planners.py makes it (2027,
/// landscape, Monday).
Book focusBook() => Book(
  'Focus Planner',
  'An ADHD-friendly planner: one thing at a time.',
  day(2027, 1, 1),
  style: PlannerStyle.hex(accent: '#2F6F6A', tab: '#E6F0EE', paper: '#FBFBF8'),
  front: [
    ('Year goals', 'target', yearGoals, 'start'),
    ('Year in pixels', 'heart', yearPixels, 'start'),
    ('Routines', 'sun', routines, 'start'),
    ('Rewards menu', 'gift', rewardsMenu, 'start'),
  ],
  monthKinds: [
    PageKind('Calendar', monthCalendar, 'months'),
    PageKind('Habits', monthHabits, 'habits'),
    PageKind('Review', monthReview, 'month_review'),
  ],
  weekKinds: [
    PageKind('Week', weekPlan, 'weeks'),
    PageKind('Review', weekReview, 'week_review'),
  ],
  dayKinds: [
    PageKind('Plan', dayFocus, 'days'),
    PageKind('Check-in', dayCheckin, 'checkin'),
  ],
  collections: [
    Collection('dumps', 'Brain dumps', 'cloud', 'dumps', [
      for (var k = 0; k < 12; k++) ('Brain dump ${k + 1}', brainDump),
    ], 'Empty your head, then sort it out.'),
    Collection('breakdowns', 'Task breakdowns', 'list', 'breakdowns', [
      for (var k = 0; k < 12; k++) ('Task ${k + 1}', taskBreakdown),
    ], 'Big, scary tasks broken into tiny steps.'),
    Collection('notes', 'Notes', 'pencil', 'notes', [
      for (var k = 0; k < 20; k++) ('Note ${k + 1}', linedPage),
    ], 'Lined pages for anything.'),
  ],
);

void main() {
  test('the Focus planner comes out as the catalog has it', () {
    final book = focusBook();
    final pdf = writePdf(book.build(), book.style);
    final want = pdfObjects(
      File('catalog/focus_planner_2027/template.pdf').readAsBytesSync(),
    );
    final got = pdfObjects(pdf);
    expect(got.length, want.length);
    final wrong = [
      for (final id in want.keys)
        if (got[id] != want[id]) id,
    ];
    if (wrong.isNotEmpty) {
      final id = wrong.first;
      final a = want[id]!.split('\n'), b = (got[id] ?? '').split('\n');
      for (var i = 0; i < a.length; i++) {
        if (i >= b.length || a[i] != b[i]) {
          fail(
            '${wrong.length} objects differ; first $id, line $i:\n'
            ' want ${a[i]}\n got  ${i < b.length ? b[i] : '(none)'}',
          );
        }
      }
    }
    final spec = jsonDecode(
      File('catalog/focus_planner_2027/template.json').readAsStringSync(),
    ) as Map<String, Object?>;
    expect(jsonEncode(book.spec()['sections']), jsonEncode(spec['sections']));
  });
}
