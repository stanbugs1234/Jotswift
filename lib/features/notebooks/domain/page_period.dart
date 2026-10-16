import 'package:flutter/foundation.dart';

/// The days a planner page covers: a range of dates (a day, a week, a
/// month, a year), or a month of any year (undated planners such as
/// Budget). Used to open a planner on today's page.
@immutable
class PagePeriod {
  PagePeriod.dates(DateTime from, DateTime to)
    : from = _day(from),
      to = _day(to),
      month = null;

  const PagePeriod.month(int this.month) : from = null, to = null;

  /// Reads `{"from": "2027-10-11", "to": "2027-10-17"}` or `{"month": 10}`.
  /// Anything else, including bad dates, gives null.
  static PagePeriod? fromMap(Object? map) {
    if (map is! Map) return null;
    if (map['month'] case final int m when m >= 1 && m <= 12) {
      return PagePeriod.month(m);
    }
    final from = _parse(map['from']), to = _parse(map['to']);
    if (from == null || to == null || to.isBefore(from)) return null;
    return PagePeriod.dates(from, to);
  }

  final DateTime? from;
  final DateTime? to;

  /// 1-12 when the page is for that month in any year.
  final int? month;

  bool includes(DateTime day) {
    if (month case final m?) return day.month == m;
    final d = _day(day);
    return !d.isBefore(from!) && !d.isAfter(to!);
  }

  /// How many days it spans, so the narrowest page can win.
  int get length => month != null ? 31 : to!.difference(from!).inDays + 1;

  /// Days from [day] to the nearest day this covers (0 when it includes
  /// it). Month-only periods count from the same month this year.
  int distanceTo(DateTime day) {
    final d = _day(day);
    final (start, end) = switch (month) {
      final m? => (DateTime(d.year, m), DateTime(d.year, m + 1, 0)),
      null => (from!, to!),
    };
    if (d.isBefore(start)) return start.difference(d).inDays;
    if (d.isAfter(end)) return d.difference(end).inDays;
    return 0;
  }

  Map<String, Object> toMap() => switch (month) {
    final m? => {'month': m},
    null => {'from': _format(from!), 'to': _format(to!)},
  };

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime? _parse(Object? s) {
    if (s is! String) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
    if (match == null) return null;
    final [y, m, d] = [for (var i = 1; i <= 3; i++) int.parse(match[i]!)];
    final date = DateTime(y, m, d);
    // Rejects dates such as 2027-02-30, which DateTime would roll over.
    return date.month == m && date.day == d ? date : null;
  }

  static String _format(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is PagePeriod &&
      other.from == from &&
      other.to == to &&
      other.month == month;

  @override
  int get hashCode => Object.hash(from, to, month);
}
