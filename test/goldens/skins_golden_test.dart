@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motley/core/skins/skin_manifest.dart';
import 'package:motley/features/skins/sample_pages.dart';

import '../helpers.dart';

/// Screenshots of every skin on every page type. If a skin or page changes
/// on purpose, regenerate them with:
///
///     flutter test --update-goldens --tags golden
void main() {
  late List<SkinManifest> skins;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    skins = await loadTestSkins();
  });

  // A fixed date keeps the planner and calendar the same on every run.
  final date = DateTime(2026, 10, 14);

  for (final id in [
    'classic',
    'minimal_dark',
    'pastel',
    'kraft',
    'botanical',
  ]) {
    testWidgets('$id skin', (tester) async {
      tester.view
        ..physicalSize = const Size(900, 1200)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        themed(
          skinById(skins, id),
          RepaintBoundary(
            key: const Key('pages'),
            child: GridView.count(
              padding: const EdgeInsets.all(12),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 3 / 4,
              children: [
                for (final kind in SamplePageKind.values)
                  SamplePage(kind: kind, date: date),
              ],
            ),
          ),
        ),
      );

      await expectLater(
        find.byKey(const Key('pages')),
        matchesGoldenFile('skins/$id.png'),
      );
    });
  }
}
