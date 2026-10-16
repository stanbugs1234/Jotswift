import 'package:flutter/material.dart';

import '../../core/catalog/catalog_item.dart';

/// What the template pickers show: a search and one category.
class TemplateFilter {
  const TemplateFilter({this.query = '', this.category});

  final String query;

  /// A catalog category, or null for every category.
  final String? category;

  bool get isEmpty => query.trim().isEmpty && category == null;

  /// Whether [item] is in the category and every word of the search is in
  /// its name, category or tags.
  bool matches(CatalogItem item) {
    if (category != null && item.category != category) return false;
    final text = [
      item.name,
      ?item.category,
      ...item.tags,
    ].join(' ').toLowerCase();
    return query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .every(text.contains);
  }

  TemplateFilter copyWith({String? query, String? Function()? category}) =>
      TemplateFilter(
        query: query ?? this.query,
        category: category == null ? this.category : category(),
      );
}

/// The template categories, in the order the pickers and the store show
/// them, with their names. Every picker uses these, so a category looks the
/// same wherever it appears.
const templateCategories = {
  'planners': 'Planners',
  'productivity': 'Productivity',
  'spreads': 'Spread planners',
  'diaries': 'Diaries',
  'journals': 'Journals',
  'study': 'Study',
  'wellness': 'Wellness',
  'lifestyle': 'Lifestyle',
  'creative': 'Creative',
  'pages': 'Basics',
};

/// The name of a catalog category, e.g. "pages" → "Basics"; one this
/// version doesn't know is capitalized.
String categoryLabel(String category) =>
    templateCategories[category] ??
    (category.isEmpty
        ? category
        : category[0].toUpperCase() + category.substring(1));

/// Sorts categories in the order of [templateCategories], unknown ones
/// last by name.
int compareCategories(String a, String b) {
  final known = templateCategories.keys.toList();
  final (i, j) = (known.indexOf(a), known.indexOf(b));
  if (i >= 0 && j >= 0) return i - j;
  if (i >= 0) return -1;
  if (j >= 0) return 1;
  return a.compareTo(b);
}

/// A search box and a row of category chips for [templates]. Shows the
/// chips only when there's more than one category.
class TemplateFilterBar extends StatefulWidget {
  const TemplateFilterBar({
    required this.templates,
    required this.filter,
    required this.onChanged,
    super.key,
  });

  final List<CatalogItem> templates;
  final TemplateFilter filter;
  final ValueChanged<TemplateFilter> onChanged;

  @override
  State<TemplateFilterBar> createState() => _TemplateFilterBarState();
}

class _TemplateFilterBarState extends State<TemplateFilterBar> {
  late final _search = TextEditingController(text: widget.filter.query);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = widget.filter;
    final categories = <String>{
      for (final t in widget.templates) ?t.category,
    }.toList()..sort(compareCategories);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          onTapOutside: (_) => FocusScope.of(context).unfocus(),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search),
            hintText: 'Search templates',
            border: const OutlineInputBorder(),
            suffixIcon: filter.query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _search.clear();
                      widget.onChanged(filter.copyWith(query: ''));
                    },
                  ),
          ),
          onChanged: (q) => widget.onChanged(filter.copyWith(query: q)),
        ),
        if (categories.length > 1) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final c in [null, ...categories])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(c == null ? 'All' : categoryLabel(c)),
                      selected: filter.category == c,
                      onSelected: (_) =>
                          widget.onChanged(filter.copyWith(category: () => c)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
