import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../features/notebooks/domain/page_period.dart';

/// How a template is used: as a whole notebook (a planner), or as pages to
/// add one at a time.
enum TemplateMode { notebook, pages }

/// One PDF page offered by a template, with its title, for planners the
/// dates it covers, and the group the planner builder can leave out.
typedef TemplatePage = ({
  int pdfPage,
  String title,
  PagePeriod? period,
  String? group,
});

/// Another PDF of a template's pack: a colourway, or for planners with
/// [TemplateSpec.options] one combination of them (e.g. portrait, weeks
/// from Sunday), with its own page list in [spec] when the pages differ.
typedef TemplateVariant = ({
  String name,
  String file,
  int? color,
  Map<String, String> options,
  String? spec,
});

/// A choice the planner builder offers, like the layout or the first day
/// of the week.
typedef TemplateOption = ({
  String id,
  String title,
  List<({String id, String name})> choices,
});

/// Pages the planner builder can leave out (daily check-ins, a
/// collection...). [on]: whether it's in by default.
typedef TemplateGroup = ({String id, String title, bool optional, bool on});

/// A template's `template.json`.
///
/// ```jsonc
/// // A planner: every PDF page becomes a notebook page, in sections.
/// {"mode": "notebook", "sections": [
///   {"title": "Months", "pages": [{"pdfPage": 2, "title": "January",
///     "from": "2027-01-01", "to": "2027-01-31"}]}]}
/// // A planner with a builder: options pick a variant (each with its own
/// // page list), and optional groups of pages can be left out.
/// {"mode": "notebook", "sections": [...],
///  "options": [{"id": "layout", "title": "Layout", "choices": [
///    {"id": "landscape", "name": "Landscape"}, {"id": "portrait", ...}]}],
///  "groups": [{"id": "checkin", "title": "Daily check-ins",
///    "optional": true, "on": true}],
///  "variants": [{"name": "Portrait", "file": "template_portrait.pdf",
///    "spec": "template_portrait.json", "options": {"layout": "portrait"}}]}
/// // Single pages to add to any notebook.
/// {"mode": "pages", "pages": [{"pdfPage": 1, "title": "To-do list"}]}
/// ```
@immutable
class TemplateSpec {
  const TemplateSpec(
    this.mode,
    this.sections, {
    this.variants = const [],
    this.options = const [],
    this.groups = const [],
  });

  /// Reads `template.json`. Entries without a page number are skipped.
  factory TemplateSpec.fromJson(Uint8List bytes) {
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final variants = <TemplateVariant>[
      for (final v in (json['variants'] as List? ?? const []).whereType<Map>())
        if ((v['name'], v['file']) case (final String name, final String file))
          (
            name: name,
            file: file,
            color: _hex(v['color']),
            options: {
              for (final MapEntry(:key, :value)
                  in (v['options'] as Map? ?? const {}).entries)
                if ((key, value) case (final String k, final String v)) k: v,
            },
            spec: v['spec'] as String?,
          ),
    ];
    final options = <TemplateOption>[
      for (final o in (json['options'] as List? ?? const []).whereType<Map>())
        if ((o['id'], o['title']) case (final String id, final String title))
          (
            id: id,
            title: title,
            choices: [
              for (final c
                  in (o['choices'] as List? ?? const []).whereType<Map>())
                if ((c['id'], c['name']) case (
                  final String id,
                  final String name,
                ))
                  (id: id, name: name),
            ],
          ),
    ];
    final groups = <TemplateGroup>[
      for (final g in (json['groups'] as List? ?? const []).whereType<Map>())
        if ((g['id'], g['title']) case (final String id, final String title))
          (
            id: id,
            title: title,
            optional: g['optional'] != false,
            on: g['on'] != false,
          ),
    ];
    if (json['mode'] == 'notebook') {
      return TemplateSpec(
        TemplateMode.notebook,
        _sections(json),
        variants: variants,
        options: options,
        groups: groups,
      );
    }
    return TemplateSpec(TemplateMode.pages, variants: variants, [
      (title: 'Pages', pages: _pages(json['pages'])),
    ]);
  }

  /// This planner with the page list of a variant's own spec file (which
  /// holds just its "sections").
  TemplateSpec withSectionsFrom(Uint8List bytes) => TemplateSpec(
    mode,
    _sections(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>),
    variants: variants,
    options: options,
    groups: groups,
  );

  static List<({String title, List<TemplatePage> pages})> _sections(
    Map<String, dynamic> json,
  ) => [
    for (final s in (json['sections'] as List? ?? const []).whereType<Map>())
      (title: s['title'] as String? ?? 'Pages', pages: _pages(s['pages'])),
  ];

  static List<TemplatePage> _pages(Object? list) => [
    for (final p in (list as List? ?? const []).whereType<Map>())
      if (p['pdfPage'] case final int n)
        (
          pdfPage: n,
          title: p['title'] as String? ?? '',
          period: PagePeriod.fromMap(p),
          group: p['group'] as String?,
        ),
  ];

  static int? _hex(Object? s) =>
      s is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(s)
      ? 0xFF000000 | int.parse(s.substring(1), radix: 16)
      : null;

  /// Colourways to choose from when making a notebook, or with [options],
  /// one PDF per combination of them; empty for templates with one look.
  final List<TemplateVariant> variants;

  /// The planner builder's choices; each picks among [variants].
  final List<TemplateOption> options;

  /// Groups of pages; the builder offers to leave out optional ones.
  final List<TemplateGroup> groups;

  /// The variant matching [chosen] options (default choices for any not
  /// given), or null without [options].
  TemplateVariant? variantFor(Map<String, String> chosen) {
    if (options.isEmpty) return null;
    final want = {
      for (final o in options)
        o.id: chosen[o.id] ?? o.choices.firstOrNull?.id ?? '',
    };
    return variants
        .where((v) => want.entries.every((e) => v.options[e.key] == e.value))
        .firstOrNull;
  }

  /// The optional groups that are off unless the user turns them on.
  Set<String> get defaultSkipped => {
    for (final g in groups)
      if (g.optional && !g.on) g.id,
  };

  /// How many pages would be made (see [made]).
  int pageCount({Set<String> skip = const {}, DateTime? from}) =>
      made(skip: skip, from: from).fold(0, (n, s) => n + s.pages.length);

  /// The sections and pages made of this planner, leaving out the groups
  /// in [skip] and sections left empty.
  ///
  /// Started [from] a day, dated pages that end before it are left out (a
  /// week that runs into it stays), with the undated pages that follow
  /// them in their section, like a month's goals after the month.
  /// [datedOnly] leaves out sections with no dated pages (notes, lists).
  List<({String title, List<TemplatePage> pages})> made({
    Set<String> skip = const {},
    DateTime? from,
    bool datedOnly = false,
  }) => [
    for (final s in sections)
      if (!datedOnly || s.pages.any((p) => p.period?.to != null))
        if (_from(s.pages, from) case final pages
            when pages.any((p) => !skip.contains(p.group)))
          (
            title: s.title,
            pages: [
              for (final p in pages)
                if (!skip.contains(p.group)) p,
            ],
          ),
  ];

  static List<TemplatePage> _from(List<TemplatePage> pages, DateTime? from) {
    if (from == null) return pages;
    final kept = <TemplatePage>[];
    var before = false;
    for (final p in pages) {
      if (p.period?.to case final to?) before = to.isBefore(from);
      if (!before) kept.add(p);
    }
    return kept;
  }

  /// Where a new copy of this planner starts on [today]: this month if
  /// the planner has it, otherwise null, for all of it.
  DateTime? startFor(DateTime today) {
    final month = DateTime(today.year, today.month);
    return months.contains(month) && month != months.first ? month : null;
  }

  /// The months a dated planner has a month page for, in order: where it
  /// can start. Empty for undated planners.
  List<DateTime> get months {
    final found = <DateTime>{};
    for (final p in pages) {
      final (from, to) = (p.period?.from, p.period?.to);
      if (from != null &&
          to != null &&
          from.day == 1 &&
          to == DateTime(from.year, from.month + 1, 0)) {
        found.add(from);
      }
    }
    return found.toList()..sort();
  }

  final TemplateMode mode;
  final List<({String title, List<TemplatePage> pages})> sections;

  List<TemplatePage> get pages => [for (final s in sections) ...s.pages];
}
