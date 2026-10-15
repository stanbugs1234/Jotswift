import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/skins/notely_skin.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/core/skins/skin_repository.dart';

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
    expect(skins.where((s) => !s.pro).map((s) => s.id), [
      'classic',
      'minimal_dark',
      'pastel',
      'kraft',
    ]);
  });

  group('interface themes', () {
    for (final dark in [false, true]) {
      test('${dark ? 'dark' : 'light'} text colors are readable', () async {
        final interface = await SkinRepository(rootBundle).loadInterface();
        final skin = dark ? interface.dark : interface.light;
        final c = skin.colors;
        expect(skin.brightness, dark ? Brightness.dark : Brightness.light);
        expect(contrast(c.onSurface, c.surface), greaterThanOrEqualTo(4.5));
        expect(contrast(c.onSurface, c.background), greaterThanOrEqualTo(4.5));
        expect(contrast(c.onPrimary, c.primary), greaterThanOrEqualTo(4.5));
        expect(contrast(c.onSecondary, c.secondary), greaterThanOrEqualTo(3));
      });
    }
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

      test('builds a theme with a NotelySkin extension', () {
        final theme = testEngine.buildTheme(skin);
        final ext = theme.extension<NotelySkin>()!;

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
