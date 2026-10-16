import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/motion/page_turn.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/settings/page_turn_picker.dart';

import '../../helpers.dart';

void main() {
  late List<SkinManifest> skins;

  setUpAll(() async {
    skins = await loadTestSkins();
  });

  testWidgets('a style is picked from the chips and previewed', (tester) async {
    final container = await makeContainer(skins);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: PageTurnPicker())),
      ),
    );
    expect(find.byType(ChoiceChip), findsNWidgets(PageTurnStyle.values.length));
    expect(container.read(pageTurnStyleProvider), PageTurnStyle.curl);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Slide'));
    await tester.pump();
    expect(container.read(pageTurnStyleProvider), PageTurnStyle.slide);
    // The preview turns to show it.
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('1'), findsNothing);
  });
}
