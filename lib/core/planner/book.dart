/// The engine behind Jotswift's planners: a Book is months of linked pages
/// in landscape or portrait, its week starting Monday or Sunday.
///
/// A port of tool/planner_kit.py. Pages run month by month: each month's
/// pages, then each week's pages followed by that week's days. Sections
/// (collections) follow, each with its own index. Every page has a Home
/// button and a trail at the top left, arrows to the pages beside it at
/// the top right, month tabs down the right edge and section tabs along
/// the bottom. Every date on every calendar opens its day.
///
/// Unlike the Python, any of the month, week and day kinds can be empty:
/// links to pages that aren't made are left out.
library;

import 'dart:math' as math;

import 'pdf_ops.dart';

const monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];
const dayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', //
  'Sunday',
];
const kLeft = 32;
const kTabW = 30;

/// A day, at midnight UTC.
DateTime day(int y, int m, int d) => DateTime.utc(y, m, d);

DateTime addMonths(DateTime d, int n) => DateTime.utc(d.year, d.month + n);

DateTime addDays(DateTime d, int n) => DateTime.utc(d.year, d.month, d.day + n);

/// Monday is 0, as in Python.
int pyWeekday(DateTime d) => d.weekday - 1;

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}'
    '-${d.day.toString().padLeft(2, '0')}';

int daysInMonth(int y, int m) => DateTime.utc(y, m + 1, 0).day;

// Drawing helpers

/// A rounded rectangle.
void rrect(
  PlannerPage p,
  num x,
  num y,
  num w,
  num h,
  num r, {
  Rgb? fill,
  Rgb? stroke,
  num width = 0.8,
}) {
  r = math.max(0, math.min(r, math.min(w / 2, h / 2)));
  final k = 0.5523 * r;
  final path =
      '${f1(x + r)} ${f1(y)} m ${f1(x + w - r)} ${f1(y)} l '
      '${f1(x + w - r + k)} ${f1(y)} ${f1(x + w)} ${f1(y + r - k)} ${f1(x + w)} ${f1(y + r)} c '
      '${f1(x + w)} ${f1(y + h - r)} l '
      '${f1(x + w)} ${f1(y + h - r + k)} ${f1(x + w - r + k)} ${f1(y + h)} ${f1(x + w - r)} ${f1(y + h)} c '
      '${f1(x + r)} ${f1(y + h)} l '
      '${f1(x + r - k)} ${f1(y + h)} ${f1(x)} ${f1(y + h - r + k)} ${f1(x)} ${f1(y + h - r)} c '
      '${f1(x)} ${f1(y + r)} l '
      '${f1(x)} ${f1(y + r - k)} ${f1(x + r - k)} ${f1(y)} ${f1(x + r)} ${f1(y)} c h';
  if (fill != null) p.color(fill);
  if (stroke != null) {
    p.color(stroke, stroke: true);
    p.ops.add('${py(width)} w');
  }
  p.ops.add(
    '$path${fill != null && stroke != null
        ? ' B'
        : fill != null
        ? ' f'
        : ' S'}',
  );
}

void strokePath(
  PlannerPage p,
  List<(num, num)> pts,
  Rgb rgb, {
  num width = 1.2,
  bool close = false,
}) {
  p.color(rgb, stroke: true);
  final path = [
    for (final (i, (x, y)) in pts.indexed)
      '${f1(x)} ${f1(y)} ${i == 0 ? 'm' : 'l'}',
  ].join(' ');
  p.ops.add('${py(width)} w 1 J 1 j $path${close ? ' h' : ''} S');
}

/// A > (or <) centred on (x, y).
void chevron(
  PlannerPage p,
  num x,
  num y,
  num size,
  Rgb rgb, {
  bool back = false,
  num width = 1.4,
}) {
  final d = size / 2;
  final dx = back ? -d / 2 : d / 2;
  strokePath(
    p,
    [(x - dx, y + d), (x + dx, y), (x - dx, y - d)],
    rgb,
    width: width,
  );
}

/// The icons a label, tile or tab can show.
const iconKinds = [
  'home', 'calendar', 'target', 'heart', 'star', 'coin', 'book', //
  'briefcase', 'check', 'sun', 'moon', 'drop', 'bolt', 'cloud', 'list',
  'leaf', 'cap', 'chart', 'pencil', 'plane', 'people', 'gift',
];

/// A small line icon centred on (cx, cy).
void icon(PlannerPage p, String kind, num cx, num cy, num size, Rgb rgb) {
  final r = size / 2;
  final num w = math.max(0.9, size / 11);
  switch (kind) {
    case 'home':
      strokePath(p, [(cx - r, cy), (cx, cy + r), (cx + r, cy)], rgb, width: w);
      strokePath(
        p,
        [
          (cx - r * 0.7, cy + r * 0.1),
          (cx - r * 0.7, cy - r),
          (cx + r * 0.7, cy - r),
          (cx + r * 0.7, cy + r * 0.1),
        ],
        rgb,
        width: w,
      );
    case 'calendar':
      rrect(
        p,
        cx - r,
        cy - r * 0.9,
        size,
        r * 1.7,
        r * 0.2,
        stroke: rgb,
        width: w,
      );
      p.line(cx - r, cy + r * 0.35, cx + r, cy + r * 0.35, rgb: rgb, width: w);
      for (final dx in [-0.45, 0.45]) {
        p.line(
          cx + dx * r,
          cy + r * 0.6,
          cx + dx * r,
          cy + r,
          rgb: rgb,
          width: w,
        );
      }
    case 'target':
      for (final f in [1, 0.62, 0.25]) {
        circle(p, cx, cy, r * f, rgb, fill: f == 0.25, width: w);
      }
    case 'heart':
      curve(
        p,
        (cx, cy - r * 0.85),
        [
          (
            (cx - r * 1.25, cy + r * 0.05),
            (cx - r * 0.6, cy + r * 1.05),
            (cx, cy + r * 0.4),
          ),
          (
            (cx + r * 0.6, cy + r * 1.05),
            (cx + r * 1.25, cy + r * 0.05),
            (cx, cy - r * 0.85),
          ),
        ],
        rgb,
        w,
        close: true,
      );
    case 'star':
      strokePath(
        p,
        [
          for (var i = 0; i < 10; i++)
            (
              cx +
                  (i.isEven ? r : r * 0.45) *
                      math.cos(math.pi / 2 + i * math.pi / 5),
              cy +
                  (i.isEven ? r : r * 0.45) *
                      math.sin(math.pi / 2 + i * math.pi / 5),
            ),
        ],
        rgb,
        width: w,
        close: true,
      );
    case 'coin':
      circle(p, cx, cy, r, rgb, fill: false, width: w);
      p.text(
        cx,
        cy - size * 0.24,
        r'$',
        size * 0.68,
        rgb: rgb,
        bold: true,
        center: true,
      );
    case 'book':
      strokePath(
        p,
        [
          (cx, cy - r * 0.8),
          (cx - r, cy - r * 0.55),
          (cx - r, cy + r * 0.8),
          (cx, cy + r * 0.55),
          (cx + r, cy + r * 0.8),
          (cx + r, cy - r * 0.55),
          (cx, cy - r * 0.8),
          (cx, cy + r * 0.55),
        ],
        rgb,
        width: w,
      );
    case 'briefcase':
      rrect(
        p,
        cx - r,
        cy - r * 0.75,
        size,
        r * 1.35,
        r * 0.18,
        stroke: rgb,
        width: w,
      );
      strokePath(
        p,
        [
          (cx - r * 0.35, cy + r * 0.6),
          (cx - r * 0.35, cy + r * 0.9),
          (cx + r * 0.35, cy + r * 0.9),
          (cx + r * 0.35, cy + r * 0.6),
        ],
        rgb,
        width: w,
      );
      p.line(cx - r, cy + r * 0.05, cx + r, cy + r * 0.05, rgb: rgb, width: w);
    case 'check':
      strokePath(
        p,
        [
          (cx - r * 0.8, cy),
          (cx - r * 0.2, cy - r * 0.6),
          (cx + r * 0.85, cy + r * 0.65),
        ],
        rgb,
        width: w * 1.3,
      );
    case 'sun':
      circle(p, cx, cy, r * 0.42, rgb, fill: false, width: w);
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        p.line(
          cx + r * 0.65 * math.cos(a),
          cy + r * 0.65 * math.sin(a),
          cx + r * math.cos(a),
          cy + r * math.sin(a),
          rgb: rgb,
          width: w,
        );
      }
    case 'moon':
      curve(
        p,
        (cx + r * 0.2, cy + r),
        [
          (
            (cx - r * 1.1, cy + r * 0.9),
            (cx - r * 1.1, cy - r * 0.9),
            (cx + r * 0.2, cy - r),
          ),
          (
            (cx - r * 0.45, cy - r * 0.5),
            (cx - r * 0.45, cy + r * 0.5),
            (cx + r * 0.2, cy + r),
          ),
        ],
        rgb,
        w,
        close: true,
      );
    case 'drop':
      curve(
        p,
        (cx, cy + r),
        [
          (
            (cx - r * 0.2, cy + r * 0.5),
            (cx - r * 0.75, cy),
            (cx - r * 0.75, cy - r * 0.3),
          ),
          (
            (cx - r * 0.75, cy - r * 1.1),
            (cx + r * 0.75, cy - r * 1.1),
            (cx + r * 0.75, cy - r * 0.3),
          ),
          ((cx + r * 0.75, cy), (cx + r * 0.2, cy + r * 0.5), (cx, cy + r)),
        ],
        rgb,
        w,
        close: true,
      );
    case 'bolt':
      strokePath(
        p,
        [
          (cx + r * 0.2, cy + r),
          (cx - r * 0.55, cy - r * 0.1),
          (cx + r * 0.05, cy - r * 0.1),
          (cx - r * 0.2, cy - r),
          (cx + r * 0.55, cy + r * 0.15),
          (cx - r * 0.05, cy + r * 0.15),
        ],
        rgb,
        width: w,
        close: true,
      );
    case 'cloud':
      for (final (dx, dy, rr) in [
        (-0.45, -0.15, 0.42),
        (0.1, 0.18, 0.5),
        (0.5, -0.15, 0.38),
      ]) {
        circle(p, cx + dx * r, cy + dy * r, rr * r, rgb, fill: false, width: w);
      }
    case 'list':
      for (var k = 0; k < 3; k++) {
        final y = cy + r * 0.6 - k * r * 0.6;
        circle(p, cx - r * 0.75, y, r * 0.12, rgb);
        p.line(cx - r * 0.4, y, cx + r, y, rgb: rgb, width: w);
      }
    case 'leaf':
      curve(
        p,
        (cx - r, cy - r),
        [
          (
            (cx - r * 0.2, cy - r * 0.9),
            (cx + r * 0.9, cy + r * 0.2),
            (cx + r, cy + r),
          ),
          (
            (cx + r * 0.2, cy + r * 0.9),
            (cx - r * 0.9, cy - r * 0.2),
            (cx - r, cy - r),
          ),
        ],
        rgb,
        w,
        close: true,
      );
      p.line(
        cx - r,
        cy - r,
        cx + r * 0.6,
        cy + r * 0.6,
        rgb: rgb,
        width: w * 0.8,
      );
    case 'cap':
      polygon(
        p,
        [
          (cx - r, cy + r * 0.25),
          (cx, cy + r * 0.75),
          (cx + r, cy + r * 0.25),
          (cx, cy - r * 0.25),
        ],
        rgb,
        fill: false,
        width: w,
      );
      strokePath(
        p,
        [
          (cx - r * 0.55, cy),
          (cx - r * 0.55, cy - r * 0.6),
          (cx + r * 0.55, cy - r * 0.6),
          (cx + r * 0.55, cy),
        ],
        rgb,
        width: w,
      );
    case 'chart':
      strokePath(
        p,
        [(cx - r, cy + r), (cx - r, cy - r), (cx + r, cy - r)],
        rgb,
        width: w,
      );
      strokePath(
        p,
        [
          (cx - r * 0.6, cy - r * 0.3),
          (cx - r * 0.1, cy + r * 0.2),
          (cx + r * 0.25, cy - r * 0.1),
          (cx + r * 0.85, cy + r * 0.6),
        ],
        rgb,
        width: w,
      );
    case 'pencil':
      strokePath(
        p,
        [
          (cx - r, cy - r),
          (cx - r * 0.75, cy - r * 0.25),
          (cx + r * 0.6, cy + r * 1.0 - r * 0.15),
          (cx + r, cy + r * 0.45),
          (cx - r * 0.25, cy - r * 0.75),
        ],
        rgb,
        width: w,
        close: true,
      );
    case 'plane':
      polygon(
        p,
        [
          (cx - r, cy),
          (cx + r, cy + r * 0.7),
          (cx + r * 0.2, cy - r),
          (cx, cy - r * 0.15),
        ],
        rgb,
        fill: false,
        width: w,
      );
    case 'people':
      circle(
        p,
        cx - r * 0.35,
        cy + r * 0.35,
        r * 0.3,
        rgb,
        fill: false,
        width: w,
      );
      circle(
        p,
        cx + r * 0.4,
        cy + r * 0.35,
        r * 0.3,
        rgb,
        fill: false,
        width: w,
      );
      curve(
        p,
        (cx - r, cy - r),
        [
          (
            (cx - r, cy - r * 0.1),
            (cx + r * 0.3, cy - r * 0.1),
            (cx + r * 0.3, cy - r),
          ),
        ],
        rgb,
        w,
      );
      curve(
        p,
        (cx + r * 0.05, cy - r * 0.2),
        [
          (
            (cx + r * 0.6, cy - r * 0.1),
            (cx + r, cy - r * 0.3),
            (cx + r, cy - r),
          ),
        ],
        rgb,
        w,
      );
    case 'gift':
      rrect(p, cx - r, cy - r, size, r * 1.3, r * 0.1, stroke: rgb, width: w);
      p.line(cx, cy - r, cx, cy + r * 0.3, rgb: rgb, width: w);
      p.line(cx - r, cy - r * 0.2, cx + r, cy - r * 0.2, rgb: rgb, width: w);
      circle(
        p,
        cx - r * 0.3,
        cy + r * 0.55,
        r * 0.25,
        rgb,
        fill: false,
        width: w,
      );
      circle(
        p,
        cx + r * 0.3,
        cy + r * 0.55,
        r * 0.25,
        rgb,
        fill: false,
        width: w,
      );
    default: // a dot
      circle(p, cx, cy, r * 0.4, rgb);
  }
}

/// A section label, in the accent colour, with an optional icon.
void label(
  PlannerPage p,
  num x,
  num y,
  String text, {
  num size = 10,
  String? iconKind,
}) {
  if (iconKind != null) {
    icon(
      p,
      iconKind,
      x + size * 0.55,
      y + size * 0.35,
      size * 1.1,
      p.style.accent,
    );
    x += size * 1.6;
  }
  p.text(x, y, text, size, rgb: p.style.accent, bold: true);
}

void lines(PlannerPage p, num x0, num x1, num top, num bottom, [num gap = 24]) {
  var y = top;
  while (y >= bottom - 0.5) {
    p.line(x0, y, x1, y);
    y -= gap;
  }
}

/// Checkbox lines from [top] down to [bottom].
void checks(
  PlannerPage p,
  num x0,
  num x1,
  num top,
  num bottom, [
  num gap = 24,
]) {
  var y = top;
  while (y >= bottom - 0.5) {
    rrect(p, x0, y - 1, 10, 10, 2, stroke: p.style.soft, width: 0.9);
    p.line(x0 + 17, y - 2, x1, y - 2);
    y -= gap;
  }
}

void dots(PlannerPage p, num x0, num x1, num top, num bottom, [num gap = 14]) {
  var y = top;
  while (y >= bottom) {
    var x = x0;
    while (x <= x1) {
      p.rect(x - 0.45, y - 0.45, 0.9, 0.9, fill: p.style.soft);
      x += gap;
    }
    y -= gap;
  }
}

/// A rounded box with an optional title; returns the y below the title.
num card(
  PlannerPage p,
  num x,
  num y,
  num w,
  num h, {
  String? title,
  String? iconKind,
  bool fill = false,
}) {
  rrect(
    p,
    x,
    y,
    w,
    h,
    8,
    fill: fill ? p.style.tab : null,
    stroke: p.style.rule,
    width: 0.9,
  );
  if (title != null) {
    label(p, x + 10, y + h - 18, title, size: 10, iconKind: iconKind);
    return y + h - 30;
  }
  return y + h - 10;
}

/// [n] circles to colour in (a 1-n rating).
num scale(
  PlannerPage p,
  num x,
  num y,
  int n, {
  num size = 11,
  List<String>? labels,
}) {
  for (var k = 0; k < n; k++) {
    final cx = x + k * (size * 1.6) + size / 2;
    circle(p, cx, y, size / 2, p.style.soft, fill: false, width: 0.9);
    if (labels != null) {
      p.text(cx, y - size - 3, labels[k], 6, rgb: p.style.soft, center: true);
    }
  }
  return x + n * size * 1.6;
}

List<(num, num)> columns(num left, num right, int n, [num gap = 16]) {
  final w = (right - left - gap * (n - 1)) / n;
  return [
    for (var k = 0; k < n; k++)
      (left + k * (w + gap), left + k * (w + gap) + w),
  ];
}

/// Splits top..bottom into rows by [weights]; (top, bottom) pairs.
List<(num, num)> rows(num top, num bottom, List<num> weights, [num gap = 12]) {
  final total = weights.fold<num>(0, (a, b) => a + b);
  final span = top - bottom - gap * (weights.length - 1);
  final out = <(num, num)>[];
  var y = top;
  for (final wgt in weights) {
    final h = span * wgt / total;
    out.add((y, y - h));
    y -= h + gap;
  }
  return out;
}

// The book

typedef PageBody = void Function(Ctx c);

/// A kind of page under a month, week or day: [name] shows on its chip
/// and in its title; [group] is what the builder can leave out.
class PageKind {
  const PageKind(this.name, this.draw, this.group);

  final String name;
  final PageBody draw;
  final String group;
}

/// A page after the year page: (name, icon, body, group).
typedef FrontPage = (String name, String icon, PageBody body, String group);

/// A section with an index page and its [pages]: (name, body) pairs.
class Collection {
  Collection(
    this.key,
    this.title,
    this.icon,
    this.group,
    this.pages, [
    this.blurb = '',
  ]);

  final String key, title, icon, group;
  final List<(String, PageBody)> pages;
  final String blurb;
  int index = -1;
  List<int> pageIds = const [];
}

/// Where a body draws, and what about.
class Ctx {
  Ctx(
    this.book,
    this.p,
    this.left,
    this.right,
    this.top,
    this.bottom, {
    this.m,
    this.w,
    this.d,
    this.k,
  });

  final Book book;
  final PlannerPage p;
  final num left, right, top, bottom;

  /// The month, week, day and item indexes, as they apply.
  final int? m, w, d, k;

  bool get landscape => p.w > p.h;
  PlannerStyle get s => p.style;
}

class _Rec {
  _Rec(
    this.section,
    this.title,
    this.group,
    this.draw, [
    this.first,
    this.last,
  ]);

  final String section, title, group;
  final void Function(PlannerPage p) draw;
  final DateTime? first, last;
}

class Book {
  /// [start]: the first day (dated), or null for an undated book.
  /// [weekStart]: 0 for Monday, 6 for Sunday.
  Book(
    this.title,
    this.subtitle,
    this.start, {
    required this.style,
    this.width = 792,
    this.height = 612,
    this.weekStart = 0,
    this.front = const [],
    required this.monthKinds,
    required this.weekKinds,
    required this.dayKinds,
    this.collections = const [],
    this.hint = '',
    int months = 12,
  }) : n = start != null ? months : 12 {
    final start = this.start;
    if (start != null) {
      this.months = [for (var i = 0; i < n; i++) addMonths(start, i)];
      final end = addMonths(start, n);
      this.end = addDays(end, -1);
      final count = end.difference(start).inHours ~/ 24;
      _days = [for (var i = 0; i < count; i++) addDays(start, i)];
      var first = addDays(start, -((pyWeekday(start) - weekStart) % 7));
      _weeks = [];
      while (first.isBefore(end)) {
        _weeks.add(first);
        first = addDays(first, 7);
      }
      for (final (i, d) in _days.indexed) {
        _dayIndex[d] = i;
      }
    } else {
      end = null;
      this.months = const [];
      _uDays = [
        for (var m = 0; m < 12; m++)
          for (var d = 1; d < 32; d++) (m, d),
      ];
      _uWeeks = [
        for (var m = 0; m < 12; m++)
          for (var r = 0; r < 5; r++) (m, r),
      ];
    }
    _plan();
  }

  final String title, subtitle;
  final DateTime? start;
  late final DateTime? end;
  final PlannerStyle style;

  /// Page size in points.
  final int width, height;
  final int weekStart;
  final List<FrontPage> front;
  final List<PageKind> monthKinds, weekKinds, dayKinds;
  final List<Collection> collections;
  final String hint;

  /// How many months.
  final int n;

  /// The first day of each month (dated).
  late final List<DateTime> months;

  bool get dated => start != null;

  List<DateTime> _days = const [];
  List<DateTime> _weeks = const [];
  List<(int, int)> _uDays = const [];
  List<(int, int)> _uWeeks = const [];
  final _dayIndex = <DateTime, int>{};

  int get dayCount => dated ? _days.length : _uDays.length;
  int get weekCount => dated ? _weeks.length : _uWeeks.length;

  final _recs = <_Rec>[];
  late final int home, yearPage;
  late final List<int> frontPages;
  late final List<List<int?>> monthPage, weekPage, dayPage;

  num get W => width;
  num get H => height;
  bool get landscape => width > height;

  // Where things are

  void _plan() {
    int add(
      String section,
      String title,
      String group,
      void Function(PlannerPage) draw, [
      DateTime? first,
      DateTime? last,
    ]) {
      _recs.add(_Rec(section, title, group, draw, first, last));
      return _recs.length - 1;
    }

    home = add('Start', 'Home', 'start', drawHome);
    yearPage = dated
        ? add('Start', yearName(), 'start', drawYear, start, end)
        : add('Start', yearName(), 'start', drawYear);
    frontPages = [
      for (final (k, (name, _, _, group)) in front.indexed)
        add('Start', name, group, (p) => drawFront(p, k)),
    ];
    monthPage = [
      for (var m = 0; m < n; m++) List<int?>.filled(monthKinds.length, null),
    ];
    weekPage = [
      for (var w = 0; w < weekCount; w++)
        List<int?>.filled(weekKinds.length, null),
    ];
    dayPage = [
      for (var d = 0; d < dayCount; d++)
        List<int?>.filled(dayKinds.length, null),
    ];
    final weekDone = List.filled(weekCount, false);
    for (var m = 0; m < n; m++) {
      final section = monthName(m);
      for (final (s, kind) in monthKinds.indexed) {
        final period = s == 0 ? monthPeriod(m) : null;
        final title = s == 0
            ? monthName(m)
            : '${monthName(m, short: true)} ${kind.name.toLowerCase()}';
        monthPage[m][s] = add(
          section,
          title,
          s > 0 ? kind.group : 'months',
          (p) => drawMonthKind(p, m, s),
          period?.$1,
          period?.$2,
        );
      }
      for (final d in daysOfMonth(m)) {
        final w = weekOf(d);
        if (w != null && !weekDone[w]) {
          weekDone[w] = true;
          for (final (s, kind) in weekKinds.indexed) {
            final period = s == 0 ? weekPeriod(w) : null;
            final title = s == 0
                ? weekName(w)
                : '${weekName(w)} ${kind.name.toLowerCase()}';
            weekPage[w][s] = add(
              section,
              title,
              kind.group,
              (p) => drawWeekKind(p, w, s),
              period?.$1,
              period?.$2,
            );
          }
        }
        for (final (s, kind) in dayKinds.indexed) {
          final date = dated && s == 0 ? _days[d] : null;
          final title = s == 0
              ? dayTitle(d)
              : '${dayTitle(d)} ${kind.name.toLowerCase()}';
          dayPage[d][s] = add(
            section,
            title,
            kind.group,
            (p) => drawDayKind(p, d, s),
            date,
            date,
          );
        }
      }
    }
    for (final c in collections) {
      c.index = add(
        c.title,
        c.title,
        c.group,
        (p) => drawCollectionIndex(p, c),
      );
      c.pageIds = [
        for (final (k, (name, _)) in c.pages.indexed)
          add(c.title, name, c.group, (p) => drawCollectionPage(p, c, k)),
      ];
    }
  }

  int get pageCount => _recs.length;

  int? monthMain(int m) => monthPage[m].firstOrNull;
  int? weekMain(int w) => weekPage[w].firstOrNull;
  int? dayMain(int d) => dayPage[d].firstOrNull;

  List<int> daysOfMonth(int m) {
    if (dated) {
      final first = months[m];
      final last = addMonths(first, 1);
      return [
        for (var i = 0; i < last.difference(first).inHours ~/ 24; i++)
          ?_dayIndex[addDays(first, i)],
      ];
    }
    return [for (var d = m * 31; d < m * 31 + 31; d++) d];
  }

  /// The week holding day index [d].
  int? weekOf(int d) {
    if (dated) {
      final i = (_days[d].difference(_weeks.first).inHours ~/ 24) ~/ 7;
      return 0 <= i && i < _weeks.length ? i : null;
    }
    final (m, n) = _uDays[d];
    return m * 5 + (n - 1) ~/ 7;
  }

  /// The (dated) days of week [w].
  List<DateTime> weekDates(int w) => [
    for (var k = 0; k < 7; k++) addDays(_weeks[w], k),
  ];

  /// The (undated) day indexes of week [w].
  List<int> _uWeekDays(int w) {
    final (m, r) = _uWeeks[w];
    return [
      for (var k = 0; k < 7; k++)
        if (r * 7 + k < 31) m * 31 + r * 7 + k,
    ];
  }

  /// (label, sub, page or null) for each day of week [w].
  List<(String, String, int?)> weekDayPages(int w) {
    if (dated) {
      return [
        for (final d in weekDates(w))
          (
            dayNames[pyWeekday(d)],
            '${monthNames[d.month - 1].substring(0, 3)} ${d.day}',
            switch (_dayIndex[d]) {
              final i? => dayMain(i),
              null => null,
            },
          ),
      ];
    }
    final days = _uWeekDays(w);
    final names = weekdayNames();
    return [
      for (var k = 0; k < 7; k++)
        (names[k], '', k < days.length ? dayMain(days[k]) : null),
    ];
  }

  List<String> weekdayNames() => [
    ...dayNames.sublist(weekStart),
    ...dayNames.sublist(0, weekStart),
  ];

  int monthOfWeek(int w) {
    if (dated) {
      for (final d in weekDates(w)) {
        if (_dayIndex[d] case final i?) return monthOfDay(i);
      }
      return n - 1;
    }
    return _uWeeks[w].$1;
  }

  int monthOfDay(int d) {
    if (dated) {
      final day = _days[d];
      return (day.year - start!.year) * 12 + day.month - start!.month;
    }
    return _uDays[d].$1;
  }

  /// Day index of day [n] of month [m], or null.
  int? dayOfMonth(int m, int n) {
    if (dated) {
      final first = months[m];
      if (n > daysInMonth(first.year, first.month)) return null;
      return _dayIndex[day(first.year, first.month, n)];
    }
    return m * 31 + n - 1;
  }

  // Names and periods

  String yearName() {
    if (!dated) return 'Year';
    if (start!.year == end!.year) return '${start!.year}';
    return '${start!.year}-${'${end!.year}'.substring(2)}';
  }

  /// January, or Jan; with the year (Dec 26, December 2026) when the book
  /// has that month twice.
  String monthName(int m, {bool short = false}) {
    if (!dated) return short ? 'M${m + 1}' : 'Month ${m + 1}';
    final first = months[m];
    final name = monthNames[first.month - 1];
    final twice = months.where((d) => d.month == first.month).length > 1;
    if (short) {
      return twice
          ? '${name.substring(0, 3)} ${'${first.year}'.substring(2)}'
          : name.substring(0, 3);
    }
    return twice ? '$name ${first.year}' : name;
  }

  String monthTitle(int m) => dated
      ? '${monthNames[months[m].month - 1]} ${months[m].year}'
      : 'Month ${m + 1}';

  (DateTime, DateTime)? monthPeriod(int m) {
    if (!dated) return null;
    final first = months[m];
    return (first, addDays(addMonths(first, 1), -1));
  }

  (DateTime, DateTime)? weekPeriod(int w) =>
      dated ? (_weeks[w], addDays(_weeks[w], 6)) : null;

  String weekName(int w) => 'Week ${w + 1}';

  String weekRange(int w) {
    if (!dated) return 'Week of  ______________';
    final (a, b) = (_weeks[w], addDays(_weeks[w], 6));
    return '${monthNames[a.month - 1].substring(0, 3)} ${a.day} - '
        '${monthNames[b.month - 1].substring(0, 3)} ${b.day}, ${b.year}';
  }

  String dayTitle(int d) {
    if (dated) {
      final day = _days[d];
      return '${monthNames[day.month - 1].substring(0, 3)} ${day.day}';
    }
    final (m, n) = _uDays[d];
    return 'M${m + 1} day $n';
  }

  String dayCrumb(int d) {
    if (dated) {
      final day = _days[d];
      return '${dayNames[pyWeekday(day)].substring(0, 3)} ${day.day}';
    }
    return 'Day ${_uDays[d].$2}';
  }

  // The frame on every page

  num get right => W - kTabW - 16;

  /// Home button and trail at the top, arrows, month tabs on the right and
  /// section tabs along the bottom. [crumbs]: (label, page) after Home;
  /// the last is this page.
  void frame(
    PlannerPage p,
    List<(String, int?)> crumbs, {
    Object? tab,
    int? prev,
    int? next,
    String? bottomTab,
  }) {
    final s = p.style;
    rrect(p, kLeft, H - 44, 26, 26, 7, fill: s.accent);
    icon(p, 'home', kLeft + 13, H - 31, 13, s.onAccent);
    p.link(kLeft - 4, H - 48, 34, 34, home);
    num x = kLeft + 36;
    final y = H - 35;
    for (final (k, (name, target)) in crumbs.indexed) {
      if (k > 0) {
        chevron(p, x + 2, y + 3, 6, s.soft, width: 1);
        x += 9;
      }
      final last = k == crumbs.length - 1;
      p.text(x, y, name, 9.5, rgb: last ? s.ink : s.accent, bold: last);
      final w = textWidth(name, 9.5);
      if (!last) p.link(x - 3, y - 10, w + 6, 26, target);
      x += w + 5;
    }
    final r = right;
    for (final (page, back, cx) in [
      (prev, true, r - 44),
      (next, false, r - 12),
    ]) {
      if (page == null) continue;
      rrect(p, cx - 13, H - 44, 26, 26, 7, fill: s.tab);
      chevron(p, cx, H - 31, 10, s.accent, back: back, width: 1.6);
      p.link(cx - 15, H - 48, 30, 34, page);
    }
    p.shared(() => monthTabs(p, tab));
    p.shared(() => bottomTabs(p, bottomTab));
  }

  void monthTabs(PlannerPage p, Object? current) {
    final s = p.style;
    final entries = <(String, int?, Object)>[
      (dated && yearName().length <= 4 ? yearName() : 'Year', yearPage, 'year'),
      for (var m = 0; m < n; m++) (monthName(m, short: true), monthMain(m), m),
    ];
    final x = W - kTabW - 4;
    final (top, bottom, gap) = (H - 18, 34, 3);
    final h = (top - bottom - gap * (entries.length - 1)) / entries.length;
    for (final (k, (name, target, key)) in entries.indexed) {
      final y = top - (k + 1) * h - k * gap;
      final on = key == current;
      rrect(p, x, y, kTabW + 12, h, 6, fill: on ? s.accent : s.tab);
      final ink = on ? s.onAccent : s.accent;
      if (name.contains(' ')) {
        // Dec 26: the year small, under the month
        final [mon, yy] = name.split(' ');
        p.text(
          x + kTabW / 2,
          y + h / 2 + 0.5,
          mon,
          8,
          rgb: ink,
          bold: true,
          center: true,
        );
        p.text(
          x + kTabW / 2,
          y + h / 2 - 8,
          "'$yy",
          6.5,
          rgb: ink,
          center: true,
        );
      } else {
        final size = name.length > 3 ? 7.5 : 8.5;
        p.text(
          x + kTabW / 2,
          y + h / 2 - size * 0.35,
          name,
          size,
          rgb: ink,
          bold: true,
          center: true,
        );
      }
      p.link(x, y, kTabW + 4, h, target);
    }
  }

  void bottomTabs(PlannerPage p, String? current) {
    if (collections.isEmpty) return;
    final s = p.style;
    final n = collections.length;
    const gap = 4;
    final w = math.min<num>(118, (right - kLeft - gap * (n - 1)) / n);
    num x = kLeft;
    for (final c in collections) {
      final on = c.key == current;
      rrect(p, x, -8, w, 30, 6, fill: on ? s.accent : s.tab);
      final ink = on ? s.onAccent : s.accent;
      final name = c.title;
      num size = 8;
      while (textWidth(name, size) > w - 26 && size > 6) {
        size -= 0.5;
      }
      icon(p, c.icon, x + 11, 11, 9, ink);
      p.text(x + 20, 8, name, size, rgb: ink, bold: true);
      p.link(x, 0, w, 24, c.index);
      x += w + gap;
    }
  }

  void heading(PlannerPage p, String text, {String? sub, num size = 24}) {
    header(p, kLeft, H - 80, text, size);
    if (sub != null) p.text(kLeft, H - 98, sub, 10, rgb: p.style.soft);
  }

  /// Linked chips at the top right, for the pages of one month, week or
  /// day; smaller when they'd run into the page's [title].
  void chips(
    PlannerPage p,
    List<String> names,
    List<int?> pages,
    int current, [
    String title = '',
  ]) {
    if (names.length < 2) return;
    final s = p.style;
    final after = kLeft + textWidth(title, 24) + 14;
    late List<num> widths;
    late num x, size;
    late num gap;
    for (final (sz, pad, least, gp) in [
      (8.5, 18, 46, 4),
      (7.5, 12, 36, 3),
      (6.5, 8, 28, 2),
    ]) {
      size = sz;
      gap = gp;
      widths = [
        for (final n in names) math.max<num>(least, textWidth(n, sz) + pad),
      ];
      x =
          right -
          widths.fold<num>(0, (a, b) => a + b) -
          gp * (names.length - 1);
      if (x >= after) break;
    }
    final y = H - 88;
    for (final (k, name) in names.indexed) {
      final (page, w) = (pages[k], widths[k]);
      final on = k == current;
      rrect(p, x, y, w, 22, 11, fill: on ? s.accent : s.tab);
      p.text(
        x + w / 2,
        y + 7.5,
        name,
        size,
        rgb: on ? s.onAccent : s.accent,
        bold: true,
        center: true,
      );
      if (!on) p.link(x, y, w, 22, page);
      x += w + gap;
    }
  }

  Ctx ctx(PlannerPage p, {int? m, int? w, int? d, int? k}) =>
      Ctx(this, p, kLeft, right, H - 112, 36, m: m, w: w, d: d, k: k);

  List<(String, int?)> crumbsMonth(int m) => [
    (yearName(), yearPage),
    (monthName(m), monthMain(m)),
  ];

  // Calendars

  /// Rows of 7 cells for month [m]: dates (dated) or day numbers (undated,
  /// 1-31 in five rows).
  List<List<Object>> monthWeeks(int m) {
    if (dated) {
      final first = months[m];
      final last = day(
        first.year,
        first.month,
        daysInMonth(first.year, first.month),
      );
      var d = addDays(first, -((pyWeekday(first) - weekStart) % 7));
      final out = <List<Object>>[];
      while (!d.isAfter(last)) {
        out.add([for (var k = 0; k < 7; k++) addDays(d, k)]);
        d = addDays(d, 7);
      }
      return out;
    }
    return [
      for (var r = 0; r < 5; r++) [for (var k = 0; k < 7; k++) r * 7 + k + 1],
    ];
  }

  /// The day index for a calendar cell of month [m], or null.
  int? cellDay(int m, Object cell) {
    if (cell is DateTime) {
      if (cell.month != months[m].month) return null;
      return _dayIndex[cell];
    }
    final n = cell as int;
    return n <= 31 ? m * 31 + n - 1 : null;
  }

  int? rowWeek(int m, int r, List<Object> row) {
    if (dated) {
      for (final d in row) {
        if (_dayIndex[d] case final i?) return weekOf(i);
      }
      return null;
    }
    return m * 5 + r;
  }

  /// Month [m] as a small grid whose dates open their days. Returns the
  /// bottom.
  num miniMonth(
    PlannerPage p,
    int m,
    num x,
    num top,
    num w,
    num rowH,
    num size, {
    int? today,
    bool weekLinks = false,
    bool title = true,
  }) {
    final s = p.style;
    if (title) {
      p.text(x, top, monthName(m), size + 1, rgb: s.accent, bold: true);
      p.link(x - 2, top - 4, w * 0.6, size + 8, monthMain(m));
      top -= size + 6;
    }
    final cols = weekLinks ? 8 : 7;
    final cw = w / cols;
    final x0 = x + (weekLinks ? cw : 0);
    if (dated) {
      for (final (k, name) in weekdayNames().indexed) {
        p.text(
          x0 + k * cw + cw / 2,
          top,
          name[0],
          size - 1,
          rgb: s.soft,
          center: true,
        );
      }
    }
    var y = top;
    for (final (r, row) in monthWeeks(m).indexed) {
      y = top - (r + 1) * rowH;
      if (weekLinks) {
        final wi = rowWeek(m, r, row);
        if (wi != null) {
          p.text(
            x + cw / 2,
            y,
            'W${wi + 1}',
            size - 1.5,
            rgb: s.accent,
            bold: true,
            center: true,
          );
          p.link(x, y - rowH * 0.3, cw, rowH, weekMain(wi));
        }
      }
      for (final (k, cell) in row.indexed) {
        final i = cellDay(m, cell);
        if (i == null) continue;
        final n = cell is DateTime ? cell.day : cell as int;
        final cx = x0 + k * cw + cw / 2;
        if (i == today) {
          circle(p, cx, y + size * 0.33, size * 0.85, s.accent);
          p.text(cx, y, '$n', size, rgb: s.onAccent, bold: true, center: true);
        } else {
          p.text(cx, y, '$n', size, center: true);
        }
        p.link(cx - cw / 2, y - rowH * 0.3, cw, rowH, dayMain(i));
      }
    }
    return y - rowH * 0.3;
  }

  // Pages

  void drawHome(PlannerPage p) {
    final s = p.style;
    final r = right;
    rrect(p, kLeft, H - 120, r - kLeft, 96, 14, fill: s.accent);
    p.text(kLeft + 22, H - 70, title, 30, rgb: s.onAccent, bold: true);
    p.text(kLeft + 22, H - 94, subtitle, 12, rgb: tint(s.onAccent, 0.0));
    if (dated) {
      p.text(
        r - 22,
        H - 70,
        yearName(),
        30,
        rgb: s.onAccent,
        bold: true,
        right: true,
      );
    }
    num y = H - 142;
    final tiles = <(String, String?, int?)>[
      ('Year', 'calendar', yearPage),
      for (final (k, (name, ic, _, _)) in front.indexed)
        (name, ic, frontPages[k]),
      for (final c in collections) (c.title, c.icon, c.index),
    ];
    final perRow = landscape ? 6 : 4;
    final th = landscape ? 50 : 62;
    y = tileGrid(p, y, 'Start here', tiles, perRow, th, icons: true);
    final monthTiles = <(String, String?, int?)>[
      for (var m = 0; m < n; m++) (monthName(m), null, monthMain(m)),
    ];
    y = tileGrid(
      p,
      y,
      'Months',
      monthTiles,
      landscape ? 6 : 4,
      landscape ? 30 : 38,
    );
    if (weekKinds.isNotEmpty) {
      final weeks = <(String, String?, int?)>[
        for (var w = 0; w < weekCount; w++) ('${w + 1}', null, weekMain(w)),
      ];
      final per = landscape ? 20 : 14;
      final nRows = (weeks.length + per - 1) ~/ per;
      final th = math.min<num>(26, (y - 64 - 8 * nRows) / nRows);
      if (th >= 16) tileGrid(p, y, 'Weeks', weeks, per, th);
    }
    final tip = hint.isNotEmpty
        ? hint
        : 'Tap any date, tab or tile with your finger to go there. The Pencil always writes.';
    p.text(kLeft, 44, tip, 9, rgb: s.soft);
    p.text(
      kLeft,
      32,
      "Tap Today at the top of the screen to open today's page.",
      9,
      rgb: s.soft,
    );
    monthTabs(p, null);
    bottomTabs(p, null);
  }

  num tileGrid(
    PlannerPage p,
    num y,
    String heading,
    List<(String, String?, int?)> items,
    int perRow,
    num h, {
    bool icons = false,
  }) {
    final s = p.style;
    label(p, kLeft, y, heading, size: 11);
    y -= 10;
    const gap = 8;
    final w = (right - kLeft - gap * (perRow - 1)) / perRow;
    for (final (k, (name, ic, target)) in items.indexed) {
      final (r, c) = (k ~/ perRow, k % perRow);
      final (x, ty) = (kLeft + c * (w + gap), y - (r + 1) * h - r * gap);
      rrect(p, x, ty, w, h, 9, fill: s.tab);
      num size = 10.5;
      while (textWidth(name, size) > w - (icons && ic != null ? 30 : 12) &&
          size > 7) {
        size -= 0.5;
      }
      if (icons && ic != null) {
        icon(
          p,
          ic,
          x + w / 2,
          ty + h * 0.62,
          math.min<num>(16, h * 0.32),
          s.accent,
        );
        p.text(
          x + w / 2,
          ty + h * 0.2,
          name,
          size,
          rgb: s.accent,
          bold: true,
          center: true,
        );
      } else {
        p.text(
          x + w / 2,
          ty + h / 2 - size * 0.35,
          name,
          size,
          rgb: s.accent,
          bold: true,
          center: true,
        );
      }
      p.link(x, ty, w, h, target);
    }
    final n = (items.length + perRow - 1) ~/ perRow;
    return y - n * (h + gap) - 22;
  }

  void drawYear(PlannerPage p) {
    heading(
      p,
      dated ? yearName() : 'Year at a glance',
      sub: 'Tap a month, a week number or any date.',
    );
    final cols = landscape ? (n <= 12 ? 4 : 5) : 3;
    final nRows = (n + cols - 1) ~/ cols;
    final (top, bottom) = (H - 108, 36);
    final (gw, gh) = ((right - kLeft) / cols, (top - bottom) / nRows);
    for (var m = 0; m < n; m++) {
      final (cx, cy) = (kLeft + (m % cols) * gw, top - (m ~/ cols + 1) * gh);
      rrect(p, cx + 4, cy + 4, gw - 8, gh - 8, 8, stroke: p.style.rule);
      miniMonth(
        p,
        m,
        cx + 12,
        cy + gh - 20,
        gw - 24,
        math.min<num>(15, (gh - 44) / 6.4),
        7.5,
        weekLinks: true,
      );
    }
    frame(p, [(yearName(), yearPage)], tab: 'year');
  }

  void drawFront(PlannerPage p, int k) {
    final (name, _, body, _) = front[k];
    heading(p, name);
    body(ctx(p, k: k));
    final pages = frontPages;
    frame(
      p,
      [(name, pages[k])],
      tab: 'year',
      prev: k > 0 ? pages[k - 1] : yearPage,
      next: k + 1 < pages.length ? pages[k + 1] : null,
    );
  }

  void drawMonthKind(PlannerPage p, int m, int s) {
    final kind = monthKinds[s];
    final title = s == 0
        ? monthTitle(m)
        : '${monthName(m)} ${kind.name.toLowerCase()}';
    heading(p, title);
    chips(p, [for (final k in monthKinds) k.name], monthPage[m], s, title);
    p.shared(() => kind.draw(ctx(p, m: m)));
    final crumbs = crumbsMonth(m);
    if (s > 0) crumbs.add((kind.name, monthPage[m][s]));
    frame(
      p,
      crumbs,
      tab: m,
      prev: m > 0 ? monthPage[m - 1][s] : null,
      next: m < n - 1 ? monthPage[m + 1][s] : null,
    );
  }

  void drawWeekKind(PlannerPage p, int w, int s) {
    final kind = weekKinds[s];
    final m = monthOfWeek(w);
    final name = weekName(w);
    heading(
      p,
      s == 0 ? name : '$name ${kind.name.toLowerCase()}',
      sub: weekRange(w),
    );
    chips(p, [for (final k in weekKinds) k.name], weekPage[w], s);
    kind.draw(ctx(p, m: m, w: w));
    final crumbs = [...crumbsMonth(m), (name, weekMain(w))];
    if (s > 0) crumbs.add((kind.name, weekPage[w][s]));
    frame(
      p,
      crumbs,
      tab: m,
      prev: w > 0 ? weekPage[w - 1][s] : null,
      next: w + 1 < weekCount ? weekPage[w + 1][s] : null,
    );
  }

  void drawDayKind(PlannerPage p, int d, int s) {
    final kind = dayKinds[s];
    final m = monthOfDay(d);
    String title, sub;
    if (dated) {
      final day = _days[d];
      title = dayNames[pyWeekday(day)];
      sub = '${monthNames[day.month - 1]} ${day.day}, ${day.year}';
    } else {
      title = 'Day ${_uDays[d].$2}';
      sub = 'Date  ______________';
    }
    if (s > 0) title = '$title · ${kind.name}';
    heading(p, title, sub: sub);
    chips(p, [for (final k in dayKinds) k.name], dayPage[d], s);
    final w = weekOf(d);
    p.shared(() => kind.draw(ctx(p, m: m, d: d, w: w)));
    final crumbs = crumbsMonth(m);
    if (w != null) crumbs.add((weekName(w), weekMain(w)));
    crumbs.add((dayCrumb(d), dayMain(d)));
    if (s > 0) crumbs.add((kind.name, dayPage[d][s]));
    frame(
      p,
      crumbs,
      tab: m,
      prev: d > 0 ? dayPage[d - 1][s] : null,
      next: d + 1 < dayCount ? dayPage[d + 1][s] : null,
    );
  }

  void drawCollectionIndex(PlannerPage p, Collection c) {
    final s = p.style;
    heading(
      p,
      c.title,
      sub: c.blurb.isNotEmpty ? c.blurb : 'Tap a line to open its page.',
    );
    final (top, bottom) = (H - 112, 40);
    final n = c.pages.length;
    final cols = n > (landscape ? 10 : 16) ? 2 : 1;
    final per = (n + cols - 1) ~/ cols;
    final rh = per == 0 ? 40 : math.min<num>(40, (top - bottom) / per);
    for (final (k, (name, _)) in c.pages.indexed) {
      final (col, r) = (k ~/ per, k % per);
      final (x0, x1) = columns(kLeft, right, cols, 24)[col];
      final y = top - (r + 1) * rh;
      p.text(x0, y + 8, '${k + 1}', 10, rgb: s.accent, bold: true);
      p.text(x0 + 24, y + 8, name, 11);
      chevron(p, x1 - 6, y + 11, 8, s.accent);
      p.line(x0 + 20, y + 3, x1, y + 3);
      p.link(x0, y, x1 - x0, rh, c.pageIds[k]);
    }
    frame(p, [(c.title, c.index)], bottomTab: c.key);
  }

  void drawCollectionPage(PlannerPage p, Collection c, int k) {
    final (name, body) = c.pages[k];
    heading(p, name);
    p.shared(() => body(ctx(p, k: k)));
    final ids = c.pageIds;
    frame(
      p,
      [(c.title, c.index), (name, ids[k])],
      prev: k > 0 ? ids[k - 1] : null,
      next: k + 1 < ids.length ? ids[k + 1] : null,
      bottomTab: c.key,
    );
  }

  // Output

  /// Draws page [i] alone, for a preview; its links point nowhere useful.
  PlannerPage drawPage(int i) {
    final p = PlannerPage(style, width, height);
    _recs[i].draw(p);
    return p;
  }

  /// Every page, with [onProgress] called now and then.
  List<PlannerPage> build({void Function(int done, int total)? onProgress}) {
    final pages = <PlannerPage>[];
    for (final (i, rec) in _recs.indexed) {
      final p = PlannerPage(style, width, height);
      rec.draw(p);
      pages.add(p);
      if (i % 50 == 0) onProgress?.call(i, _recs.length);
    }
    return pages;
  }

  /// The template spec (template.json) for the pages [build] makes.
  Map<String, Object?> spec() {
    final sections = <Map<String, Object?>>[];
    for (final (i, rec) in _recs.indexed) {
      if (sections.isEmpty || sections.last['title'] != rec.section) {
        sections.add({'title': rec.section, 'pages': <Map<String, Object?>>[]});
      }
      final e = <String, Object?>{'pdfPage': i + 1, 'title': rec.title};
      if (rec.group != 'start' && rec.group != 'months') e['group'] = rec.group;
      if (rec.first case final first?) {
        e['from'] = isoDate(first);
        e['to'] = isoDate(rec.last ?? first);
      }
      (sections.last['pages']! as List).add(e);
    }
    return {'mode': 'notebook', 'sections': sections};
  }

  /// Index of the first page in [section] (for previews).
  int? firstPageIn(String group) {
    for (final (i, rec) in _recs.indexed) {
      if (rec.group == group) return i;
    }
    return null;
  }
}
