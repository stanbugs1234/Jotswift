import 'package:flutter/material.dart';

import '../../core/skins/motley_skin.dart';
import '../../core/skins/skin_manifest.dart';
import '../../core/skins/widgets/paper.dart';

/// Read-only example pages that show off a skin. They are used in the skin
/// picker and as placeholders until the real editors are built.

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', //
  'August', 'September', 'October', 'November', 'December',
];
const _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', //
  'Sunday',
];

String longDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';

/// The page types a skin can be previewed on.
enum SamplePageKind {
  note('Note', Icons.edit_note),
  planner('Planner', Icons.view_day_outlined),
  todo('To-do', Icons.checklist),
  calendar('Calendar', Icons.calendar_month_outlined);

  const SamplePageKind(this.label, this.icon);

  final String label;
  final IconData icon;
}

class SamplePage extends StatelessWidget {
  const SamplePage({required this.kind, required this.date, super.key});

  final SamplePageKind kind;
  final DateTime date;

  @override
  Widget build(BuildContext context) => switch (kind) {
    SamplePageKind.note => const SampleNotePage(),
    SamplePageKind.planner => SamplePlannerPage(date: date),
    SamplePageKind.todo => const SampleTodoPage(),
    SamplePageKind.calendar => SampleCalendarPage(month: date),
  };
}

class SampleNotePage extends StatelessWidget {
  const SampleNotePage({super.key});

  @override
  Widget build(BuildContext context) {
    final skin = MotleySkin.of(context);
    final text = Theme.of(context).textTheme;
    // The first text line sits on the first ruled line.
    const firstLine = PaperPainter.topMargin;
    return Paper(
      child: Stack(
        children: [
          Positioned(
            left: PaperPainter.leftMargin + 12,
            top: 8,
            child: Text('Project ideas', style: text.headlineSmall),
          ),
          Positioned.fill(
            top: firstLine,
            child: CustomPaint(painter: _SampleInkPainter(skin)),
          ),
        ],
      ),
    );
  }
}

/// Fake handwriting: wavy strokes in the skin's ink colors.
class _SampleInkPainter extends CustomPainter {
  _SampleInkPainter(this.skin);

  final MotleySkin skin;

  @override
  void paint(Canvas canvas, Size size) {
    const left = PaperPainter.leftMargin + 12;
    final lineCount = (size.height / skin.spacing).floor().clamp(0, 6);
    for (var i = 0; i < lineCount; i++) {
      final baseline = skin.spacing * (i + 1) - 8;
      final width = (size.width - left - 24) * (i.isEven ? 0.85 : 0.6);
      final paint = Paint()
        ..color = skin.inkColors[i % skin.inkColors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;
      final path = Path()..moveTo(left, baseline);
      for (var x = 0.0; x < width; x += 10) {
        path.relativeQuadraticBezierTo(2.5, (x ~/ 10).isEven ? -9 : 3, 5, 0);
        path.relativeQuadraticBezierTo(2.5, (x ~/ 10).isEven ? 3 : -7, 5, 0);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SampleInkPainter old) => old.skin != skin;
}

class SamplePlannerPage extends StatelessWidget {
  const SamplePlannerPage({required this.date, super.key});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final skin = MotleySkin.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget label(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(s.toUpperCase(), style: theme.textTheme.labelMedium),
    );

    Widget slot(String time, String? title, Color? color) => SizedBox(
      height: 34,
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(time, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: title == null
                ? Divider(color: skin.lineColor)
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: color!.withValues(alpha: 0.18),
                      border: Border(left: BorderSide(color: color, width: 3)),
                    ),
                    child: Text(title, style: theme.textTheme.bodySmall),
                  ),
          ),
        ],
      ),
    );

    return Paper(
      pattern: PaperPattern.blank,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(longDate(date), style: skin.accentTextStyle),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      label('Schedule'),
                      slot('8:00', null, null),
                      slot('9:00', 'Team stand-up', scheme.primary),
                      slot('10:00', null, null),
                      slot('11:00', 'Dentist', scheme.secondary),
                      slot('12:00', null, null),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      label('Top 3'),
                      const _SampleTask('Finish slides', done: true),
                      const _SampleTask('Call Mom'),
                      const _SampleTask('Water plants'),
                      const SizedBox(height: 12),
                      label('Notes'),
                      Expanded(
                        child: Paper(pattern: skin.pattern, showMargin: false),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SampleTask extends StatelessWidget {
  const _SampleTask(this.title, {this.done = false});

  final String title;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          Icon(
            done ? Icons.check_box : Icons.check_box_outline_blank,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                decoration: done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SampleTodoPage extends StatelessWidget {
  const SampleTodoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final skin = MotleySkin.of(context);
    final theme = Theme.of(context);
    return Paper(
      pattern: PaperPattern.blank,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This week', style: skin.accentTextStyle),
          const SizedBox(height: 8),
          const _SampleTask('Book flights', done: true),
          const _SampleTask('Renew library books', done: true),
          const _SampleTask('Plan birthday dinner'),
          const _SampleTask('Fix the bike tire'),
          const _SampleTask('Send invoices'),
          const SizedBox(height: 12),
          Text('Groceries', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          const _SampleTask('Oat milk'),
          const _SampleTask('Basil'),
        ],
      ),
    );
  }
}

class SampleCalendarPage extends StatelessWidget {
  const SampleCalendarPage({required this.month, super.key});

  /// Any day in the month to show. That day is highlighted.
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final skin = MotleySkin.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final first = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = first.weekday - 1; // Weeks start on Monday.
    final cellCount = ((leadingBlanks + daysInMonth) / 7).ceil() * 7;
    // Example events, so the grid has some color.
    final eventDays = {
      3: scheme.primary,
      12: scheme.secondary,
      21: scheme.primary,
    };

    return Paper(
      pattern: PaperPattern.blank,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_months[month.month - 1]} ${month.year}',
            style: skin.accentTextStyle,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final d in _weekdays)
                Expanded(
                  child: Center(
                    child: Text(
                      d.substring(0, 1),
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: GridView.count(
              crossAxisCount: 7,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.1,
              children: [
                for (var i = 0; i < cellCount; i++)
                  _dayCell(
                    context,
                    i - leadingBlanks + 1,
                    daysInMonth,
                    eventDays,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayCell(
    BuildContext context,
    int day,
    int daysInMonth,
    Map<int, Color> eventDays,
  ) {
    if (day < 1 || day > daysInMonth) return const SizedBox.shrink();
    final skin = MotleySkin.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isSelected = day == month.day;
    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: isSelected ? scheme.primary : null,
        border: Border.all(color: skin.lineColor),
        borderRadius: BorderRadius.circular(skin.cornerRadius / 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$day',
            style: TextStyle(
              color: isSelected ? scheme.onPrimary : scheme.onSurface,
              fontSize: 12,
            ),
          ),
          if (eventDays[day] case final color?)
            Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
        ],
      ),
    );
  }
}
