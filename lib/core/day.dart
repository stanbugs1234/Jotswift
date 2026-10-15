import 'package:flutter/foundation.dart';

/// A calendar day with no time or time zone, such as a due date. Stored
/// as "2026-10-14", so it's the same day everywhere.
@immutable
class Day implements Comparable<Day> {
  const Day(this.year, this.month, this.day);

  factory Day.of(DateTime t) => Day(t.year, t.month, t.day);

  factory Day.today() => Day.of(DateTime.now());

  /// Reads "YYYY-MM-DD". Returns null for anything else.
  static Day? tryParse(Object? value) {
    if (value is! String) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (m == null) return null;
    final day = Day(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
    // Rejects impossible dates such as February 30.
    return Day.of(day.toDateTime()) == day ? day : null;
  }

  final int year;
  final int month;
  final int day;

  /// Midnight at the start of this day, local time.
  DateTime toDateTime() => DateTime(year, month, day);

  /// [DateTime.monday] to [DateTime.sunday].
  int get weekday => toDateTime().weekday;

  /// The first day of this day's month.
  Day get firstOfMonth => Day(year, month, 1);

  Day addDays(int days) => Day.of(DateTime(year, month, day + days));

  /// Whole days from this day to [other] (negative if [other] is earlier).
  int daysUntil(Day other) => DateTime.utc(
    other.year,
    other.month,
    other.day,
  ).difference(DateTime.utc(year, month, day)).inDays;

  bool isBefore(Day other) => compareTo(other) < 0;
  bool isAfter(Day other) => compareTo(other) > 0;

  @override
  int compareTo(Day other) =>
      (year - other.year) * 10000 +
      (month - other.month) * 100 +
      (day - other.day);

  @override
  bool operator ==(Object other) =>
      other is Day &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}
