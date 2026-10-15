import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/entitlements/entitlements.dart';
import '../../../core/motion/period_transition.dart';
import '../../store/paywall.dart';
import '../calendar_providers.dart';
import '../domain/event.dart';
import 'calendar_look.dart';
import 'calendar_template.dart';

/// Opens the template and animation picker: a sheet on tablets, a full
/// screen on phones.
Future<void> showCalendarTemplates(BuildContext context) {
  // In the app's own look, not the current template's.
  final navigator = Navigator.of(context, rootNavigator: true);
  final appTheme = Theme.of(navigator.context);
  if (MediaQuery.sizeOf(context).width >= 600) {
    return showModalBottomSheet<void>(
      context: navigator.context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: appTheme.colorScheme.surface,
      builder: (_) => Theme(
        data: appTheme,
        child: const FractionallySizedBox(
          heightFactor: 0.88,
          child: CalendarTemplatesPicker(),
        ),
      ),
    );
  }
  return navigator.push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => Theme(
        data: appTheme,
        child: Scaffold(
          appBar: AppBar(title: const Text('Calendar templates')),
          body: const CalendarTemplatesPicker(),
        ),
      ),
    ),
  );
}

/// Templates as live previews, and the month animation with a demo.
class CalendarTemplatesPicker extends ConsumerStatefulWidget {
  const CalendarTemplatesPicker({super.key});

  @override
  ConsumerState<CalendarTemplatesPicker> createState() =>
      _CalendarTemplatesPickerState();
}

class _CalendarTemplatesPickerState
    extends ConsumerState<CalendarTemplatesPicker> {
  /// The demo's month; each animation tap moves it on and back.
  late Day _demoMonth = ref.read(calendarProvider).day.firstOfMonth;

  void _demo() => setState(
    () => _demoMonth = _demoMonth.month == 12
        ? Day(_demoMonth.year + 1, 1, 1)
        : Day(_demoMonth.year, _demoMonth.month + 1, 1),
  );

  Future<void> _pick(CalendarTemplate t) async {
    final entitlements = ref.read(entitlementsProvider);
    if (!canUseCalendarTemplate(entitlements, t)) {
      final unlocked = await showPaywall(
        context,
        ref,
        reason: '${t.name} is included in Jotswift Pro.',
      );
      if (!unlocked) return;
    }
    await ref.read(calendarTemplateSettingProvider.notifier).select(t);
    _demo();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = ref.watch(calendarTemplateProvider);
    final choice = ref.watch(monthAnimationChoiceProvider);
    final animation = ref.watch(monthAnimationProvider);
    final entitlements = ref.watch(entitlementsProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text('Month animation', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              height: 150,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: PeriodTransition<Day>(
                  animation: animation,
                  period: _demoMonth,
                  child: TemplatePreview(template: current, month: _demoMonth),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text("Template's (${current.animation.label})"),
                    selected: choice == null,
                    onSelected: (_) {
                      ref
                          .read(monthAnimationSettingProvider.notifier)
                          .set(null);
                      _demo();
                    },
                  ),
                  for (final a in PeriodAnimation.values)
                    ChoiceChip(
                      label: Text(a.label),
                      selected: choice == a,
                      onSelected: (_) {
                        ref.read(monthAnimationSettingProvider.notifier).set(a);
                        _demo();
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text('Templates', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = (constraints.maxWidth / 170).floor().clamp(2, 5);
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: columns,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.72,
              children: [
                for (final t in calendarTemplates)
                  _TemplateCard(
                    template: t,
                    selected: t == current,
                    badge: t.free
                        ? 'Free'
                        : entitlements.owns(t.productId!) ||
                              entitlements.owns(calendarTemplatesBundle)
                        ? 'Owned'
                        : entitlements.pro
                        ? 'In your Pro'
                        : 'Pro',
                    onTap: () => _pick(t),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final CalendarTemplate template;
  final bool selected;
  final String badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final month = Day.of(DateTime.now()).firstOfMonth;
    return Semantics(
      button: true,
      selected: selected,
      label: '${template.name}, $badge',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    width: selected ? 3 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: TemplatePreview(template: template, month: month),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(template.name, style: theme.textTheme.titleSmall),
            Text(
              badge,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small month drawn in [template], with a few sample events, for
/// choosing templates and showing animations.
class TemplatePreview extends StatelessWidget {
  const TemplatePreview({
    required this.template,
    required this.month,
    super.key,
  });

  final CalendarTemplate template;
  final Day month;

  static const _sample = {
    3: 0xFF1F8A99,
    9: 0xFFC8553D,
    14: 0xFF7B4FA0,
    22: 0xFFD4A017,
  };

  @override
  Widget build(BuildContext context) {
    final local = MaterialLocalizations.of(context);
    final today = Day.of(DateTime.now());
    final first = startOfWeek(month, local.firstDayOfWeekIndex);
    return CalendarLook(
      template: template,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final small = theme.textTheme.labelSmall!.copyWith(fontSize: 8);
          return ColoredBox(
            color: template.background,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.bigMonthNumber
                        ? month.month.toString().padLeft(2, '0')
                        : local.formatMonthYear(month.toDateTime()),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontSize: template.bigMonthNumber ? 20 : 11,
                      fontWeight: FontWeight.w800,
                      color: template.bigMonthNumber ? template.accent : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Column(
                      children: [
                        for (var r = 0; r < 6; r++)
                          Expanded(
                            child: Row(
                              children: [
                                for (var c = 0; c < 7; c++)
                                  Expanded(
                                    child: _PreviewDay(
                                      day: first.addDays(r * 7 + c),
                                      inMonth:
                                          first.addDays(r * 7 + c).month ==
                                          month.month,
                                      isToday:
                                          first.addDays(r * 7 + c) == today,
                                      event:
                                          _sample[first.addDays(r * 7 + c).day],
                                      seed: r * 7 + c,
                                      style: small,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PreviewDay extends StatelessWidget {
  const _PreviewDay({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.event,
    required this.seed,
    required this.style,
  });

  final Day day;
  final bool inMonth;
  final bool isToday;
  final int? event;
  final int seed;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final t = CalendarLook.of(context);
    if (!inMonth) return const SizedBox.expand();
    return CustomPaint(
      foregroundPainter: t.cornerRadius > 0
          ? null
          : CellEdges(t.gridLines, t.grid, seed: seed),
      child: Container(
        margin: EdgeInsets.all(t.cornerRadius > 0 ? 1 : 0),
        decoration: t.cornerRadius > 0
            ? BoxDecoration(
                color: t.cell,
                borderRadius: BorderRadius.circular(t.cornerRadius / 3),
              )
            : null,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isToday)
              TodayMark(text: '${day.day}', style: style, size: 12)
            else
              Text('${day.day}', style: style),
            if (event != null && !isToday)
              Positioned(
                bottom: 1,
                child: Container(width: 10, height: 2.5, color: Color(event!)),
              ),
          ],
        ),
      ),
    );
  }
}
