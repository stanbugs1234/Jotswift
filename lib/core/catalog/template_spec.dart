import 'dart:convert';

import 'package:flutter/foundation.dart';

/// How a template is used: as a whole notebook (a planner), or as pages to
/// add one at a time.
enum TemplateMode { notebook, pages }

/// One PDF page offered by a template, with its title.
typedef TemplatePage = ({int pdfPage, String title});

/// A template's `template.json`.
///
/// ```jsonc
/// // A planner: every PDF page becomes a notebook page, in sections.
/// {"mode": "notebook", "sections": [
///   {"title": "Months", "pages": [{"pdfPage": 2, "title": "January"}]}]}
/// // Single pages to add to any notebook.
/// {"mode": "pages", "pages": [{"pdfPage": 1, "title": "To-do list"}]}
/// ```
@immutable
class TemplateSpec {
  const TemplateSpec(this.mode, this.sections);

  /// Reads `template.json`. Entries without a page number are skipped.
  factory TemplateSpec.fromJson(Uint8List bytes) {
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    List<TemplatePage> pages(Object? list) => [
      for (final p in (list as List? ?? const []).whereType<Map>())
        if (p['pdfPage'] case final int n)
          (pdfPage: n, title: p['title'] as String? ?? ''),
    ];
    if (json['mode'] == 'notebook') {
      return TemplateSpec(TemplateMode.notebook, [
        for (final s
            in (json['sections'] as List? ?? const []).whereType<Map>())
          (title: s['title'] as String? ?? 'Pages', pages: pages(s['pages'])),
      ]);
    }
    return TemplateSpec(TemplateMode.pages, [
      (title: 'Pages', pages: pages(json['pages'])),
    ]);
  }

  final TemplateMode mode;
  final List<({String title, List<TemplatePage> pages})> sections;

  List<TemplatePage> get pages => [for (final s in sections) ...s.pages];
}
