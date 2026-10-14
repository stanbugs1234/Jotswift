import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:motley/core/skins/motley_skin.dart';
import 'package:motley/core/skins/skin_manifest.dart';

import '../../helpers.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<SkinManifest> skins;

  setUpAll(() async => skins = await loadTestSkins());

  test('every skin in the catalog loads', () {
    final catalog = jsonDecode(
      File('assets/skins/catalog.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(skins.map((s) => s.id), catalog['skins']);
  });

  test('every skin folder is listed in the catalog and in pubspec.yaml', () {
    final folders = Directory('assets/skins')
        .listSync()
        .whereType<Directory>()
        .map((d) => d.uri.pathSegments[d.uri.pathSegments.length - 2]);
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final folder in folders) {
      expect(skins.map((s) => s.id), contains(folder));
      expect(pubspec, contains('- assets/skins/$folder/'), reason: folder);
    }
  });

  test('ships the four free skins from the plan, with classic as default', () {
    expect(skins.where((s) => s.isFree).map((s) => s.id), [
      'classic',
      'minimal_dark',
      'pastel',
      'kraft',
    ]);
  });

  for (final id in [
    'classic',
    'minimal_dark',
    'pastel',
    'kraft',
    'botanical',
  ]) {
    group(id, () {
      late SkinManifest skin;
      setUp(() => skin = skinById(skins, id));

      test('builds a theme with a MotleySkin extension', () {
        final theme = testEngine.buildTheme(skin);
        final ext = theme.extension<MotleySkin>()!;

        expect(theme.colorScheme.primary, skin.colors.primary);
        expect(theme.brightness, skin.brightness);
        expect(ext.id, skin.id);
        expect(ext.paperColor, skin.paper.color);
        expect(ext.inkColors, skin.inkColors);
        expect(theme.appBarTheme.titleTextStyle?.fontSize, 22);
      });

      // WCAG AA asks for 4.5:1 for normal text.
      test('text colors are readable', () {
        final c = skin.colors;
        expect(contrast(c.onSurface, c.surface), greaterThanOrEqualTo(4.5));
        expect(contrast(c.onSurface, c.background), greaterThanOrEqualTo(4.5));
        expect(
          contrast(c.onSurface, skin.paper.color),
          greaterThanOrEqualTo(4.5),
        );
        expect(contrast(c.onPrimary, c.primary), greaterThanOrEqualTo(4.5));
        expect(contrast(c.onSecondary, c.secondary), greaterThanOrEqualTo(3));
      });

      test('the first ink color stands out on the paper', () {
        expect(
          contrast(skin.inkColors.first, skin.paper.color),
          greaterThanOrEqualTo(4.5),
        );
      });
    });
  }
}
