import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tasks/task_providers.dart' show todayProvider;
import '../calendar_providers.dart';
import '../domain/event.dart';
import '../event_editor.dart';

/// Days before and after [AgendaView.anchor] that the list covers.
const _daysBack = 180;
const _daysAhead = 365;

/// Every event as one list, a heading per day (pinned while its events
/// scroll by), and a short note for the days in between with none. Opens
/// at [anchor]; scroll up for earlier days.
class AgendaView extends ConsumerWidget {
  const AgendaView({required this.anchor, super.key});

  final Day anchor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final from = anchor.addDays(-_daysBack);
    final to = anchor.addDays(_daysAhead);
    final byDay = groupByDay(
      ref.watch(occurrencesProvider((from: from, to: to))),
      from,
      to,
    );
    final ahead = [
      for (final d in byDay.keys)
        if (!d.isBefore(anchor)) d,
    ];
    final before = [
      for (final d in byDay.keys.toList().reversed)
        if (d.isBefore(anchor)) d,
    ];
    const center = ValueKey('agenda-center');

    final slivers = <Widget>[];
    // The chosen day always shows, even with nothing on it.
    final first = ahead.firstOrNull;
    if (first != anchor) {
      slivers.add(
        _DaySliver(
          day: anchor,
          occurrences: const [],
          gapUntil: first == null
              ? to
              : first.isAfter(anchor.addDays(1))
              ? first.addDays(-1)
              : null,
        ),
      );
    }
    for (final (i, day) in ahead.indexed) {
      final next = i + 1 < ahead.length ? ahead[i + 1] : null;
      slivers.add(
        _DaySliver(
          day: day,
          occurrences: byDay[day]!,
          gapUntil: next != null && next.isAfter(day.addDays(1))
              ? next.addDays(-1)
              : null,
          gapFrom: day.addDays(1),
        ),
      );
    }
    if (ahead.isEmpty) {
      slivers.add(
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Nothing coming up.'),
          ),
        ),
      );
    }

    return CustomScrollView(
      key: ValueKey(anchor),
      center: center,
      slivers: [
        // Earlier days, nearest first, stacking upward from the anchor.
        SliverList.builder(
          itemCount: before.length,
          itemBuilder: (context, i) =>
              _DayBlock(day: before[i], occurrences: byDay[before[i]]!),
        ),
        SliverMainAxisGroup(key: center, slivers: slivers),
        const SliverToBoxAdapter(child: SizedBox(height: 88)),
      ],
    );
  }
}

/// [occurrences] by the days they're on between [from] and [to], in
/// order; all-day events first, then by start time.
Map<Day, List<Occurrence>> groupByDay(
  List<Occurrence> occurrences,
  Day from,
  Day to,
) {
  final byDay = <Day, List<Occurrence>>{};
  for (final o in occurrences) {
    var d = Day.of(o.start).isBefore(from) ? from : Day.of(o.start);
    final last = Day.of(o.end);
    while (!d.isAfter(last) && !d.isAfter(to)) {
      if (o.isOn(d)) byDay.putIfAbsent(d, () => []).add(o);
      d = d.addDays(1);
    }
  }
  final days = byDay.keys.toList()..sort();
  return {
    for (final d in days)
      d: byDay[d]!
        ..sort((a, b) {
          if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
          return a.start.compareTo(b.start);
        }),
  };
}

/// A day's heading (pinned while its events scroll), its events, and a
/// note when the next days are empty.
class _DaySliver extends StatelessWidget {
  const _DaySliver({
    required this.day,
    required this.occurrences,
    this.gapFrom,
    this.gapUntil,
  });

  final Day day;
  final List<Occurrence> occurrences;
  final Day? gapFrom;
  final Day? gapUntil;

  @override
  Widget build(BuildContext context) => SliverMainAxisGroup(
    slivers: [
      SliverPersistentHeader(pinned: true, delegate: _HeaderDelegate(day)),
      SliverList.list(
        children: [
          if (occurrences.isEmpty) const _Empty('Nothing on this day.'),
          for (final o in occurrences) _EventTile(occurrence: o),
          if (gapUntil case final until?)
            _Gap(from: gapFrom ?? day.addDays(1), until: until),
        ],
      ),
    ],
  );
}

/// An earlier day: the same, without pinning.
class _DayBlock extends StatelessWidget {
  const _DayBlock({required this.day, required this.occurrences});

  final Day day;
  final List<Occurrence> occurrences;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Heading(day: day),
      for (final o in occurrences) _EventTile(occurrence: o),
    ],
  );
}

class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  _HeaderDelegate(this.day);

  final Day day;

  @override
  double get minExtent => 40;

  @override
  double get maxExtent => 40;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      _Heading(day: day, raised: overlaps || shrinkOffset > 0);

  @override
  bool shouldRebuild(_HeaderDelegate old) => old.day != day;
}

class _Heading extends ConsumerWidget {
  const _Heading({required this.day, this.raised = false});

  final Day day;
  final bool raised;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final local = MaterialLocalizations.of(context);
    final isToday = day == ref.watch(todayProvider);
    return Material(
      color: theme.colorScheme.surface,
      elevation: raised ? 1 : 0,
      child: InkWell(
        onTap: () => ref.read(calendarProvider.notifier).openDay(day),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerLeft,
          child: Text(
            isToday
                ? 'Today · ${local.formatMediumDate(day.toDateTime())}'
                : local.formatFullDate(day.toDateTime()),
            style: theme.textTheme.titleSmall?.copyWith(
              color: isToday ? theme.colorScheme.primary : null,
              fontWeight: isToday ? FontWeight.w700 : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.occurrence});

  final Occurrence occurrence;

  @override
  Widget build(BuildContext context) {
    final local = MaterialLocalizations.of(context);
    String time(DateTime t) => local.formatTimeOfDay(TimeOfDay.fromDateTime(t));
    final o = occurrence;
    return ListTile(
      dense: true,
      leading: Container(
        width: 6,
        height: 32,
        decoration: BoxDecoration(
          color: Color(o.color),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      title: Text(o.event.title),
      subtitle: Text(
        [
          o.allDay ? 'All day' : '${time(o.start)} – ${time(o.end)}',
          if (o.event.recurrence != null) 'Repeats',
        ].join(' · '),
      ),
      onTap: () => showEventEditor(context, event: o.event),
    );
  }
}

class _Gap extends StatelessWidget {
  const _Gap({required this.from, required this.until});

  final Day from;
  final Day until;

  @override
  Widget build(BuildContext context) {
    final local = MaterialLocalizations.of(context);
    final a = local.formatShortMonthDay(from.toDateTime());
    final b = local.formatShortMonthDay(until.toDateTime());
    return _Empty(from == until ? 'No events · $a' : 'No events · $a – $b');
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(72, 6, 16, 10),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
    );
  }
}
