import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tasks/task_providers.dart' show todayProvider;
import '../calendar_providers.dart';
import '../domain/event.dart';

/// Called with the tapped month's first day and where it is on screen.
typedef MonthTap = void Function(Day month, Rect from);

/// Twelve small months. Days with events get a dot in their colour, and
/// today is circled. Tapping a month opens it.
class YearView extends ConsumerWidget {
  const YearView({required this.year, required this.onMonth, super.key});

  final int year;
  final MonthTap onMonth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final occurrences = ref.watch(
      occurrencesProvider((from: Day(year, 1, 1), to: Day(year, 12, 31))),
    );
    // The colour of each day's first event, for its dot.
    final dots = <Day, int>{};
    for (final o in occurrences) {
      var d = Day.of(o.start);
      final last = Day.of(o.end);
      for (var i = 0; i < 366 && !d.isAfter(last); i++, d = d.addDays(1)) {
        if (d.year == year) dots.putIfAbsent(d, () => o.color);
      }
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 560
            ? 3
            : 2;
        return GridView.count(
          padding: const EdgeInsets.all(12),
          crossAxisCount: columns,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.92,
          children: [
            for (var m = 1; m <= 12; m++)
              _MiniMonth(month: Day(year, m, 1), dots: dots, onTap: onMonth),
          ],
        );
      },
    );
  }
}

class _MiniMonth extends ConsumerWidget {
  const _MiniMonth({
    required this.month,
    required this.dots,
    required this.onTap,
  });

  final Day month;
  final Map<Day, int> dots;
  final MonthTap onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final local = MaterialLocalizations.of(context);
    final today = ref.watch(todayProvider);
    final first = startOfWeek(month, local.firstDayOfWeekIndex);
    final isThisMonth = today.year == month.year && today.month == month.month;
    final name = local.formatMonthYear(month.toDateTime()).split(' ').first;
    final letters = [
      for (var i = 0; i < 7; i++)
        local.narrowWeekdays[(local.firstDayOfWeekIndex + i) % 7],
    ];

    return Semantics(
      button: true,
      label: local.formatMonthYear(month.toDateTime()),
      excludeSemantics: true,
      child: Builder(
        builder: (context) => InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            final box = context.findRenderObject()! as RenderBox;
            onTap(month, box.localToGlobal(Offset.zero) & box.size);
          },
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 4),
                  child: Text(
                    name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: isThisMonth ? theme.colorScheme.primary : null,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final cw = c.maxWidth / 7;
                      final ch = c.maxHeight / 7;
                      final size = (cw < ch ? cw : ch);
                      final small = theme.textTheme.labelSmall!.copyWith(
                        fontSize: (size * 0.42).clamp(7, 13),
                        height: 1,
                      );
                      Widget cell(Widget child) =>
                          SizedBox(width: cw, height: ch, child: child);
                      return Column(
                        children: [
                          Row(
                            children: [
                              for (final l in letters)
                                cell(
                                  Center(
                                    child: Text(
                                      l,
                                      style: small.copyWith(
                                        color: theme.colorScheme.outline,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          for (var r = 0; r < 6; r++)
                            Row(
                              children: [
                                for (var i = 0; i < 7; i++)
                                  cell(
                                    _MiniDay(
                                      day: first.addDays(r * 7 + i),
                                      inMonth:
                                          first.addDays(r * 7 + i).month ==
                                          month.month,
                                      today: today,
                                      dot: dots[first.addDays(r * 7 + i)],
                                      size: size,
                                      style: small,
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniDay extends StatelessWidget {
  const _MiniDay({
    required this.day,
    required this.inMonth,
    required this.today,
    required this.dot,
    required this.size,
    required this.style,
  });

  final Day day;
  final bool inMonth;
  final Day today;
  final int? dot;
  final double size;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (!inMonth) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final isToday = day == today;
    return Stack(
      alignment: Alignment.center,
      children: [
        if (isToday)
          Container(
            width: size * 0.9,
            height: size * 0.9,
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
            ),
          ),
        Text(
          '${day.day}',
          style: style.copyWith(
            color: isToday ? scheme.onPrimary : scheme.onSurface,
            fontWeight: isToday ? FontWeight.w700 : null,
          ),
        ),
        if (dot != null && !isToday)
          Positioned(
            bottom: 0,
            child: Container(
              width: (size * 0.16).clamp(2, 5),
              height: (size * 0.16).clamp(2, 5),
              decoration: BoxDecoration(
                color: Color(dot!),
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}
