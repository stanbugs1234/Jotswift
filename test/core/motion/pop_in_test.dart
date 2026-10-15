import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/motion/motion.dart';
import 'package:notely/core/motion/pop_in.dart';
import 'package:notely/core/skins/skin_manifest.dart';

import '../../helpers.dart';

void main() {
  late List<SkinManifest> skins;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    skins = await loadTestSkins();
  });

  Future<ValueNotifier<Brightness>> pumpPopIn(
    WidgetTester tester, {
    String level = 'full',
  }) async {
    final container = await makeContainer(
      skins,
      prefs: {'animationLevel': level},
    );
    final brightness = ValueNotifier(Brightness.light);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ValueListenableBuilder(
          valueListenable: brightness,
          builder: (context, b, _) => MaterialApp(
            theme: ThemeData(brightness: b),
            builder: (context, child) => MotionScope(child: child!),
            home: const PopIn(child: Text('Sticker')),
          ),
        ),
      ),
    );
    return brightness;
  }

  double? scaleOf(WidgetTester tester) {
    final t = find.descendant(
      of: find.byType(PopIn),
      matching: find.byType(Transform),
    );
    if (t.evaluate().isEmpty) return null;
    return tester.widget<Transform>(t.first).transform.storage[0];
  }

  testWidgets('grows in once, then stays put', (tester) async {
    final brightness = await pumpPopIn(tester);
    await tester.pump(const Duration(milliseconds: 30));
    expect(scaleOf(tester), lessThan(1));

    await tester.pumpAndSettle();
    expect(scaleOf(tester), isNull);

    // A theme change doesn't replay it.
    brightness.value = Brightness.dark;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(scaleOf(tester), isNull);
  });

  testWidgets('with animations off, it simply appears', (tester) async {
    await pumpPopIn(tester, level: 'off');
    await tester.pump(const Duration(milliseconds: 30));
    expect(scaleOf(tester), isNull);
    expect(
      tester
          .widgetList<Opacity>(
            find.ancestor(
              of: find.text('Sticker'),
              matching: find.byType(Opacity),
            ),
          )
          .every((o) => o.opacity == 1),
      isTrue,
    );
  });
}
