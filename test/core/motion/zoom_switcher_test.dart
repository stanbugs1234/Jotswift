import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/motion/motion.dart';
import 'package:notely/core/motion/zoom_switcher.dart';
import 'package:notely/core/skins/skin_manifest.dart';

import '../../helpers.dart';

void main() {
  late List<SkinManifest> skins;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    skins = await loadTestSkins();
  });

  /// Shows view `(name, level)`; returns a function that switches views.
  Future<void Function(String, int)> pumpZoom(
    WidgetTester tester, {
    String level = 'full',
  }) async {
    tester.view
      ..physicalSize = const Size(800, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = await makeContainer(
      skins,
      prefs: {'animationLevel': level},
    );
    final view = ValueNotifier(('Year', 0));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => MotionScope(child: child!),
          home: ValueListenableBuilder(
            valueListenable: view,
            builder: (context, v, _) => ZoomSwitcher(
              view: v.$1,
              level: v.$2,
              origin: const Rect.fromLTWH(100, 100, 200, 150),
              child: ColoredBox(color: Colors.white, child: Text(v.$1)),
            ),
          ),
        ),
      ),
    );
    return (name, level) => view.value = (name, level);
  }

  /// The smallest scale applied around [text], mid-animation.
  double scaleOf(WidgetTester tester, String text) => tester
      .widgetList<Transform>(
        find.ancestor(of: find.text(text), matching: find.byType(Transform)),
      )
      .map((t) => t.transform.storage[0]) // horizontal scale
      .fold(1.0, (a, b) => a < b ? a : b); // none: no zoom

  testWidgets('zooming in grows the new view out of the tapped place', (
    tester,
  ) async {
    final go = await pumpZoom(tester);
    go('March', 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Year'), findsOneWidget, reason: 'still leaving');
    expect(scaleOf(tester, 'March'), lessThan(0.6));
    await tester.pumpAndSettle();
    expect(find.text('Year'), findsNothing);
    expect(scaleOf(tester, 'March'), 1, reason: 'settled in place');
  });

  testWidgets('zooming out shrinks the old view back into its place', (
    tester,
  ) async {
    final go = await pumpZoom(tester);
    go('March', 1);
    await tester.pumpAndSettle();
    go('Year', 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(scaleOf(tester, 'March'), lessThan(0.6), reason: 'shrinking');
    await tester.pumpAndSettle();
    expect(find.text('March'), findsNothing);
  });

  testWidgets('reduced animations only crossfade', (tester) async {
    final go = await pumpZoom(tester, level: 'reduced');
    go('March', 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Year'), findsOneWidget);
    expect(scaleOf(tester, 'March'), 1, reason: 'no zoom');
    await tester.pumpAndSettle();
  });

  testWidgets('with animations off the view changes at once', (tester) async {
    final go = await pumpZoom(tester, level: 'off');
    go('March', 1);
    await tester.pump();
    expect(find.text('Year'), findsNothing);
    expect(find.text('March'), findsOneWidget);
  });
}
