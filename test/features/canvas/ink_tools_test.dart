import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/settings/synced_setting.dart';
import 'package:notely/features/canvas/domain/stroke.dart';
import 'package:notely/features/canvas/ink_tools.dart';
import 'package:notely/features/canvas/pencil_actions.dart';

import '../../helpers.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadTestSkins();
  });

  test('strokes keep their pen type; old strokes are fountain pen', () {
    final stroke = Stroke(
      id: 'a',
      tool: InkTool.pen,
      color: 0xFF000000,
      width: 4,
      points: const [InkPoint(1, 2)],
      createdAt: 1,
      style: PenStyle.pencil,
    );
    expect(Stroke.fromMap('a', stroke.toMap()).style, PenStyle.pencil);
    final old = stroke.toMap()..remove('style');
    expect(Stroke.fromMap('a', old).style, PenStyle.fountain);
    // Fountain (the default) isn't written, keeping documents small.
    final fountain = Stroke(
      id: 'b',
      tool: InkTool.pen,
      color: 0,
      width: 4,
      points: const [],
      createdAt: 1,
    );
    expect(fountain.toMap().containsKey('style'), isFalse);
  });

  test('the pen is remembered on the device', () async {
    final first = await makeContainer(await loadTestSkins());
    first.read(inkToolProvider.notifier)
      ..selectCustomColor(const Color(0xFF123456))
      ..selectPenStyle(PenStyle.brush)
      ..setWidth(9);
    first.read(inkToolProvider.notifier).selectTool(InkToolKind.lasso);
    final saved = jsonDecode(
      first.read(sharedPreferencesProvider).getString('inkTool')!,
    );

    final second = await makeContainer(
      await loadTestSkins(),
      prefs: {'inkTool': jsonEncode(saved)},
    );
    final tool = second.read(inkToolProvider);
    expect(tool.customColor, 0xFF123456);
    expect(tool.penStyle, PenStyle.brush);
    expect(tool.size, 9);
    // The lasso isn't kept: pages open ready to write.
    expect(tool.kind, InkToolKind.pen);
  });

  test('damaged saved pens are ignored', () async {
    final container = await makeContainer(
      await loadTestSkins(),
      prefs: {'inkTool': '{not json'},
    );
    expect(container.read(inkToolProvider).kind, InkToolKind.pen);
  });

  test('saved pens: added once, at most twelve, removable', () async {
    final container = await makeContainer(await loadTestSkins());
    final favorites = container.read(penFavoritesSettingProvider.notifier);
    for (var i = 0; i < 14; i++) {
      await favorites.add(
        PenFavorite(
          tool: InkTool.pen,
          style: PenStyle.ballpoint,
          color: i,
          width: 4,
        ),
      );
    }
    await favorites.add(
      const PenFavorite(
        tool: InkTool.pen,
        style: PenStyle.ballpoint,
        color: 13,
        width: 4,
      ),
    );
    final pens = container.read(penFavoritesProvider);
    expect(pens, hasLength(12));
    expect(pens.first.color, 2);
    expect(pens.last.color, 13);

    await favorites.remove(pens.first);
    expect(container.read(penFavoritesProvider), hasLength(11));
  });

  group('eraseFromStroke', () {
    var n = 0;
    String id() => 'piece${n++}';
    final line = Stroke(
      id: 'line',
      tool: InkTool.pen,
      color: 0xFF000000,
      width: 4,
      // Sparse points: the cut must still land where the eraser is.
      points: const [InkPoint(0, 0), InkPoint(100, 0), InkPoint(200, 0)],
      createdAt: 3,
      style: PenStyle.brush,
    );

    test('a cut in the middle leaves two pieces like the original', () {
      final pieces = eraseFromStroke(line, const Offset(50, 0), 10, id)!;
      expect(pieces, hasLength(2));
      expect(pieces.first.bounds.right, lessThan(40));
      expect(pieces.last.bounds.left, greaterThan(60));
      for (final p in pieces) {
        expect(p.createdAt, 3);
        expect(p.style, PenStyle.brush);
        expect(p.id, startsWith('piece'));
      }
    });

    test('a cut at the end leaves one piece', () {
      final pieces = eraseFromStroke(line, const Offset(200, 0), 10, id)!;
      expect(pieces, hasLength(1));
      expect(pieces.single.bounds.right, lessThan(190));
    });

    test('a miss is null; covering all of it leaves nothing', () {
      expect(eraseFromStroke(line, const Offset(50, 40), 10, id), isNull);
      expect(eraseFromStroke(line, const Offset(100, 0), 150, id), isEmpty);
    });
  });

  test('Pencil gestures use the iPad setting unless one is chosen here', () {
    expect(
      resolvePencilAction(PencilAction.system, 'switchEraser'),
      PencilAction.switchEraser,
    );
    expect(
      resolvePencilAction(PencilAction.system, 'showInkAttributes'),
      PencilAction.showColors,
    );
    expect(
      resolvePencilAction(PencilAction.system, 'ignore'),
      PencilAction.off,
    );
    expect(
      resolvePencilAction(PencilAction.switchPrevious, 'switchEraser'),
      PencilAction.switchPrevious,
    );
  });

  test('eraser and back, and the previous tool', () async {
    final container = await makeContainer(await loadTestSkins());
    final tools = container.read(inkToolProvider.notifier);
    tools.selectTool(InkToolKind.highlighter);
    tools.toggleEraser();
    expect(container.read(inkToolProvider).kind, InkToolKind.eraser);
    tools.toggleEraser();
    expect(container.read(inkToolProvider).kind, InkToolKind.highlighter);

    tools.selectTool(InkToolKind.lasso);
    tools.switchToPrevious();
    expect(container.read(inkToolProvider).kind, InkToolKind.highlighter);
  });
}
