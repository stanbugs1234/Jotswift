import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/motion/motion.dart';
import 'package:notely/core/motion/period_transition.dart';
import 'package:notely/core/skins/skin_manifest.dart';

import '../../helpers.dart';

void main() {
  late List<SkinManifest> skins;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    skins = await loadTestSkins();
  });

  /// Shows "Month 5" with [animation]; returns a function to move.
  Future<void Function(int)> pumpMonths(
    WidgetTester tester,
    PeriodAnimation animation, {
    String level = 'full',
  }) async {
    tester.view
      ..physicalSize = const Size(600, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = await makeContainer(
      skins,
      prefs: {'animationLevel': level},
    );
    final month = ValueNotifier(5);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => MotionScope(child: child!),
          home: ValueListenableBuilder(
            valueListenable: month,
            builder: (context, m, _) => PeriodTransition<num>(
              animation: animation,
              period: m,
              child: ColoredBox(color: Colors.white, child: Text('Month $m')),
            ),
          ),
        ),
      ),
    );
    return (m) => month.value = m;
  }

  /// The transforms between [text] and the switcher, mid-animation.
  List<Matrix4> transformsAround(WidgetTester tester, String text) => [
    for (final t in tester.widgetList<Transform>(
      find.ancestor(of: find.text(text), matching: find.byType(Transform)),
    ))
      t.transform,
  ];

  for (final animation in PeriodAnimation.values) {
    testWidgets('${animation.label}: both months mid-way, then only the new', (
      tester,
    ) async {
      final go = await pumpMonths(tester, animation);
      go(6);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('Month 5'), findsOneWidget);
      expect(find.text('Month 6'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Month 5'), findsNothing);
      expect(find.text('Month 6'), findsOneWidget);

      go(5); // and back
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('Month 6'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Month 6'), findsNothing);
    });
  }

  testWidgets('slide and stack move the way of travel', (tester) async {
    final go = await pumpMonths(tester, PeriodAnimation.slide);
    go(6);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final forward = transformsAround(tester, 'Month 6').first;
    expect(forward.getTranslation().x, greaterThan(0), reason: 'from right');
    await tester.pumpAndSettle();
    go(5);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final back = transformsAround(tester, 'Month 5').first;
    expect(back.getTranslation().x, lessThan(0), reason: 'from left');
    await tester.pumpAndSettle();
  });

  testWidgets('the wall flip lifts the old month over its top edge', (
    tester,
  ) async {
    final go = await pumpMonths(tester, PeriodAnimation.wallFlip);
    go(6);
    await tester.pump();
    // It starts slowly, like lifting a heavy page.
    await tester.pump(const Duration(milliseconds: 400));
    final flips = transformsAround(tester, 'Month 5');
    // Rotated around the x axis: the y and z rows change.
    expect(flips.any((m) => m.entry(1, 1) < 0.99), isTrue);
    expect(transformsAround(tester, 'Month 6'), isEmpty, reason: 'lies flat');
    await tester.pumpAndSettle();
  });

  testWidgets('reduced animations crossfade whatever is chosen', (
    tester,
  ) async {
    final go = await pumpMonths(tester, PeriodAnimation.cube, level: 'reduced');
    go(6);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Month 5'), findsOneWidget);
    expect(transformsAround(tester, 'Month 6'), isEmpty);
    await tester.pumpAndSettle();
  });

  testWidgets('with animations off the month changes at once', (tester) async {
    final go = await pumpMonths(tester, PeriodAnimation.wallFlip, level: 'off');
    go(6);
    await tester.pump();
    expect(find.text('Month 5'), findsNothing);
    expect(find.text('Month 6'), findsOneWidget);
  });

  testWidgets('quick changes keep up and end on the last month', (
    tester,
  ) async {
    final go = await pumpMonths(tester, PeriodAnimation.pageTurn);
    for (final m in [6, 7, 8]) {
      go(m);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pumpAndSettle();
    expect(find.text('Month 8'), findsOneWidget);
    expect(find.textContaining('Month'), findsOneWidget);
  });
}
