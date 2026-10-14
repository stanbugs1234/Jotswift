@Tags(['golden'])
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/auth/auth_repository.dart';
import 'package:notely/features/canvas/domain/stroke.dart';
import 'package:notely/features/canvas/page_canvas.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/notes_providers.dart';

import '../helpers.dart';

/// Handwriting-like strokes: a pressure-sensitive wave, a finger-drawn
/// spiral, a highlighter swipe and a dot.
List<Stroke> sampleInk(List<Color> ink) {
  var n = 0;
  Stroke make(
    InkTool tool,
    Color color,
    double width,
    List<InkPoint> points, {
    bool pressure = false,
  }) => Stroke(
    id: 's${n++}',
    tool: tool,
    color: color.toARGB32(),
    width: width,
    points: points,
    createdAt: n,
    pressureSensitive: pressure,
  );

  return [
    make(InkTool.highlighter, ink[2].withValues(alpha: 0.35), 30, [
      for (var x = 140.0; x <= 1000; x += 20) InkPoint(x, 330),
    ]),
    make(InkTool.pen, ink[0], 6, pressure: true, [
      for (var i = 0; i <= 120; i++)
        InkPoint(
          140 + i * 8.0,
          320 + math.sin(i / 6) * 30,
          0.2 + 0.8 * (math.sin(i / 20) + 1) / 2,
        ),
    ]),
    make(InkTool.pen, ink[1], 6, [
      for (var i = 0; i <= 200; i++)
        InkPoint(
          700 + math.cos(i / 10) * i * 1.5,
          900 + math.sin(i / 10) * i * 1.5,
        ),
    ]),
    make(InkTool.pen, ink[3], 12, const [InkPoint(300, 900)]),
  ];
}

void main() {
  late List<SkinManifest> skins;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    skins = await loadTestSkins();
  });

  for (final id in ['classic', 'minimal_dark']) {
    testWidgets('ink on a $id page', (tester) async {
      tester.view
        ..physicalSize = const Size(600, 820)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final skin = skinById(skins, id);
      final auth = DevAuthRepository();
      await auth.signInWithEmail('sam@example.com', 'secret1');
      final backend = InMemoryNotesBackend();
      for (final s in sampleInk(skin.inkColors)) {
        await backend.strokes(auth.currentUser!.uid).addStroke('p', s);
      }
      final container = await makeContainer(
        skins,
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          notesBackendProvider.overrideWithValue(backend),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: themed(skin, const PageCanvas(pageId: 'p', readOnly: true)),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(PageCanvas),
        matchesGoldenFile('ink/$id.png'),
      );
    });
  }
}
