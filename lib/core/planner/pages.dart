/// Page bodies for planner books: a port of tool/planner_pages.py. Each
/// takes a Ctx (c) and draws in c.left..c.right, c.top..c.bottom, adapting
/// to landscape or portrait.
///
/// Writing space is never cramped: ruled lines are 24pt or more apart, and
/// a page that needs more room gets a second page in the book instead.
library;

import 'book.dart';
import 'pdf_ops.dart';

String _hour(int h) => '${h % 12 == 0 ? 12 : h % 12}${h < 12 ? 'am' : 'pm'}';

// Shared pieces

/// Hours from [start] to [end], each split in half, to block out.
void timeBlocks(
  Ctx c,
  num x0,
  num x1,
  num top,
  num bottom, [
  int start = 6,
  int end = 22,
  String title = 'Time blocks',
]) {
  label(c.p, x0, top - 12, title, size: 10, iconKind: 'calendar');
  top -= 26;
  final n = end - start;
  final gap = (top - bottom) / n;
  for (var k = 0; k <= n; k++) {
    final y = top - k * gap;
    if (k < n) {
      c.p.text(x0, y - 10, _hour(start + k), 7.5, rgb: c.s.soft, bold: true);
      c.p.line(
        x0 + 30,
        y - gap / 2,
        x1,
        y - gap / 2,
        rgb: tint(c.s.rule, 0.5),
        width: 0.5,
      );
    }
    c.p.line(x0 + 30, y, x1, y);
  }
}

/// A card with a title, an optional grey prompt and lines (or dots).
void promptBox(
  Ctx c,
  num x0,
  num x1,
  num top,
  num bottom,
  String title, [
  String? prompt,
  String? iconKind,
  String kind = 'lines',
]) {
  var y = card(
    c.p,
    x0,
    bottom,
    x1 - x0,
    top - bottom,
    title: title,
    iconKind: iconKind,
  );
  if (prompt != null) {
    c.p.text(x0 + 10, y - 4, prompt, 8, rgb: c.s.soft);
    y -= 16;
  }
  switch (kind) {
    case 'lines':
      lines(c.p, x0 + 10, x1 - 10, y - 18, bottom + 10, 24);
    case 'checks':
      checks(c.p, x0 + 10, x1 - 10, y - 16, bottom + 12, 24);
    case 'dots':
      dots(c.p, x0 + 12, x1 - 12, y - 8, bottom + 10, 14);
  }
}

/// A row to tick [n] times: name on the left, boxes or circles after.
void trackerRow(
  Ctx c,
  num x0,
  num x1,
  num y,
  String name,
  int n, [
  String? iconKind,
  String kind = 'boxes',
]) {
  if (iconKind != null) icon(c.p, iconKind, x0 + 6, y + 4, 11, c.s.accent);
  c.p.text(
    x0 + (iconKind != null ? 18 : 0),
    y,
    name,
    9,
    rgb: c.s.ink,
    bold: true,
  );
  final bx = x0 + 96;
  final size = [14, (x1 - bx) / n - 4].reduce((a, b) => a < b ? a : b);
  for (var k = 0; k < n; k++) {
    final x = bx + k * (size + 4);
    if (kind == 'circles') {
      circle(
        c.p,
        x + size / 2,
        y + 3,
        size / 2,
        c.s.soft,
        fill: false,
        width: 0.9,
      );
    } else {
      rrect(c.p, x, y - 3, size, size, 3, stroke: c.s.soft, width: 0.9);
    }
  }
}

void rating(
  Ctx c,
  num x0,
  num y,
  String name, [
  int n = 5,
  List<String>? words,
  String? iconKind,
]) {
  if (iconKind != null) icon(c.p, iconKind, x0 + 6, y + 4, 11, c.s.accent);
  c.p.text(
    x0 + (iconKind != null ? 18 : 0),
    y,
    name,
    9,
    rgb: c.s.ink,
    bold: true,
  );
  scale(c.p, x0 + 96, y + 3, n, size: 12, labels: words);
}

/// A table with headings; [fracs] are column widths (fractions).
num table(
  Ctx c,
  num x0,
  num x1,
  num top,
  num bottom,
  List<String> heads, [
  List<num>? fracs,
  num rowH = 26,
]) {
  fracs ??= [for (final _ in heads) 1 / heads.length];
  rrect(c.p, x0, top - 22, x1 - x0, 22, 6, fill: c.s.tab);
  var x = x0;
  final edges = <num>[];
  for (final (i, head) in heads.indexed) {
    final w = (x1 - x0) * fracs[i];
    c.p.text(x + 8, top - 15, head, 8.5, rgb: c.s.accent, bold: true);
    edges.add(x);
    x += w;
  }
  var y = top - 22;
  while (y - rowH >= bottom - 0.5) {
    y -= rowH;
    c.p.line(x0, y, x1, y);
  }
  for (final e in edges.skip(1)) {
    c.p.line(e, top - 22, e, y, rgb: tint(c.s.rule, 0.3), width: 0.6);
  }
  return y;
}

/// This page's month, small, with linked dates and weeks.
num miniCal(Ctx c, num x0, num x1, num top, [int? today]) => c.book.miniMonth(
  c.p,
  c.m!,
  x0,
  top,
  x1 - x0,
  12,
  7.5,
  today: today,
  weekLinks: true,
);

int? _dayOfMonth(Book book, int m, int n) => book.dayOfMonth(m, n);

// Year pages

void yearGoals(Ctx c) {
  const areas = [
    ('Health & body', 'heart'),
    ('Mind', 'cloud'),
    ('Work & study', 'briefcase'), //
    ('Money', 'coin'), ('People', 'people'), ('Fun & growth', 'star'),
  ];
  final nCols = c.landscape ? 3 : 2;
  final cols = columns(c.left, c.right, nCols, 12);
  final nRows = areas.length ~/ nCols;
  final rws = rows(c.top, c.bottom, [for (var i = 0; i < nRows; i++) 1], 12);
  for (final (k, (name, ic)) in areas.indexed) {
    final ((x0, x1), (t, b)) = (cols[k % nCols], rws[k ~/ nCols]);
    promptBox(
      c,
      x0,
      x1,
      t,
      b,
      name,
      'What would make this a great year?',
      ic,
      'checks',
    );
  }
}

/// A square for every day, coloured by mood; each opens its day.
void yearPixels(Ctx c) {
  final book = c.book;
  const nameW = 20;
  final cw = (c.right - c.left - nameW) / book.n;
  final (top, bottom) = (c.top, c.bottom + 30);
  final rh = (top - 16 - bottom) / 31;
  for (var m = 0; m < book.n; m++) {
    final x = c.left + nameW + m * cw;
    c.p.text(
      x + cw / 2,
      top - 10,
      book.monthName(m, short: true),
      8,
      rgb: c.s.accent,
      bold: true,
      center: true,
    );
    c.p.link(x, top - 16, cw, 20, book.monthMain(m));
  }
  for (var n = 1; n < 32; n++) {
    final y = top - 16 - n * rh;
    c.p.text(
      c.left + nameW - 5,
      y + rh / 2 - 3,
      '$n',
      6.5,
      rgb: c.s.soft,
      right: true,
    );
    for (var m = 0; m < book.n; m++) {
      final i = _dayOfMonth(book, m, n);
      if (i == null) continue;
      final x = c.left + nameW + m * cw;
      rrect(
        c.p,
        x + 1.5,
        y + 1,
        cw - 3,
        rh - 2,
        2,
        stroke: c.s.rule,
        width: 0.6,
      );
      c.p.link(x, y, cw, rh, book.dayMain(i));
    }
  }
  const keys = ['Great', 'Good', 'Okay', 'Low', 'Hard'];
  final kw = (c.right - c.left - 40) / 5;
  label(c.p, c.left, c.bottom + 6, 'Key', size: 9);
  for (final (k, word) in keys.indexed) {
    final x = c.left + 40 + k * kw;
    rrect(c.p, x, c.bottom + 2, 14, 14, 3, stroke: c.s.soft);
    c.p.text(x + 20, c.bottom + 6, word, 8, rgb: c.s.soft);
    c.p.line(
      x + 20 + textWidth(word, 8) + 4,
      c.bottom + 3,
      x + kw - 12,
      c.bottom + 3,
    );
  }
}

/// Six frames to paste photos or stickers in, with captions.
void visionBoard(Ctx c) {
  final cols = columns(c.left, c.right, 3, 12);
  final rws = rows(c.top, c.bottom, [1, 1], 12);
  for (var k = 0; k < 6; k++) {
    final ((x0, x1), (t, b)) = (cols[k % 3], rws[k ~/ 3]);
    rrect(c.p, x0, b + 26, x1 - x0, t - b - 26, 8, stroke: c.s.rule);
    dots(c.p, x0 + 10, x1 - 10, t - 10, b + 34, 16);
    c.p.line(x0, b + 8, x1, b + 8);
  }
}

void routines(Ctx c) {
  final cols = columns(c.left, c.right, 2, 16);
  const items = [
    ('Morning routine', 'sun', 'Start small: 3-5 steps.'),
    ('Evening wind-down', 'moon', 'Screens off, prep tomorrow.'),
  ];
  for (final (k, (name, ic, hint)) in items.indexed) {
    promptBox(
      c,
      cols[k].$1,
      cols[k].$2,
      c.top,
      c.bottom,
      name,
      hint,
      ic,
      'checks',
    );
  }
}

/// Rewards for small, medium and big wins.
void rewardsMenu(Ctx c) {
  final cols = columns(c.left, c.right, 3, 12);
  const items = [
    ('Small wins', '5 minutes: a song, a snack'),
    ('Medium wins', 'An episode, a walk, a coffee out'),
    ('Big wins', 'A day trip, something new'),
  ];
  for (final (k, (name, hint)) in items.indexed) {
    promptBox(
      c,
      cols[k].$1,
      cols[k].$2,
      c.top,
      c.bottom,
      name,
      hint,
      'gift',
      'checks',
    );
  }
}

// Month pages

/// The month: a big grid; dates open days, the W column opens weeks.
/// [side]: the Focus and Notes boxes beside (or under) it.
void monthCalendar(Ctx c, {bool side = true, Set<String> off = const {}}) {
  final boxes = [
    for (final b in const ['focus', 'notes'])
      if (!off.contains(b)) b,
  ];
  side = side && boxes.isNotEmpty;
  final (book, p) = (c.book, c.p);
  final beside = c.landscape;
  final right = c.right - (side && beside ? 170 : 0);
  final bottom = side && !beside ? c.bottom + 150 : c.bottom;
  final gridLeft = c.left + 30;
  final cw = (right - gridLeft) / 7;
  final top = c.top + 4;
  for (final (k, name) in book.weekdayNames().indexed) {
    p.text(
      gridLeft + k * cw + cw / 2,
      top - 10,
      name.substring(0, 3),
      8.5,
      rgb: c.s.soft,
      bold: true,
      center: true,
    );
  }
  final weeks = book.monthWeeks(c.m!);
  final rh = (top - 18 - bottom) / weeks.length;
  for (final (r, row) in weeks.indexed) {
    final y = top - 18 - (r + 1) * rh;
    final wi = book.rowWeek(c.m!, r, row);
    if (wi != null) {
      rrect(p, c.left, y + 2, 26, rh - 4, 6, fill: c.s.tab);
      p.text(
        c.left + 13,
        y + rh / 2 - 3,
        'W${wi + 1}',
        8,
        rgb: c.s.accent,
        bold: true,
        center: true,
      );
      p.link(c.left, y, 26, rh, book.weekMain(wi));
    }
    for (final (k, cell) in row.indexed) {
      final x = gridLeft + k * cw;
      p.rect(x, y, cw, rh, stroke: c.s.rule);
      final i = book.cellDay(c.m!, cell);
      if (cell is DateTime) {
        final inside = i != null;
        p.text(
          x + 6,
          y + rh - 14,
          '${cell.day}',
          10,
          rgb: inside ? c.s.ink : c.s.rule,
          bold: inside,
        );
      } else if ((cell as int) <= 31) {
        p.text(x + 6, y + rh - 14, '$cell', 10, rgb: c.s.soft);
      }
      if (i != null) {
        circle(p, x + cw - 7, y + rh - 10, 1.8, tint(c.s.accent, 0.3));
        p.link(x, y, cw, rh, book.dayMain(i));
      }
    }
  }
  if (!side) return;
  if (beside) {
    final x0 = right + 16;
    final rws = rows(c.top, c.bottom, [
      for (final b in boxes) b == 'focus' ? 1 : 1.4,
    ], 12);
    for (final (i, b) in boxes.indexed) {
      _calendarBox(c, b, x0, c.right, rws[i].$1, rws[i].$2);
    }
  } else {
    final cols = columns(c.left, c.right, boxes.length, 16);
    for (final (i, b) in boxes.indexed) {
      _calendarBox(c, b, cols[i].$1, cols[i].$2, c.bottom + 136, c.bottom);
    }
  }
}

void _calendarBox(Ctx c, String box, num x0, num x1, num top, num bottom) =>
    box == 'focus'
    ? promptBox(c, x0, x1, top, bottom, 'Focus', null, 'target', 'checks')
    : promptBox(c, x0, x1, top, bottom, 'Notes', null, null, 'lines');

/// A habit per row, a box per day; each day number opens that day.
void monthHabits(Ctx c) {
  final (book, p) = (c.book, c.p);
  DateTime? first;
  var count = 31;
  if (book.dated) {
    first = book.months[c.m!];
    count = daysInMonth(first.year, first.month);
  }
  const nameW = 110;
  final cw = (c.right - c.left - nameW) / count;
  final top = c.top;
  for (var n = 1; n <= count; n++) {
    final x = c.left + nameW + (n - 1) * cw;
    p.text(
      x + cw / 2,
      top - 8,
      '$n',
      6.5,
      rgb: c.s.accent,
      bold: true,
      center: true,
    );
    if (first != null) {
      final d = day(first.year, first.month, n);
      p.text(
        x + cw / 2,
        top - 17,
        dayNames[pyWeekday(d)][0],
        5.5,
        rgb: c.s.soft,
        center: true,
      );
    }
    final i = _dayOfMonth(book, c.m!, n);
    if (i != null) p.link(x, top - 20, cw, 24, book.dayMain(i));
  }
  label(p, c.left, top - 12, 'Habit', size: 9, iconKind: 'check');
  var y = top - 26;
  final num size = cw - 3 < 13 ? cw - 3 : 13;
  while (y - 26 >= c.bottom) {
    y -= 26;
    p.line(c.left, y + 2, c.left + nameW - 10, y + 2);
    for (var n = 0; n < count; n++) {
      final x = c.left + nameW + n * cw + (cw - size) / 2;
      rrect(p, x, y + 3, size, size, 2.5, stroke: c.s.rule, width: 0.6);
    }
  }
}

typedef Prompt = (String name, String? icon, String? hint);

const monthReviewPrompts = <Prompt>[
  ('Wins', 'star', 'What went well? Big or small.'),
  ('What worked', 'check', 'Strategies, tools, times of day.'),
  ('What got in the way', 'cloud', 'No blame, just patterns.'),
  ('Energy & mood', 'bolt', 'When did I feel best?'),
  ('Next month', 'target', 'One thing to try.'),
  ('Grateful for', 'heart', null),
];

/// Boxes for each of [prompts], in two or three columns.
void monthReview(Ctx c, [List<Prompt> prompts = monthReviewPrompts]) {
  final nCols = c.landscape ? 3 : 2;
  final cols = columns(c.left, c.right, nCols, 12);
  final nRows = (prompts.length + nCols - 1) ~/ nCols;
  final rws = rows(c.top, c.bottom, [for (var i = 0; i < nRows; i++) 1], 12);
  for (final (k, (name, ic, hint)) in prompts.indexed) {
    final (x0, x1) = cols[k % nCols];
    final (t, b) = rws[k ~/ nCols];
    promptBox(c, x0, x1, t, b, name, hint, ic);
  }
}

void monthGoals(Ctx c) {
  final cols = columns(c.left, c.right, 2, 16);
  final [t1, t2] = rows(c.top, c.bottom, [1, 1], 12);
  promptBox(
    c,
    cols[0].$1,
    cols[0].$2,
    t1.$1,
    t1.$2,
    'Goals this month',
    null,
    'target',
    'checks',
  );
  promptBox(
    c,
    cols[1].$1,
    cols[1].$2,
    t1.$1,
    t1.$2,
    'Action steps',
    null,
    'list',
    'checks',
  );
  promptBox(
    c,
    cols[0].$1,
    cols[0].$2,
    t2.$1,
    t2.$2,
    'Important dates',
    null,
    'calendar',
  );
  promptBox(c, cols[1].$1, cols[1].$2, t2.$1, t2.$2, 'To remember');
}

/// Mood and anxiety per day, plus what helped: a monthly check-in.
void monthMentalHealth(Ctx c) {
  final (p, book) = (c.p, c.book);
  final top = c.top;
  label(
    p,
    c.left,
    top - 12,
    'Mood & anxiety by day',
    size: 10,
    iconKind: 'heart',
  );
  var count = 31;
  if (book.dated) {
    final first = book.months[c.m!];
    count = daysInMonth(first.year, first.month);
  }
  final cw = (c.right - c.left - 70) / count;
  for (final (r, name) in ['Mood', 'Anxiety', 'Sleep', 'Energy'].indexed) {
    final y = top - 44 - r * 22;
    p.text(c.left, y + 3, name, 8.5, rgb: c.s.ink, bold: true);
    for (var n = 0; n < count; n++) {
      final x = c.left + 70 + n * cw;
      rrect(p, x + 1, y, cw - 2, 14, 2, stroke: c.s.rule, width: 0.6);
      if (r == 0) {
        p.text(
          x + cw / 2,
          top - 26,
          '${n + 1}',
          6,
          rgb: c.s.accent,
          bold: true,
          center: true,
        );
        final i = _dayOfMonth(book, c.m!, n + 1);
        if (i != null) p.link(x, top - 30, cw, 14, book.dayMain(i));
      }
    }
  }
  p.text(
    c.left + 70,
    top - 134,
    'Colour 1-5: 1 = low, 5 = high.',
    7.5,
    rgb: c.s.soft,
  );
  final nCols = c.landscape ? 3 : 2;
  final cols = columns(c.left, c.right, nCols, 12);
  const items = <Prompt>[
    ('What helped', 'leaf', null), ('Triggers I noticed', 'bolt', null), //
    ('Self-care I did', 'heart', null),
    ('Questions for therapy', 'cloud', null),
    ('Small wins', 'star', null), ('Next month I need', 'target', null),
  ];
  final rws = rows(top - 146, c.bottom, [1, 1], 12);
  for (final (k, (name, ic, hint)) in items.take(nCols * 2).indexed) {
    final (x0, x1) = cols[k % nCols];
    final (t, b) = rws[k ~/ nCols];
    promptBox(c, x0, x1, t, b, name, hint, ic);
  }
}

void monthBudget(Ctx c) {
  final cols = columns(c.left, c.right, 2, 16);
  final [t1, t2] = rows(c.top, c.bottom, [1, 1.3], 12);
  var (x0, x1) = cols[0];
  card(
    c.p,
    x0,
    t1.$2,
    x1 - x0,
    t1.$1 - t1.$2,
    title: 'Income',
    iconKind: 'coin',
  );
  table(
    c,
    x0 + 8,
    x1 - 8,
    t1.$1 - 30,
    t1.$2 + 8,
    ['Source', 'Amount'],
    [0.65, 0.35],
  );
  (x0, x1) = cols[1];
  card(
    c.p,
    x0,
    t1.$2,
    x1 - x0,
    t1.$1 - t1.$2,
    title: 'Bills',
    iconKind: 'calendar',
  );
  table(
    c,
    x0 + 8,
    x1 - 8,
    t1.$1 - 30,
    t1.$2 + 8,
    ['Bill', 'Due', 'Paid'],
    [0.55, 0.25, 0.2],
  );
  (x0, x1) = (c.left, c.right);
  card(
    c.p,
    x0,
    t2.$2,
    x1 - x0,
    t2.$1 - t2.$2,
    title: 'Spending',
    iconKind: 'chart',
  );
  table(
    c,
    x0 + 8,
    x1 - 8,
    t2.$1 - 30,
    t2.$2 + 8,
    ['Date', 'What', 'Category', 'Amount'],
    [0.15, 0.45, 0.22, 0.18],
  );
}

/// A month of posts: channel, idea and status per day.
void contentCalendar(Ctx c) => table(
  c,
  c.left,
  c.right,
  c.top,
  c.bottom,
  ['Date', 'Channel', 'Idea / hook', 'Status'],
  [0.12, 0.18, 0.55, 0.15],
  24,
);

void incomeExpenses(Ctx c) {
  final cols = columns(c.left, c.right, 2, 16);
  for (final (k, name) in ['Income', 'Expenses'].indexed) {
    final (x0, x1) = cols[k];
    card(
      c.p,
      x0,
      c.bottom,
      x1 - x0,
      c.top - c.bottom,
      title: name,
      iconKind: 'coin',
    );
    table(
      c,
      x0 + 8,
      x1 - 8,
      c.top - 30,
      c.bottom + 40,
      ['Date', 'Description', 'Amount'],
      [0.2, 0.55, 0.25],
    );
    c.p.text(x0 + 12, c.bottom + 16, 'Total', 9, rgb: c.s.accent, bold: true);
    c.p.line(x0 + 50, c.bottom + 14, x1 - 12, c.bottom + 14);
  }
}

void milestones(Ctx c) {
  final cols = columns(c.left, c.right, 2, 16);
  promptBox(
    c,
    cols[0].$1,
    cols[0].$2,
    c.top,
    c.bottom,
    'Milestones this month',
    'Linked to your goal dashboards.',
    'target',
    'checks',
  );
  final [t1, t2] = rows(c.top, c.bottom, [1, 1], 12);
  promptBox(c, cols[1].$1, cols[1].$2, t1.$1, t1.$2, 'Progress', null, 'chart');
  promptBox(
    c,
    cols[1].$1,
    cols[1].$2,
    t2.$1,
    t2.$2,
    'Next steps',
    null,
    'list',
    'checks',
  );
}

void wins(Ctx c) {
  final nCols = c.landscape ? 3 : 2;
  final cols = columns(c.left, c.right, nCols, 12);
  final rws = rows(c.top, c.bottom, c.landscape ? [1, 1] : [1, 1, 1], 12);
  for (final (t, b) in rws) {
    for (final (x0, x1) in cols) {
      rrect(c.p, x0, b, x1 - x0, t - b, 10, stroke: c.s.rule);
      icon(c.p, 'star', x0 + 16, t - 16, 12, tint(c.s.accent, 0.3));
      lines(c.p, x0 + 12, x1 - 12, t - 40, b + 12, 24);
    }
  }
}

// Week pages

/// The week's days as linked boxes, with priorities and a focus.
void weekPlan(Ctx c, [Set<String> off = const {}]) {
  final p = c.p;
  final boxes = [
    for (final b in const ['priorities', 'focus', 'calendar'])
      if (!off.contains(b)) b,
  ];
  if (c.landscape) {
    final num side = boxes.isEmpty ? 0 : 180;
    final days = c.book.weekDayPages(c.w!);
    final gridR = boxes.isEmpty ? c.right : c.right - side - 14;
    final cols = columns(c.left, gridR, 4, 8);
    final rws = rows(c.top, c.bottom, [1, 1], 8);
    for (var k = 0; k < 8; k++) {
      final ((x0, x1), (t, b)) = (cols[k % 4], rws[k ~/ 4]);
      rrect(p, x0, b, x1 - x0, t - b, 8, stroke: c.s.rule);
      if (k < 7) {
        final (name, sub, page) = days[k];
        rrect(p, x0, t - 22, x1 - x0, 22, 8, fill: c.s.tab);
        p.text(x0 + 8, t - 15, name, 9, rgb: c.s.accent, bold: true);
        if (sub.isNotEmpty) {
          p.text(x1 - 18, t - 15, sub, 8, rgb: c.s.soft, right: true);
        }
        if (page != null) {
          chevron(p, x1 - 9, t - 11.5, 6, c.s.accent);
          p.link(x0, t - 24, x1 - x0, 24, page);
        }
        checks(p, x0 + 8, x1 - 8, t - 40, b + 10, 24);
      } else {
        label(p, x0 + 8, t - 16, 'Notes', size: 9);
        lines(p, x0 + 8, x1 - 8, t - 34, b + 10, 24);
      }
    }
    final x0 = c.right - side;
    const weights = {'priorities': 1.1, 'focus': 0.8, 'calendar': 1};
    final rs = rows(c.top, c.bottom, [for (final b in boxes) weights[b]!], 10);
    for (final (i, b) in boxes.indexed) {
      final (t, bt) = rs[i];
      switch (b) {
        case 'priorities':
          promptBox(
            c,
            x0,
            c.right,
            t,
            bt,
            'Top 3 priorities',
            null,
            'target',
            'checks',
          );
        case 'focus':
          promptBox(
            c,
            x0,
            c.right,
            t,
            bt,
            'One focus',
            'If only one thing gets done...',
            'star',
          );
        default:
          miniCal(c, x0 + 4, c.right - 4, t - 6);
      }
    }
  } else {
    final bottom = weekStripTall(c, reserve: boxes.isEmpty ? 0 : 150);
    if (boxes.isEmpty) return;
    final cols = columns(c.left, c.right, boxes.length, 10);
    for (final (i, b) in boxes.indexed) {
      final (x0, x1) = cols[i];
      switch (b) {
        case 'priorities':
          promptBox(
            c,
            x0,
            x1,
            bottom - 12,
            c.bottom,
            'Top 3 priorities',
            null,
            'target',
            'checks',
          );
        case 'focus':
          promptBox(
            c,
            x0,
            x1,
            bottom - 12,
            c.bottom,
            'One focus',
            null,
            'star',
          );
        default:
          miniCal(c, x0, x1, bottom - 18);
      }
    }
  }
}

/// Portrait: seven linked day rows down the page; returns the bottom.
num weekStripTall(Ctx c, {num reserve = 150}) {
  final p = c.p;
  final days = c.book.weekDayPages(c.w!);
  final bottom = c.bottom + reserve;
  final rws = rows(c.top, bottom, [1, 1, 1, 1, 1, 1, 1], 6);
  for (final (k, (name, sub, page)) in days.indexed) {
    final (t, b) = rws[k];
    rrect(p, c.left, b, c.right - c.left, t - b, 8, stroke: c.s.rule);
    rrect(p, c.left, b, 70, t - b, 8, fill: c.s.tab);
    p.text(
      c.left + 8,
      t - 16,
      name.substring(0, 3),
      10,
      rgb: c.s.accent,
      bold: true,
    );
    if (sub.isNotEmpty) p.text(c.left + 8, t - 30, sub, 8, rgb: c.s.soft);
    if (page != null) {
      chevron(p, c.left + 60, t - 12, 6, c.s.accent);
      p.link(c.left, b, 70, t - b, page);
    }
    lines(p, c.left + 80, c.right - 10, t - 22, b + 6, 24);
  }
  return bottom;
}

const weekReviewPrompts = <Prompt>[
  ('Wins this week', 'star', null), ('What drained me', 'bolt', null), //
  ('What helped', 'leaf', null), ('Carry over', 'list', null),
  ("Next week's focus", 'target', null), ('Grateful for', 'heart', null),
];

void weekReview(Ctx c) => monthReview(c, weekReviewPrompts);

/// Meals and movement for each day of the week.
void mealsMovement(Ctx c) {
  final p = c.p;
  final days = c.book.weekDayPages(c.w!);
  const heads = [
    'Day',
    'Breakfast',
    'Lunch',
    'Dinner',
    'Snacks',
    'Movement',
    'Water',
  ];
  const fr = [0.1, 0.17, 0.17, 0.17, 0.13, 0.16, 0.1];
  final bottom = c.bottom + 110;
  table(
    c,
    c.left,
    c.right,
    c.top,
    bottom,
    heads,
    fr,
    (c.top - 22 - bottom) / 7,
  );
  final rh = (c.top - 22 - bottom) / 7;
  for (final (k, (name, _, page)) in days.indexed) {
    final ty = c.top - 22 - (k + 1) * rh;
    p.text(
      c.left + 8,
      ty + rh / 2 - 3,
      name.substring(0, 3),
      9,
      rgb: c.s.accent,
      bold: true,
    );
    if (page != null) p.link(c.left, ty, (c.right - c.left) * fr[0], rh, page);
  }
  final cols = columns(c.left, c.right, 2, 16);
  promptBox(
    c,
    cols[0].$1,
    cols[0].$2,
    bottom - 10,
    c.bottom,
    'Groceries',
    null,
    'list',
    'checks',
  );
  promptBox(
    c,
    cols[1].$1,
    cols[1].$2,
    bottom - 10,
    c.bottom,
    'Prep ahead',
    null,
    'check',
    'checks',
  );
}

// Day pages

/// A day: a schedule down the left (unless [off]), and [boxes] (id,
/// weight, draw) stacked on the right, those [off] left out so the rest
/// grow.
void _dayLayout(
  Ctx c,
  Set<String> off, {
  required int start,
  required int end,
  required String scheduleTitle,
  required List<(String, num, void Function(num x0, num x1, num t, num b))>
  boxes,
}) {
  final [(a0, a1), (b0, b1)] = columns(c.left, c.right, 2, 18);
  final schedule = !off.contains('schedule');
  if (schedule) {
    timeBlocks(c, a0, a1, c.top, c.bottom, start, end, scheduleTitle);
  }
  final shown = [
    for (final b in boxes)
      if (!off.contains(b.$1)) b,
  ];
  if (shown.isEmpty) return;
  final (x0, x1) = schedule ? (b0, b1) : (c.left, c.right);
  final rs = rows(c.top, c.bottom, [for (final b in shown) b.$2], 10);
  for (final (i, (_, _, draw)) in shown.indexed) {
    draw(x0, x1, rs[i].$1, rs[i].$2);
  }
}

/// ADHD-friendly day: time blocks, Top 3, one thing, to-do and a reward.
void dayFocus(Ctx c, [Set<String> off = const {}]) {
  final p = c.p;
  _dayLayout(
    c,
    off,
    start: 7,
    end: c.landscape ? 21 : 22,
    scheduleTitle: 'Time blocks',
    boxes: [
      (
        'one_thing',
        0.75,
        (x0, x1, t, b) => promptBox(
          c,
          x0,
          x1,
          t,
          b,
          'The one thing',
          'If only this gets done, today counts.',
          'star',
        ),
      ),
      (
        'top3',
        1.15,
        (x0, x1, t, b) {
          final y = card(
            p,
            x0,
            b,
            x1 - x0,
            t - b,
            title: 'Top 3',
            iconKind: 'target',
          );
          final h = (y - b - 10 - 12) / 3;
          for (var k = 0; k < 3; k++) {
            final ty = y - (k + 1) * h - k * 6 + 2;
            circle(
              p,
              x0 + 18,
              ty + h / 2,
              7,
              c.s.accent,
              fill: false,
              width: 1.1,
            );
            p.line(x0 + 32, ty + h / 2 - 7, x1 - 10, ty + h / 2 - 7);
          }
        },
      ),
      (
        'todo',
        1.6,
        (x0, x1, t, b) =>
            promptBox(c, x0, x1, t, b, 'To-do', null, 'list', 'checks'),
      ),
      (
        'reward',
        0.6,
        (x0, x1, t, b) => promptBox(c, x0, x1, t, b, 'Reward', null, 'gift'),
      ),
    ],
  );
}

/// How today feels: energy, mood, body, and a place to empty your head.
void dayCheckin(Ctx c) {
  final p = c.p;
  num a0, a1, b0, b1;
  if (c.landscape) {
    [(a0, a1), (b0, b1)] = [
      for (final col in columns(c.left, c.right, 2, 18)) col,
    ];
  } else {
    (a0, a1, b0, b1) = (c.left, c.right, c.left, c.right);
  }
  final tScales = c.top;
  const hScales = 172;
  final y = card(
    p,
    a0,
    tScales - hScales,
    a1 - a0,
    hScales,
    title: "How I'm doing",
    iconKind: 'bolt',
  );
  rating(c, a0 + 10, y - 10, 'Energy', 5, null, 'bolt');
  rating(c, a0 + 10, y - 34, 'Mood', 5, null, 'heart');
  rating(c, a0 + 10, y - 58, 'Focus', 5, null, 'target');
  trackerRow(c, a0 + 10, a1 - 10, y - 82, 'Water', 8, 'drop', 'circles');
  trackerRow(c, a0 + 10, a1 - 10, y - 106, 'Sleep (hrs)', 10, 'moon');
  trackerRow(c, a0 + 10, a1 - 10, y - 130, 'Movement', 6, 'leaf');
  if (c.landscape) {
    final [t1, t2] = rows(tScales - hScales - 12, c.bottom, [1, 1], 12);
    promptBox(
      c,
      a0,
      a1,
      t1.$1,
      t1.$2,
      'Morning: how am I arriving?',
      'Worries, hopes, one intention.',
      'sun',
    );
    promptBox(
      c,
      a0,
      a1,
      t2.$1,
      t2.$2,
      'Evening: let it go',
      'What went okay? What can wait?',
      'moon',
    );
    promptBox(
      c,
      b0,
      b1,
      c.top,
      c.bottom,
      'Brain dump',
      'Everything on your mind. Sort it later.',
      'cloud',
      'dots',
    );
  } else {
    final [t1, t2, t3] = rows(tScales - hScales - 12, c.bottom, [
      1,
      1,
      1.3,
    ], 12);
    final [(x0, x1), (y0, y1)] = columns(c.left, c.right, 2, 12);
    promptBox(
      c,
      x0,
      x1,
      t1.$1,
      t1.$2,
      'Morning',
      'Worries, hopes, one intention.',
      'sun',
    );
    promptBox(
      c,
      y0,
      y1,
      t1.$1,
      t1.$2,
      'Evening',
      'What went okay? What can wait?',
      'moon',
    );
    promptBox(
      c,
      c.left,
      c.right,
      t2.$1,
      t2.$2,
      'Meds, meals & snacks',
      null,
      'check',
      'checks',
    );
    promptBox(
      c,
      c.left,
      c.right,
      t3.$1,
      t3.$2,
      'Brain dump',
      'Everything on your mind.',
      'cloud',
      'dots',
    );
  }
}

/// Wellness day: check-in plus gratitude and a journal page.
void dayJournal(Ctx c) {
  final p = c.p;
  num a0, a1, b0, b1;
  if (c.landscape) {
    [(a0, a1), (b0, b1)] = [
      for (final col in columns(c.left, c.right, 2, 18)) col,
    ];
  } else {
    (a0, a1, b0, b1) = (c.left, c.right, c.left, c.right);
  }
  const h = 148;
  final y = card(
    p,
    a0,
    c.top - h,
    a1 - a0,
    h,
    title: 'Today I feel',
    iconKind: 'heart',
  );
  const words = [
    'Calm',
    'Happy',
    'Tired',
    'Anxious',
    'Sad',
    'Angry',
    'Hopeful',
    'Proud',
  ];
  var (x, yy) = (a0 + 12, y - 10);
  for (final wd in words) {
    final wdt = textWidth(wd, 8.5) + 18;
    if (x + wdt > a1 - 10) (x, yy) = (a0 + 12, yy - 22);
    rrect(p, x, yy - 6, wdt, 18, 9, stroke: c.s.rule);
    p.text(x + 9, yy, wd, 8.5, rgb: c.s.soft);
    x += wdt + 6;
  }
  rating(c, a0 + 10, yy - 30, 'Stress', 5, null, 'bolt');
  trackerRow(c, a0 + 10, a1 - 10, yy - 54, 'Water', 8, 'drop', 'circles');
  if (c.landscape) {
    final [t1, t2] = rows(c.top - h - 12, c.bottom, [1, 1.2], 12);
    promptBox(
      c,
      a0,
      a1,
      t1.$1,
      t1.$2,
      'Three good things',
      null,
      'star',
      'checks',
    );
    promptBox(
      c,
      a0,
      a1,
      t2.$1,
      t2.$2,
      'Self-care today',
      null,
      'leaf',
      'checks',
    );
    promptBox(
      c,
      b0,
      b1,
      c.top,
      c.bottom,
      'Journal',
      "What's on my heart today?",
      'pencil',
    );
  } else {
    final [t1, t2] = rows(c.top - h - 12, c.bottom, [1, 2.2], 12);
    final [(x0, x1), (y0, y1)] = columns(c.left, c.right, 2, 12);
    promptBox(
      c,
      x0,
      x1,
      t1.$1,
      t1.$2,
      'Three good things',
      null,
      'star',
      'checks',
    );
    promptBox(
      c,
      y0,
      y1,
      t1.$1,
      t1.$2,
      'Self-care today',
      null,
      'leaf',
      'checks',
    );
    promptBox(
      c,
      c.left,
      c.right,
      t2.$1,
      t2.$2,
      'Journal',
      "What's on my heart today?",
      'pencil',
    );
  }
}

/// Life planner day: schedule, Top 3, to-do, gratitude, affirmation.
void dayLife(Ctx c, [Set<String> off = const {}]) => _dayLayout(
  c,
  off,
  start: 6,
  end: 22,
  scheduleTitle: 'Schedule',
  boxes: [
    (
      'top3',
      0.9,
      (x0, x1, t, b) =>
          promptBox(c, x0, x1, t, b, 'Top 3', null, 'target', 'checks'),
    ),
    (
      'todo',
      1.6,
      (x0, x1, t, b) =>
          promptBox(c, x0, x1, t, b, 'To-do', null, 'list', 'checks'),
    ),
    (
      'grateful',
      0.8,
      (x0, x1, t, b) =>
          promptBox(c, x0, x1, t, b, 'Grateful for', null, 'heart'),
    ),
    (
      'affirmation',
      0.55,
      (x0, x1, t, b) => promptBox(c, x0, x1, t, b, 'Affirmation', null, 'star'),
    ),
  ],
);

/// Goals planner day: priorities tied to goals, schedule, notes.
void dayGoals(Ctx c, [Set<String> off = const {}]) => _dayLayout(
  c,
  off,
  start: 6,
  end: 22,
  scheduleTitle: 'Schedule',
  boxes: [
    (
      'top3',
      1.2,
      (b0, b1, t, b) {
        final y = card(
          c.p,
          b0,
          b,
          b1 - b0,
          t - b,
          title: 'Top 3 for my goals',
          iconKind: 'target',
        );
        final h = (y - b - 8) / 3;
        for (var k = 0; k < 3; k++) {
          final ty = y - (k + 1) * h;
          c.p.text(
            b0 + 10,
            ty + h / 2,
            '${k + 1}',
            11,
            rgb: c.s.accent,
            bold: true,
          );
          c.p.line(b0 + 26, ty + h / 2 - 2, b1 - 90, ty + h / 2 - 2);
          c.p.text(b1 - 84, ty + h / 2, 'Goal #', 7.5, rgb: c.s.soft);
          c.p.line(b1 - 54, ty + h / 2 - 2, b1 - 10, ty + h / 2 - 2);
        }
      },
    ),
    (
      'tasks',
      1.2,
      (x0, x1, t, b) =>
          promptBox(c, x0, x1, t, b, 'Other tasks', null, 'list', 'checks'),
    ),
    (
      'notes',
      1,
      (x0, x1, t, b) =>
          promptBox(c, x0, x1, t, b, 'Notes & wins', null, 'star'),
    ),
  ],
);

/// Student day: classes, due today, study block and to-do.
void dayStudent(Ctx c) {
  final [(a0, a1), (b0, b1)] = columns(c.left, c.right, 2, 18);
  final [t1, t2] = rows(c.top, c.bottom, [1, 1.2], 10);
  card(
    c.p,
    a0,
    t1.$2,
    a1 - a0,
    t1.$1 - t1.$2,
    title: 'Classes',
    iconKind: 'cap',
  );
  table(
    c,
    a0 + 8,
    a1 - 8,
    t1.$1 - 30,
    t1.$2 + 8,
    ['Time', 'Class', 'Room'],
    [0.22, 0.56, 0.22],
  );
  timeBlocks(c, a0, a1, t2.$1, t2.$2, 15, 22, 'Study blocks');
  final [u1, u2, u3] = rows(c.top, c.bottom, [1, 1.3, 0.9], 10);
  promptBox(c, b0, b1, u1.$1, u1.$2, 'Due today', null, 'check', 'checks');
  promptBox(c, b0, b1, u2.$1, u2.$2, 'To-do', null, 'list', 'checks');
  final y = card(
    c.p,
    b0,
    u3.$2,
    b1 - b0,
    u3.$1 - u3.$2,
    title: 'Pomodoros',
    iconKind: 'target',
  );
  for (var k = 0; k < 8; k++) {
    circle(c.p, b0 + 22 + k * 26, y - 14, 9, c.s.soft, fill: false, width: 0.9);
  }
}

/// Business day: 3 priorities, time blocks, health and habits.
void dayBusiness(Ctx c, [Set<String> off = const {}]) => _dayLayout(
  c,
  off,
  start: 7,
  end: 20,
  scheduleTitle: 'Time blocks',
  boxes: [
    (
      'priorities',
      1,
      (x0, x1, t, b) =>
          promptBox(c, x0, x1, t, b, '3 priorities', null, 'target', 'checks'),
    ),
    (
      'admin',
      1.3,
      (x0, x1, t, b) => promptBox(
        c,
        x0,
        x1,
        t,
        b,
        'Calls, emails & admin',
        null,
        'briefcase',
        'checks',
      ),
    ),
    (
      'habits',
      0.75,
      (b0, b1, t, b) {
        final y = card(
          c.p,
          b0,
          b,
          b1 - b0,
          t - b,
          title: 'Health & habits',
          iconKind: 'leaf',
        );
        trackerRow(c, b0 + 10, b1 - 10, y - 12, 'Water', 8, 'drop', 'circles');
        trackerRow(c, b0 + 10, b1 - 10, y - 34, 'Habits', 6);
      },
    ),
    (
      'grateful',
      0.75,
      (x0, x1, t, b) =>
          promptBox(c, x0, x1, t, b, 'Grateful for', null, 'heart'),
    ),
  ],
);

// Collection pages

void brainDump(Ctx c) => promptBox(
  c,
  c.left,
  c.right,
  c.top,
  c.bottom,
  'Everything on my mind',
  "Write it all out. Circle what matters; cross out what doesn't.",
  'cloud',
  'dots',
);

/// A big task broken into small steps, with time guesses.
void taskBreakdown(Ctx c) {
  final p = c.p;
  label(p, c.left, c.top - 12, 'Big task', size: 10, iconKind: 'target');
  p.line(c.left + 70, c.top - 14, c.right, c.top - 14);
  label(p, c.left, c.top - 40, 'Why it matters', size: 10, iconKind: 'heart');
  p.line(c.left + 104, c.top - 42, c.right, c.top - 42);
  table(
    c,
    c.left,
    c.right,
    c.top - 62,
    c.bottom + 34,
    ['#', 'Tiny step', 'Minutes', 'Done'],
    [0.07, 0.63, 0.15, 0.15],
    26,
  );
  p.text(
    c.left,
    c.bottom + 12,
    'Tip: if a step takes more than 25 minutes, break it in two.',
    8.5,
    rgb: c.s.soft,
  );
}

void linedPage(Ctx c) => lines(c.p, c.left, c.right, c.top - 10, c.bottom, 26);

void dottedPage(Ctx c) => dots(c.p, c.left, c.right, c.top - 6, c.bottom, 16);

void checklistPage(Ctx c) =>
    checks(c.p, c.left, c.right, c.top - 12, c.bottom + 6, 28);

/// Squares, for maths, sketches and tables.
void gridPage(Ctx c) {
  const gap = 18;
  for (num x = c.left; x <= c.right + 0.5; x += gap) {
    c.p.line(x, c.bottom, x, c.top - 6, rgb: tint(c.s.rule, 0.3), width: 0.5);
  }
  for (num y = c.top - 6; y >= c.bottom - 0.5; y -= gap) {
    c.p.line(c.left, y, c.right, y, rgb: tint(c.s.rule, 0.3), width: 0.5);
  }
}

void blankPage(Ctx c) {}

void therapyNotes(Ctx c) {
  final p = c.p;
  for (final (k, word) in ['Date', 'Session #'].indexed) {
    final x = c.left + k * 220;
    p.text(x, c.top - 10, word, 9, rgb: c.s.accent, bold: true);
    p.line(x + textWidth(word, 9) + 6, c.top - 12, x + 200, c.top - 12);
  }
  final top = c.top - 26;
  final cols = columns(c.left, c.right, 2, 12);
  final rws = rows(top, c.bottom, [1, 1.3, 1], 12);
  const items = [
    ('Before: what I want to talk about', 'cloud'),
    ("How I'm feeling", 'heart'), //
    ('Key takeaways', 'star'), ('Things to try', 'check'),
    ('Homework', 'pencil'), ('After: how do I feel?', 'leaf'),
  ];
  for (final (k, (name, ic)) in items.indexed) {
    final (x0, x1) = cols[k % 2];
    final (t, b) = rws[k ~/ 2];
    promptBox(
      c,
      x0,
      x1,
      t,
      b,
      name,
      null,
      ic,
      name == 'Things to try' ? 'checks' : 'lines',
    );
  }
}

void anxietyJournal(Ctx c) {
  final cols = columns(c.left, c.right, 2, 12);
  final rws = rows(c.top, c.bottom, [1, 1, 1], 12);
  const items = [
    ('What am I worried about?', 'cloud'),
    ('How likely is it, really?', 'chart'), //
    ('What can I control?', 'check'), ('What can I let go?', 'leaf'),
    ('What would I tell a friend?', 'heart'), ('One small step', 'target'),
  ];
  for (final (k, (name, ic)) in items.indexed) {
    final (x0, x1) = cols[k % 2];
    final (t, b) = rws[k ~/ 2];
    promptBox(c, x0, x1, t, b, name, null, ic);
  }
}

void selfCareMenu(Ctx c) {
  final cols = columns(c.left, c.right, c.landscape ? 3 : 2, 12);
  const items = [
    ('5 minutes', 'sun'), ('30 minutes', 'leaf'), ('An afternoon', 'heart'), //
    ("When I'm anxious", 'cloud'),
    ("When I'm low", 'moon'),
    ('People I can call', 'people'),
  ];
  final n = cols.length;
  final rws = rows(c.top, c.bottom, [
    for (var i = 0; i < (items.length + n - 1) ~/ n; i++) 1,
  ], 12);
  for (final (k, (name, ic)) in items.indexed) {
    final (x0, x1) = cols[k % n];
    final (t, b) = rws[k ~/ n];
    promptBox(c, x0, x1, t, b, name, null, ic, 'checks');
  }
}

void sleepLog(Ctx c) => table(
  c,
  c.left,
  c.right,
  c.top,
  c.bottom,
  ['Date', 'Bed', 'Up', 'Hours', 'Quality 1-5', 'Notes'],
  [0.12, 0.1, 0.1, 0.1, 0.14, 0.44],
  24,
);

void gratitude(Ctx c) {
  final cols = columns(c.left, c.right, 2, 12);
  final rws = rows(c.top, c.bottom, [1, 1, 1], 12);
  for (var k = 0; k < 6; k++) {
    final (x0, x1) = cols[k % 2];
    final (t, b) = rws[k ~/ 2];
    rrect(c.p, x0, b, x1 - x0, t - b, 8, stroke: c.s.rule);
    c.p.text(x0 + 10, t - 16, 'Date', 8, rgb: c.s.soft, bold: true);
    c.p.line(x0 + 36, t - 18, x0 + 120, t - 18);
    icon(c.p, 'heart', x1 - 16, t - 13, 11, tint(c.s.accent, 0.3));
    for (var j = 0; j < 3; j++) {
      final y = t - 40 - j * 24;
      if (y < b + 6) break;
      c.p.text(x0 + 10, y + 2, '${j + 1}.', 9, rgb: c.s.accent, bold: true);
      c.p.line(x0 + 24, y, x1 - 10, y);
    }
  }
}

void stressTracker(Ctx c) => table(
  c,
  c.left,
  c.right,
  c.top,
  c.bottom,
  ['Date', 'Stress 1-10', 'What happened', 'How I coped'],
  [0.12, 0.13, 0.4, 0.35],
  26,
);

/// One goal: why, deadline, milestones by month, action steps, progress.
void goalDashboard(Ctx c) {
  final p = c.p;
  for (final (k, word) in ['Goal', 'Deadline'].indexed) {
    final x = c.left + k * (c.right - c.left) * 0.62;
    p.text(x, c.top - 10, word, 10, rgb: c.s.accent, bold: true);
    final x1 = c.left + (c.right - c.left) * (k == 0 ? 0.58 : 1);
    p.line(x + textWidth(word, 10) + 6, c.top - 12, x1, c.top - 12);
  }
  final y = c.top - 34;
  label(p, c.left, y, 'Progress', size: 9, iconKind: 'chart');
  final seg = (c.right - c.left - 70) / 10;
  for (var k = 0; k < 10; k++) {
    rrect(p, c.left + 70 + k * seg, y - 4, seg - 3, 14, 3, stroke: c.s.rule);
    p.text(
      c.left + 70 + k * seg + seg / 2 - 1,
      y - 14,
      '${(k + 1) * 10}%',
      6,
      rgb: c.s.soft,
      center: true,
    );
  }
  final top = y - 26;
  final [(a0, a1), (b0, b1)] = columns(c.left, c.right, 2, 14);
  final [t1, t2] = rows(top, c.bottom, [1, 1.4], 12);
  promptBox(c, a0, a1, t1.$1, t1.$2, 'Why it matters', null, 'heart');
  promptBox(c, a0, a1, t2.$1, t2.$2, 'Action steps', null, 'list', 'checks');
  final yy = card(
    p,
    b0,
    c.bottom,
    b1 - b0,
    top - c.bottom,
    title: 'Milestones by month',
    iconKind: 'calendar',
  );
  final rh = (yy - c.bottom - 8) / c.book.n;
  for (var m = 0; m < c.book.n; m++) {
    final ty = yy - (m + 1) * rh;
    p.text(
      b0 + 10,
      ty + rh / 2 - 3,
      c.book.monthName(m, short: true),
      8.5,
      rgb: c.s.accent,
      bold: true,
    );
    p.link(b0 + 6, ty, 40, rh, c.book.monthMain(m));
    p.line(b0 + 46, ty + 3, b1 - 10, ty + 3);
  }
}

void projectDashboard(Ctx c) {
  final p = c.p;
  const fields = [('Project', 0.5), ('Start', 0.22), ('Due', 0.22)];
  var x = c.left;
  for (final (word, f) in fields) {
    final w = (c.right - c.left) * f;
    p.text(x, c.top - 10, word, 10, rgb: c.s.accent, bold: true);
    p.line(x + textWidth(word, 10) + 6, c.top - 12, x + w - 12, c.top - 12);
    x += w + (c.right - c.left) * 0.02;
  }
  final top = c.top - 30;
  final [(a0, a1), (b0, b1)] = columns(c.left, c.right, 2, 14);
  final [t1, t2] = rows(top, c.bottom, [0.8, 1.2], 12);
  promptBox(
    c,
    a0,
    a1,
    t1.$1,
    t1.$2,
    'Outcome',
    'What does done look like?',
    'target',
  );
  promptBox(c, a0, a1, t2.$1, t2.$2, 'Notes & links', null, 'pencil');
  card(
    p,
    b0,
    c.bottom,
    b1 - b0,
    top - c.bottom,
    title: 'Tasks',
    iconKind: 'list',
  );
  table(
    c,
    b0 + 8,
    b1 - 8,
    top - 30,
    c.bottom + 8,
    ['Task', 'Due', 'Done'],
    [0.62, 0.22, 0.16],
    24,
  );
}

/// Goal clarity: from a dream to this week's step.
void goalRoadmap(Ctx c) {
  const steps = [
    ('Dream', 'Where do I want to be in 3 years?', 'star'),
    ('This year', 'What would make this year a success?', 'target'),
    ('This quarter', 'Which milestones get me there?', 'chart'),
    ('This month', "What's the next milestone?", 'calendar'),
    ('This week', 'One step I can take now.', 'check'),
  ];
  final p = c.p;
  final rws = rows(c.top, c.bottom, [for (final _ in steps) 1], 8);
  for (final (k, (name, hint, ic)) in steps.indexed) {
    final (t, b) = rws[k];
    final indent = k * (c.landscape ? 18 : 10);
    rrect(
      p,
      c.left + indent,
      b,
      c.right - c.left - indent,
      t - b,
      10,
      fill: k.isOdd ? c.s.tab : null,
      stroke: c.s.rule,
    );
    label(p, c.left + indent + 10, t - 18, name, size: 10, iconKind: ic);
    p.text(c.left + indent + 130, t - 18, hint, 8.5, rgb: c.s.soft);
    lines(p, c.left + indent + 10, c.right - 10, t - 36, b + 8, 24);
  }
}

void quarterReview(Ctx c) => monthReview(c, const [
  ('Wins', 'star', null), ('Goals on track', 'check', null), //
  ('Goals to rethink', 'cloud', null), ('Lessons', 'leaf', null),
  ("Next quarter's focus", 'target', null), ('Celebrate', 'gift', null),
]);

void courseDashboard(Ctx c) {
  final p = c.p;
  final cols = columns(c.left, c.right, 2, 20);
  for (final (k, word) in ['Course', 'Teacher', 'Room', 'Times'].indexed) {
    final (x0, x1) = cols[k % 2];
    final y = c.top - 10 - (k ~/ 2) * 22;
    p.text(x0, y, word, 9.5, rgb: c.s.accent, bold: true);
    p.line(x0 + textWidth(word, 9.5) + 6, y - 2, x1, y - 2);
  }
  final top = c.top - 56;
  final [(a0, a1), (b0, b1)] = cols;
  card(
    p,
    a0,
    c.bottom,
    a1 - a0,
    top - c.bottom,
    title: 'Assignments & exams',
    iconKind: 'check',
  );
  table(
    c,
    a0 + 8,
    a1 - 8,
    top - 30,
    c.bottom + 8,
    ['What', 'Due', 'Grade'],
    [0.6, 0.2, 0.2],
    24,
  );
  final [t1, t2] = rows(top, c.bottom, [1, 1], 12);
  promptBox(c, b0, b1, t1.$1, t1.$2, 'Grading & syllabus notes', null, 'book');
  promptBox(
    c,
    b0,
    b1,
    t2.$1,
    t2.$2,
    'Questions for office hours',
    null,
    'cloud',
  );
}

void assignmentTracker(Ctx c) => table(
  c,
  c.left,
  c.right,
  c.top,
  c.bottom,
  ['Course', 'Assignment', 'Due', 'Status', 'Grade'],
  [0.18, 0.44, 0.13, 0.13, 0.12],
  24,
);

void examPlanner(Ctx c) {
  final cols = columns(c.left, c.right, 2, 14);
  final rws = rows(c.top, c.bottom, [1, 1], 12);
  for (var k = 0; k < 4; k++) {
    final (x0, x1) = cols[k % 2];
    final (t, b) = rws[k ~/ 2];
    final y = card(
      c.p,
      x0,
      b,
      x1 - x0,
      t - b,
      title: 'Exam ${k + 1}',
      iconKind: 'cap',
    );
    for (final (j, word) in ['Course', 'Date'].indexed) {
      c.p.text(x0 + 10 + j * 140, y - 4, word, 8.5, rgb: c.s.soft, bold: true);
      c.p.line(x0 + 50 + j * 140, y - 6, x0 + 130 + j * 140, y - 6);
    }
    checks(c.p, x0 + 10, x1 - 10, y - 30, b + 12, 24);
  }
}

void pomodoro(Ctx c) {
  table(
    c,
    c.left,
    c.right,
    c.top,
    c.bottom + 40,
    ['Date', 'Task', 'Pomodoros (25 min)'],
    [0.13, 0.45, 0.42],
    26,
  );
  c.p.text(
    c.left,
    c.bottom + 16,
    '25 minutes on, 5 off. After four, take 20.',
    8.5,
    rgb: c.s.soft,
  );
}

void gpaTracker(Ctx c) => table(
  c,
  c.left,
  c.right,
  c.top,
  c.bottom,
  ['Course', 'Credits', 'Grade', 'Points', 'Term'],
  [0.4, 0.13, 0.13, 0.13, 0.21],
  24,
);

void readingLog(Ctx c) => table(
  c,
  c.left,
  c.right,
  c.top,
  c.bottom,
  ['Title', 'Author', 'Started', 'Finished', 'Rating'],
  [0.36, 0.26, 0.13, 0.13, 0.12],
  26,
);

void classSchedule(Ctx c) {
  final p = c.p;
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
  final cols = columns(c.left + 40, c.right, 5, 4);
  for (final (k, d) in days.indexed) {
    final (x0, x1) = cols[k];
    rrect(p, x0, c.top - 22, x1 - x0, 22, 6, fill: c.s.tab);
    p.text(
      (x0 + x1) / 2,
      c.top - 15,
      d,
      9,
      rgb: c.s.accent,
      bold: true,
      center: true,
    );
  }
  final hours = [for (var h = 8; h < 19; h++) h];
  final rh = (c.top - 30 - c.bottom) / hours.length;
  for (final (k, h) in hours.indexed) {
    final y = c.top - 30 - k * rh;
    p.text(c.left, y - 12, _hour(h), 8, rgb: c.s.soft, bold: true);
    p.line(c.left + 40, y, c.right, y);
  }
  p.line(c.left + 40, c.bottom, c.right, c.bottom);
}

void yearReview(Ctx c) => monthReview(c, const [
  ('Proudest moments', 'star', null), ('Biggest lessons', 'leaf', null), //
  ("What I'll leave behind", 'cloud', null),
  ('Revenue & numbers', 'chart', null),
  ('Best clients & projects', 'people', null),
  ('Word for next year', 'target', null),
]);

void businessStrategy(Ctx c) => monthReview(c, const [
  ('Mission', 'target', 'Why does the business exist?'),
  ('Ideal client', 'people', 'Who, their problem, where they are.'),
  ('Offers & pricing', 'coin', null),
  ('Brand voice', 'pencil', 'Three words.'),
  ('Strengths & gaps', 'chart', null),
  ("This year's big moves", 'star', null),
]);

void marketingPlan(Ctx c) {
  final cols = columns(c.left, c.right, 2, 14);
  final [t1, t2] = rows(c.top, c.bottom, [1, 1.2], 12);
  promptBox(
    c,
    cols[0].$1,
    cols[0].$2,
    t1.$1,
    t1.$2,
    'Channels',
    'Where my clients are.',
    'people',
    'checks',
  );
  promptBox(
    c,
    cols[1].$1,
    cols[1].$2,
    t1.$1,
    t1.$2,
    'Content pillars',
    null,
    'list',
    'checks',
  );
  card(
    c.p,
    c.left,
    t2.$2,
    c.right - c.left,
    t2.$1 - t2.$2,
    title: 'Campaigns',
    iconKind: 'chart',
  );
  table(
    c,
    c.left + 8,
    c.right - 8,
    t2.$1 - 30,
    t2.$2 + 8,
    ['Campaign', 'Launch', 'Goal', 'Result'],
    [0.4, 0.15, 0.25, 0.2],
    24,
  );
}

void clientCard(Ctx c) {
  final p = c.p;
  final cols = columns(c.left, c.right, 2, 20);
  for (final (k, word) in [
    'Client',
    'Contact',
    'Email',
    'Phone',
    'Project',
    'Rate',
  ].indexed) {
    final (x0, x1) = cols[k % 2];
    final y = c.top - 10 - (k ~/ 2) * 24;
    p.text(x0, y, word, 9.5, rgb: c.s.accent, bold: true);
    p.line(x0 + textWidth(word, 9.5) + 6, y - 2, x1, y - 2);
  }
  final top = c.top - 84;
  final [t1, t2] = rows(top, c.bottom, [1, 1], 12);
  card(
    p,
    c.left,
    t1.$2,
    c.right - c.left,
    t1.$1 - t1.$2,
    title: 'Invoices',
    iconKind: 'coin',
  );
  table(
    c,
    c.left + 8,
    c.right - 8,
    t1.$1 - 30,
    t1.$2 + 8,
    ['Invoice', 'Sent', 'Amount', 'Paid'],
    [0.3, 0.2, 0.3, 0.2],
    24,
  );
  promptBox(c, c.left, c.right, t2.$1, t2.$2, 'Notes', null, 'pencil');
}

/// Income, spending and saving for every month of the year.
void financeOverview(Ctx c) {
  final book = c.book;
  const heads = ['Month', 'Income', 'Spending', 'Saved', 'Notes'];
  const fr = [0.14, 0.18, 0.18, 0.18, 0.32];
  final rh = (c.top - 22 - c.bottom) / (book.n + 1);
  table(c, c.left, c.right, c.top, c.bottom, heads, fr, rh);
  for (var m = 0; m < book.n; m++) {
    final y = c.top - 22 - (m + 1) * rh;
    c.p.text(
      c.left + 8,
      y + rh / 2 - 3,
      book.monthName(m, short: true),
      9,
      rgb: c.s.accent,
      bold: true,
    );
    c.p.link(c.left, y, (c.right - c.left) * fr[0], rh, book.monthMain(m));
  }
  c.p.text(
    c.left + 8,
    c.bottom + rh / 2 - 3,
    'Total',
    9,
    rgb: c.s.accent,
    bold: true,
  );
}

void savingsGoals(Ctx c) {
  final cols = columns(c.left, c.right, 2, 14);
  final rws = rows(c.top, c.bottom, [1, 1], 12);
  for (var k = 0; k < 4; k++) {
    final (x0, x1) = cols[k % 2];
    final (t, b) = rws[k ~/ 2];
    final y = card(
      c.p,
      x0,
      b,
      x1 - x0,
      t - b,
      title: 'Saving for',
      iconKind: 'coin',
    );
    c.p.line(x0 + 90, t - 20, x1 - 10, t - 20);
    final cw = (x1 - x0 - 20) / 10;
    for (var j = 0; j < 20; j++) {
      final cx = x0 + 10 + (j % 10) * cw + cw / 2;
      final cy = y - 18 - (j ~/ 10) * (cw + 2);
      final r = cw / 2 - 2 < 9 ? cw / 2 - 2 : 9;
      circle(c.p, cx, cy, r, c.s.soft, fill: false, width: 0.9);
    }
    c.p.text(x0 + 10, b + 12, r'Each circle = $ ______', 8, rgb: c.s.soft);
  }
}

void debtPayoff(Ctx c) => table(
  c,
  c.left,
  c.right,
  c.top,
  c.bottom,
  ['Debt', 'Balance', 'Rate', 'Minimum', 'Paid off by'],
  [0.32, 0.17, 0.12, 0.17, 0.22],
  26,
);

void billsTracker(Ctx c) {
  final book = c.book;
  table(
    c,
    c.left,
    c.right,
    c.top,
    c.bottom,
    [
      'Bill',
      'Due',
      for (var m = 0; m < book.n; m++) book.monthName(m, short: true),
    ],
    [0.2, 0.08, for (var m = 0; m < book.n; m++) 0.72 / book.n],
    24,
  );
}

void subscriptions(Ctx c) => table(
  c,
  c.left,
  c.right,
  c.top,
  c.bottom,
  ['Service', 'Cost', 'Renews', 'Keep?'],
  [0.45, 0.18, 0.2, 0.17],
  26,
);

void wishlist(Ctx c) => table(
  c,
  c.left,
  c.right,
  c.top,
  c.bottom,
  ['Item', 'Where', 'Price', 'Bought'],
  [0.45, 0.25, 0.15, 0.15],
  26,
);

void cleaningSchedule(Ctx c) {
  final cols = columns(c.left, c.right, c.landscape ? 4 : 2, 10);
  const items = [
    ('Daily', 'check'),
    ('Weekly', 'calendar'),
    ('Monthly', 'star'),
    ('Seasonal', 'leaf'),
  ];
  final n = cols.length;
  final rws = rows(c.top, c.bottom, [for (var i = 0; i < 4 ~/ n; i++) 1], 12);
  for (final (k, (name, ic)) in items.indexed) {
    final (x0, x1) = cols[k % n];
    final (t, b) = rws[k ~/ n];
    promptBox(c, x0, x1, t, b, name, null, ic, 'checks');
  }
}

void mealPlan(Ctx c) {
  final cols = columns(c.left, c.right, 2, 14);
  final [t1, t2] = rows(c.top, c.bottom, [1.2, 1], 12);
  card(
    c.p,
    c.left,
    t1.$2,
    c.right - c.left,
    t1.$1 - t1.$2,
    title: 'Favourite meals',
    iconKind: 'heart',
  );
  table(
    c,
    c.left + 8,
    c.right - 8,
    t1.$1 - 30,
    t1.$2 + 8,
    ['Meal', 'Ingredients', 'Time'],
    [0.3, 0.55, 0.15],
    24,
  );
  promptBox(
    c,
    cols[0].$1,
    cols[0].$2,
    t2.$1,
    t2.$2,
    'Fitness goals',
    null,
    'target',
    'checks',
  );
  promptBox(
    c,
    cols[1].$1,
    cols[1].$2,
    t2.$1,
    t2.$2,
    'Workout ideas',
    null,
    'leaf',
    'checks',
  );
}

void tripPlanner(Ctx c) {
  final p = c.p;
  for (final (k, word) in ['Destination', 'Dates'].indexed) {
    final x = c.left + k * 300;
    p.text(x, c.top - 10, word, 9.5, rgb: c.s.accent, bold: true);
    p.line(x + textWidth(word, 9.5) + 6, c.top - 12, x + 270, c.top - 12);
  }
  final top = c.top - 28;
  final cols = columns(c.left, c.right, c.landscape ? 3 : 2, 12);
  const items = [
    ('Packing list', 'check', 'checks'), ('Itinerary', 'calendar', 'lines'), //
    ('Bookings', 'plane', 'lines'), ('Budget', 'coin', 'lines'),
    ('To see & eat', 'star', 'checks'), ('Notes', 'pencil', 'lines'),
  ];
  final n = cols.length;
  final rws = rows(top, c.bottom, [
    for (var i = 0; i < (items.length + n - 1) ~/ n; i++) 1,
  ], 12);
  for (final (k, (name, ic, kind)) in items.indexed) {
    final (x0, x1) = cols[k % n];
    final (t, b) = rws[k ~/ n];
    promptBox(c, x0, x1, t, b, name, null, ic, kind);
  }
}
