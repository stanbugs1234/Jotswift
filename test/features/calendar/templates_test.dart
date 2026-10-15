import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/app/app.dart';
import 'package:notely/core/entitlements/entitlements.dart';
import 'package:notely/core/motion/period_transition.dart';
import 'package:notely/core/settings/synced_setting.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/calendar/calendar_providers.dart';
import 'package:notely/features/calendar/data/event_repository.dart';
import 'package:notely/features/calendar/domain/event.dart';
import 'package:notely/features/calendar/templates/calendar_look.dart';
import 'package:notely/features/calendar/templates/calendar_template.dart';
import 'package:notely/features/calendar/templates/calendar_templates_screen.dart';
import 'package:notely/features/tasks/task_providers.dart';

import '../../helpers.dart';

const today = Day(2026, 10, 14);

final events = [
  CalendarEvent(
    id: 'a',
    title: 'Standup with the whole team',
    start: DateTime(2026, 10, 14, 9),
    end: DateTime(2026, 10, 14, 10),
  ),
  CalendarEvent(
    id: 'b',
    title: 'Trip',
    allDay: true,
    start: DateTime(2026, 10, 16),
    end: DateTime(2026, 10, 18),
  ),
];

void main() {
  late List<SkinManifest> skins;

  setUpAll(() async {
    skins = await loadTestSkins();
  });

  Future<ProviderContainer> open(
    WidgetTester tester, {
    Size size = const Size(1024, 900),
    bool pro = true,
  }) async {
    await pumpApp(
      tester,
      skins,
      size: size,
      overrides: [
        todayProvider.overrideWithValue(today),
        eventsBackendProvider.overrideWithValue(InMemoryEventsBackend()),
        accountEntitlementsProvider.overrideWithValue(
          AsyncData(Entitlements(pro: pro)),
        ),
      ],
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NotelyApp)),
    );
    for (final e in events) {
      await container.read(eventRepositoryProvider).saveEvent(e);
    }
    await tester.tap(find.text('Calendar').last);
    await tester.pumpAndSettle();
    return container;
  }

  for (final size in const [Size(400, 800), Size(1024, 900)]) {
    testWidgets(
      'every template draws every view at ${size.width.round()} wide',
      (tester) async {
        final c = await open(tester, size: size);
        for (final t in calendarTemplates) {
          await c.read(calendarTemplateSettingProvider.notifier).select(t);
          for (final mode in CalendarMode.values) {
            c.read(calendarProvider.notifier).setMode(mode);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '${t.id} $mode');
          }
        }
      },
    );
  }

  testWidgets('a template recolours the Calendar and sets its animation', (
    tester,
  ) async {
    final c = await open(tester);
    final night = calendarTemplateById('night');
    await c.read(calendarTemplateSettingProvider.notifier).select(night);
    await tester.pumpAndSettle();
    final scaffold = Theme.of(tester.element(find.text('New event')))
        .scaffoldBackgroundColor;
    expect(scaffold, night.background);
    expect(c.read(monthAnimationProvider), PeriodAnimation.fade);

    // An animation chosen by the user wins over the template's.
    await c
        .read(monthAnimationSettingProvider.notifier)
        .set(PeriodAnimation.cube);
    expect(c.read(monthAnimationProvider), PeriodAnimation.cube);
    expect(
      c.read(sharedPreferencesProvider).getString('monthAnimation'),
      'cube',
    );
    expect(
      c.read(sharedPreferencesProvider).getString('calendarTemplate'),
      'night',
    );
  });

  testWidgets('a paid template without Pro falls back to Classic', (
    tester,
  ) async {
    final c = await open(tester, pro: false);
    await c
        .read(calendarTemplateSettingProvider.notifier)
        .select(calendarTemplateById('wall'));
    expect(c.read(calendarTemplateProvider), classicCalendar);
  });

  testWidgets('the picker applies templates and plays animations', (
    tester,
  ) async {
    final c = await open(tester);
    await tester.tap(find.byTooltip('Templates & animation'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp('^Minimal')));
    await tester.pumpAndSettle();
    expect(c.read(calendarTemplateProvider).id, 'minimal');

    await tester.tap(find.text('Wall flip'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(PeriodTransition<Day>), findsWidgets);
    await tester.pumpAndSettle();
    expect(c.read(monthAnimationChoiceProvider), PeriodAnimation.wallFlip);
  });

  testWidgets('a locked template in the picker offers Pro', (tester) async {
    await open(tester, pro: false);
    await tester.tap(find.byTooltip('Templates & animation'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.bySemanticsLabel(RegExp('^Wall Calendar, Pro')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(CalendarTemplatesPicker),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.bySemanticsLabel(RegExp('^Wall Calendar, Pro')));
    await tester.pumpAndSettle();
    expect(find.textContaining('included in Jotswift Pro'), findsOneWidget);
  });
}
