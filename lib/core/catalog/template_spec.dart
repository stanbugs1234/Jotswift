import 'dart:convert';

import 'package:flutter/foundation.dart';

/// How a template is used: as a whole notebook (a planner), or as pages to
/// add one at a time.
enum TemplateMode { notebook, pages }

/// One PDF page offered by a template, with its title.
typedef TemplatePage = ({int pdfPage, String title});

/// A colourway of a template: the same pages in another PDF of its pack.
typedef TemplateVariant = ({String name, String file, int? color});

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
  const TemplateSpec(this.mode, this.sections, {this.variants = const []});

  /// Reads `template.json`. Entries without a page number are skipped.
  factory TemplateSpec.fromJson(Uint8List bytes) {
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    List<TemplatePage> pages(Object? list) => [
      for (final p in (list as List? ?? const []).whereType<Map>())
        if (p['pdfPage'] case final int n)
          (pdfPage: n, title: p['title'] as String? ?? ''),
    ];
    final variants = <TemplateVariant>[
      for (final v in (json['variants'] as List? ?? const []).whereType<Map>())
        if ((v['name'], v['file']) case (final String name, final String file))
          (name: name, file: file, color: _hex(v['color'])),
    ];
    if (json['mode'] == 'notebook') {
      return TemplateSpec(TemplateMode.notebook, variants: variants, [
        for (final s
            in (json['sections'] as List? ?? const []).whereType<Map>())
          (title: s['title'] as String? ?? 'Pages', pages: pages(s['pages'])),
      ]);
    }
    return TemplateSpec(TemplateMode.pages, variants: variants, [
      (title: 'Pages', pages: pages(json['pages'])),
    ]);
  }

  static int? _hex(Object? s) =>
      s is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(s)
      ? 0xFF000000 | int.parse(s.substring(1), radix: 16)
      : null;

  /// Colourways to choose from when making a notebook; empty for templates
  /// with one look.
  final List<TemplateVariant> variants;

  final TemplateMode mode;
  final List<({String title, List<TemplatePage> pages})> sections;

  List<TemplatePage> get pages => [for (final s in sections) ...s.pages];
}
