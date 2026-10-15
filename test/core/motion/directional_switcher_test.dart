import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/motion/directional_switcher.dart';
import 'package:notely/core/motion/motion.dart';
import 'package:notely/core/skins/skin_manifest.dart';

import '../../helpers.dart';

void main() {
  late List<SkinManifest> skins;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    skins = await loadTestSkins();
  });

  Future<void Function(int)> pumpSwitcher(
    WidgetTester tester, {
    String level = 'full',
  }) async {
    final container = await makeContainer(
      skins,
      prefs: {'animationLevel': level},
    );
    final position = ValueNotifier(5);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => MotionScope(child: child!),
          home: ValueListenableBuilder(
            valueListenable: position,
            builder: (context, p, _) =>
                DirectionalSwitcher<num>(position: p, child: Text('Page $p')),
          ),
        ),
      ),
    );
    return (p) => position.value = p;
  }

  /// The horizontal offset of the slide around [text], mid-animation.
  double slideOf(WidgetTester tester, String text) => tester
      .widget<SlideTransition>(
        find
            .ancestor(
              of: find.text(text),
              matching: find.byType(SlideTransition),
            )
            .first,
      )
      .position
      .value
      .dx;

  testWidgets('moving forward slides the new view in from the right', (
    tester,
  ) async {
    final go = await pumpSwitcher(tester);
    go(6);
    await tester.pump();
    await tester.pump(MotionTokens.standard ~/ 4);

    expect(slideOf(tester, 'Page 6'), greaterThan(0));
    expect(slideOf(tester, 'Page 5'), lessThan(0));
    await tester.pumpAndSettle();
    expect(find.text('Page 5'), findsNothing);
  });

  testWidgets('moving back slides the new view in from the left', (
    tester,
  ) async {
    final go = await pumpSwitcher(tester);
    go(4);
    await tester.pump();
    await tester.pump(MotionTokens.standard ~/ 4);

    expect(slideOf(tester, 'Page 4'), lessThan(0));
    expect(slideOf(tester, 'Page 5'), greaterThan(0));
  });

  testWidgets('reduced animations fade without sliding', (tester) async {
    final go = await pumpSwitcher(tester, level: 'reduced');
    go(6);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.descendant(
        of: find.byType(DirectionalSwitcher<num>),
        matching: find.byType(SlideTransition),
      ),
      findsNothing,
    );
    expect(find.text('Page 6'), findsOneWidget);
  });
}
