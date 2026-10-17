import 'package:flutter/foundation.dart';

import 'catalog_item.dart';
import 'template_spec.dart';

/// One planner design and its editions: the same planner for different
/// dates (2026, Oct 2026 - Dec 2027, 2027, undated), each its own listing.
/// People choose the planner, then its dates.
@immutable
class PlannerSeries {
  const PlannerSeries({
    required this.key,
    required this.name,
    required this.editions,
  });

  /// The editions' shared id, without the dates (`autumn_planner`).
  final String key;

  /// The planner's name without dates ("Autumn Planner").
  final String name;

  /// Oldest dates first; undated last.
  final List<CatalogItem> editions;

  /// The edition a new notebook starts as on [today], among those [usable]
  /// (any, when none is): the one with today in it that runs longest, else
  /// the next one to start, else the undated one.
  CatalogItem defaultEdition(
    DateTime today, {
    bool Function(CatalogItem)? usable,
  }) {
    final pool = usable == null
        ? editions
        : [
            for (final e in editions)
              if (usable(e)) e,
          ];
    final from = pool.isEmpty ? editions : pool;
    final day = DateTime(today.year, today.month, today.day);
    final current = [
      for (final e in from)
        if (editionDates(e) case final r?
            when !day.isBefore(r.from) && !day.isAfter(r.to))
          (e, r),
    ]..sort((a, b) => b.$2.to.compareTo(a.$2.to));
    if (current.isNotEmpty) return current.first.$1;
    final upcoming = [
      for (final e in from)
        if (editionDates(e) case final r? when r.from.isAfter(day)) (e, r),
    ]..sort((a, b) => a.$2.from.compareTo(b.$2.from));
    if (upcoming.isNotEmpty) return upcoming.first.$1;
    return from.where((e) => editionDates(e) == null).firstOrNull ?? from.last;
  }
}

final _edition = RegExp(r'^(.+?)_(\d{4})(?:_(\d{2}))?$|^(.+?)_undated$');
final _range = RegExp(r'([A-Z][a-z]{2}) (\d{4}) - ([A-Z][a-z]{2}) (\d{4})');
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// The series [item] belongs to: its id without the dates.
String seriesKey(CatalogItem item) {
  final m = _edition.firstMatch(item.id);
  return m?.group(1) ?? m?.group(4) ?? item.id;
}

/// [name] without its dates: "Autumn Planner Oct 2026 - Dec 2027" and
/// "Autumn 2027 Planner" are both "Autumn Planner".
String undatedName(String name) => name
    .replaceAll(_range, '')
    .replaceAll(RegExp(r'\(undated\)', caseSensitive: false), '')
    .replaceAll(RegExp(r'\b\d{4}(-\d{2})?\b'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// [item]'s planner's name, without the dates of its edition.
String plannerName(CatalogItem item) =>
    editionLabel(item) == null ? item.name : undatedName(item.name);

/// The days an edition covers, read from its id and name; null if undated.
/// A school year ("2026-27") counts from July.
({DateTime from, DateTime to})? editionDates(CatalogItem item) {
  if (_range.firstMatch(item.name) case final r?) {
    final from = DateTime(int.parse(r[2]!), _months.indexOf(r[1]!) + 1);
    final to = DateTime(int.parse(r[4]!), _months.indexOf(r[3]!) + 2, 0);
    return (from: from, to: to);
  }
  final m = _edition.firstMatch(item.id);
  if (m == null || m.group(2) == null) return null;
  final year = int.parse(m.group(2)!);
  if (m.group(3) != null) {
    return (from: DateTime(year, 7), to: DateTime(year + 1, 6, 30));
  }
  return (from: DateTime(year), to: DateTime(year, 12, 31));
}

/// A short name for an edition's dates: "2027", "Oct 2026 – Dec 2027",
/// "2026–27", "Undated"; null for a planner with no editions.
String? editionLabel(CatalogItem item) {
  if (_range.firstMatch(item.name) case final r?) {
    return '${r[1]} ${r[2]} – ${r[3]} ${r[4]}';
  }
  final m = _edition.firstMatch(item.id);
  if (m == null) return null;
  if (m.group(4) != null) return 'Undated';
  return m.group(3) == null ? m.group(2) : '${m.group(2)}–${m.group(3)}';
}

/// A planner's dates in a few words, for a card: its edition's dates, or
/// that there are several to pick from; null for a planner without dates.
String? datesSummary(List<CatalogItem> editions) => editions.length > 1
    ? editions.any((e) => editionDates(e) == null)
          ? 'Dated or undated'
          : 'Pick your dates'
    : editionLabel(editions.single);

/// Planners (templates made as whole notebooks) grouped by design, in the
/// order each design first appears in [items]. Other items are left out.
List<PlannerSeries> plannerSeries(Iterable<CatalogItem> items) {
  final byKey = <String, List<CatalogItem>>{};
  for (final item in items) {
    if (item.kind != CatalogKind.template ||
        item.templateMode != TemplateMode.notebook) {
      continue;
    }
    (byKey[seriesKey(item)] ??= []).add(item);
  }
  return [
    for (final MapEntry(:key, value: editions) in byKey.entries)
      PlannerSeries(
        key: key,
        name: plannerName(editions.first),
        editions: editions.toList()..sort(_byDates),
      ),
  ];
}

int _byDates(CatalogItem a, CatalogItem b) {
  final (da, db) = (editionDates(a), editionDates(b));
  if (da == null || db == null) {
    return (da == null ? 1 : 0) - (db == null ? 1 : 0);
  }
  final c = da.from.compareTo(db.from);
  return c != 0 ? c : da.to.compareTo(db.to);
}

/// The other editions of [item]'s planner among [items], [item] included,
/// in date order; just [item] if it has none.
List<CatalogItem> editionsOf(CatalogItem item, Iterable<CatalogItem> items) =>
    plannerSeries(items)
        .where((s) => s.key == seriesKey(item))
        .firstOrNull
        ?.editions ??
    [item];

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', //
  'August', 'September', 'October', 'November', 'December',
];

/// "October 2026".
String monthYear(DateTime d) => '${_monthNames[d.month - 1]} ${d.year}';
