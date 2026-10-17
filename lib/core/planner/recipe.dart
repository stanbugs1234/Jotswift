import 'dart:isolate';
import 'dart:typed_data';

import 'book.dart';
import 'page_kinds.dart';
import 'pages.dart' show Prompt;
import 'pdf_ops.dart';

/// A kind of page in a planner: under each month, week or day, or at the
/// front. [name] overrides the kind's own (on chips and titles).
class KindRef {
  const KindRef(this.kind, {this.name, this.group, this.prompts});

  factory KindRef.fromMap(Map<String, Object?> m) => KindRef(
    m['kind'] as String? ?? 'lined',
    name: m['name'] as String?,
    group: m['group'] as String?,
    prompts: _prompts(m['prompts']),
  );

  final String kind;
  final String? name;

  /// What the builder groups it as; the kind's id if null.
  final String? group;

  /// The boxes on a review page, if not the kind's own.
  final List<Prompt>? prompts;

  PageKindInfo get info => kindOf(kind);
  String get title => name ?? info.name;
  String get groupId => group ?? kind;

  KindRef copyWith({String? name}) =>
      KindRef(kind, name: name ?? this.name, group: group, prompts: prompts);

  Map<String, Object?> toMap() => {
    'kind': kind,
    'name': ?name,
    'group': ?group,
    if (prompts case final p?)
      'prompts': [
        for (final (n, i, h) in p) [n, i, h],
      ],
  };
}

List<Prompt>? _prompts(Object? raw) => raw is List
    ? [
        for (final p in raw.whereType<List>())
          (
            p[0] as String,
            p.length > 1 ? p[1] as String? : null,
            p.length > 2 ? p[2] as String? : null,
          ),
      ]
    : null;

/// [count] pages of one kind in a section, named [name] (and numbered
/// when there's more than one).
class PageRun {
  const PageRun(this.kind, this.name, [this.count = 1]);

  factory PageRun.fromMap(Map<String, Object?> m) => PageRun(
    m['kind'] as String? ?? 'lined',
    m['name'] as String? ?? '',
    (m['count'] as num?)?.toInt() ?? 1,
  );

  final String kind;
  final String name;
  final int count;

  PageRun copyWith({String? name, int? count}) =>
      PageRun(kind, name ?? this.name, count ?? this.count);

  List<String> get names =>
      count == 1 ? [name] : [for (var k = 0; k < count; k++) '$name ${k + 1}'];

  Map<String, Object?> toMap() => {'kind': kind, 'name': name, 'count': count};
}

/// A section after the months: an index page, then its pages.
class SectionRecipe {
  const SectionRecipe({
    required this.key,
    required this.title,
    this.icon = 'list',
    this.blurb = '',
    this.runs = const [],
  });

  factory SectionRecipe.fromMap(Map<String, Object?> m) => SectionRecipe(
    key: m['key'] as String? ?? 'section',
    title: m['title'] as String? ?? 'Section',
    icon: m['icon'] as String? ?? 'list',
    blurb: m['blurb'] as String? ?? '',
    runs: [
      for (final r in (m['runs'] as List? ?? const []).whereType<Map>())
        PageRun.fromMap(r.cast()),
    ],
  );

  final String key, title, icon, blurb;
  final List<PageRun> runs;

  int get pageCount => runs.fold(1, (n, r) => n + r.count);

  SectionRecipe copyWith({String? title, String? icon, List<PageRun>? runs}) =>
      SectionRecipe(
        key: key,
        title: title ?? this.title,
        icon: icon ?? this.icon,
        blurb: blurb,
        runs: runs ?? this.runs,
      );

  Map<String, Object?> toMap() => {
    'key': key,
    'title': title,
    'icon': icon,
    if (blurb.isNotEmpty) 'blurb': blurb,
    'runs': [for (final r in runs) r.toMap()],
  };
}

/// Everything that makes a planner: its look, dates and pages. The planner
/// builder edits one; the engine turns it into a PDF.
class PlannerRecipe {
  const PlannerRecipe({
    required this.title,
    this.subtitle = '',
    this.style = const PlannerStyle(),
    this.collectionId,
    this.landscape = true,
    this.start,
    this.months = 12,
    this.weekStart = 0,
    this.front = const [],
    this.month = const [],
    this.week = const [],
    this.day = const [],
    this.sections = const [],
  });

  factory PlannerRecipe.fromMap(Map<String, Object?> m) {
    List<KindRef> refs(String key) => [
      for (final r in (m[key] as List? ?? const []).whereType<Map>())
        KindRef.fromMap(r.cast()),
    ];
    return PlannerRecipe(
      title: m['title'] as String? ?? 'My Planner',
      subtitle: m['subtitle'] as String? ?? '',
      style: PlannerStyle.fromMap((m['style'] as Map?)?.cast() ?? const {}),
      collectionId: m['collectionId'] as String?,
      landscape: m['landscape'] != false,
      start: switch (m['start']) {
        final String s => _firstOfMonth(DateTime.tryParse(s)),
        _ => null,
      },
      months: (m['months'] as num?)?.toInt() ?? 12,
      weekStart: (m['weekStart'] as num?)?.toInt() ?? 0,
      front: refs('front'),
      month: refs('month'),
      week: refs('week'),
      day: refs('day'),
      sections: [
        for (final s in (m['sections'] as List? ?? const []).whereType<Map>())
          SectionRecipe.fromMap(s.cast()),
      ],
    );
  }

  final String title, subtitle;
  final PlannerStyle style;

  /// The collection whose look [style] came from, for its cover and theme.
  final String? collectionId;
  final bool landscape;

  /// The first month; null for an undated planner.
  final DateTime? start;
  final int months;

  /// 0 for Monday, 6 for Sunday.
  final int weekStart;
  final List<KindRef> front, month, week, day;
  final List<SectionRecipe> sections;

  bool get dated => start != null;

  PlannerRecipe copyWith({
    String? title,
    String? subtitle,
    PlannerStyle? style,
    String? Function()? collectionId,
    bool? landscape,
    DateTime? Function()? start,
    int? months,
    int? weekStart,
    List<KindRef>? front,
    List<KindRef>? month,
    List<KindRef>? week,
    List<KindRef>? day,
    List<SectionRecipe>? sections,
  }) => PlannerRecipe(
    title: title ?? this.title,
    subtitle: subtitle ?? this.subtitle,
    style: style ?? this.style,
    collectionId: collectionId != null ? collectionId() : this.collectionId,
    landscape: landscape ?? this.landscape,
    start: start != null ? start() : this.start,
    months: months ?? this.months,
    weekStart: weekStart ?? this.weekStart,
    front: front ?? this.front,
    month: month ?? this.month,
    week: week ?? this.week,
    day: day ?? this.day,
    sections: sections ?? this.sections,
  );

  Map<String, Object?> toMap() => {
    'title': title,
    if (subtitle.isNotEmpty) 'subtitle': subtitle,
    'style': style.toMap(),
    'collectionId': ?collectionId,
    'landscape': landscape,
    if (start case final s?) 'start': isoDate(s),
    'months': months,
    'weekStart': weekStart,
    'front': [for (final r in front) r.toMap()],
    'month': [for (final r in month) r.toMap()],
    'week': [for (final r in week) r.toMap()],
    'day': [for (final r in day) r.toMap()],
    'sections': [for (final s in sections) s.toMap()],
  };

  /// The book this recipe makes.
  Book book() => Book(
    title,
    subtitle,
    start,
    style: style,
    width: landscape ? 792 : 612,
    height: landscape ? 612 : 792,
    weekStart: weekStart,
    months: months,
    front: [
      for (final r in front)
        (r.title, r.info.icon, r.info.body(r.prompts), r.groupId),
    ],
    monthKinds: [
      for (final r in month)
        PageKind(r.title, r.info.body(r.prompts), r.groupId),
    ],
    weekKinds: [
      for (final r in week)
        PageKind(r.title, r.info.body(r.prompts), r.groupId),
    ],
    dayKinds: [
      for (final r in day) PageKind(r.title, r.info.body(r.prompts), r.groupId),
    ],
    collections: [
      for (final s in sections)
        Collection(s.key, s.title, s.icon, s.key, [
          for (final r in s.runs)
            for (final name in r.names) (name, kindOf(r.kind).draw),
        ], s.blurb),
    ],
  );

  /// How many pages it makes, without drawing them.
  int get pageCount => book().pageCount;

  /// The groups of pages, for the template spec: (id, title).
  List<(String, String)> get groups {
    final out = <String, String>{};
    for (final r in [...front, ...month.skip(1), ...week, ...day]) {
      out.putIfAbsent(r.groupId, () => r.info.groupTitle);
    }
    for (final s in sections) {
      out.putIfAbsent(s.key, () => s.title);
    }
    return [for (final e in out.entries) (e.key, e.value)];
  }
}

DateTime? _firstOfMonth(DateTime? d) =>
    d == null ? null : DateTime.utc(d.year, d.month);

/// A planner made from a recipe: its PDF and template spec.
typedef MadePlanner = ({Uint8List pdf, Map<String, Object?> spec, int pages});

/// Makes [recipe]'s PDF and spec. Slow for a dated planner with day pages
/// (a second or two); see [makePlannerInBackground].
MadePlanner makePlanner(PlannerRecipe recipe) {
  final book = recipe.book();
  final pages = book.build();
  final spec = book.spec();
  spec['groups'] = [
    for (final (id, title) in recipe.groups)
      {'id': id, 'title': title, 'optional': true, 'on': true},
  ];
  spec['recipe'] = recipe.toMap();
  return (pdf: writePdf(pages, recipe.style), spec: spec, pages: pages.length);
}

Future<MadePlanner> makePlannerInBackground(PlannerRecipe recipe) {
  final map = recipe.toMap();
  return Isolate.run(() => makePlanner(PlannerRecipe.fromMap(map)));
}

/// One page of [recipe] as a PDF of its own, to show it: the first page
/// of [group] (a kind's group, a section's key, or "home"/"year").
Uint8List previewPage(PlannerRecipe recipe, String group) {
  final book = recipe.book();
  final i = switch (group) {
    'home' => book.home,
    'year' => book.yearPage,
    'months' => book.monthMain(0) ?? book.home,
    _ => book.firstPageIn(group) ?? book.home,
  };
  final page = book.drawPage(i)..links.clear();
  return writePdf([page], recipe.style);
}
