import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:motley/core/skins/skin_manifest.dart';

Map<String, dynamic> validJson() => jsonDecode('''
{
  "schemaVersion": 1,
  "id": "test_skin",
  "version": 2,
  "name": "Test",
  "description": "A skin for tests.",
  "tier": "free",
  "brightness": "light",
  "colors": {
    "primary": "#112233", "onPrimary": "#FFFFFF",
    "secondary": "#445566", "onSecondary": "#FFFFFF",
    "background": "#F0F0F0", "surface": "#FFFFFF", "onSurface": "#000000",
    "outline": "#888888", "error": "#B00020"
  },
  "paper": { "color": "#FFFFFF", "lineColor": "#CCCCCC", "pattern": "grid", "spacing": 24 },
  "inkColors": ["#000000", "#80FF0000"],
  "typography": { "heading": "Inter", "body": "Inter", "accent": "Caveat" },
  "cornerRadius": 12
}
''') as Map<String, dynamic>;

void main() {
  group('SkinManifest.fromJson', () {
    test('parses a valid manifest', () {
      final skin = SkinManifest.fromJson(validJson());

      expect(skin.id, 'test_skin');
      expect(skin.version, 2);
      expect(skin.tier, SkinTier.free);
      expect(skin.isFree, isTrue);
      expect(skin.brightness, Brightness.light);
      expect(skin.colors.primary, const Color(0xFF112233));
      expect(skin.paper.pattern, PaperPattern.grid);
      expect(skin.paper.spacing, 24);
      expect(skin.paper.marginColor, isNull);
      expect(skin.inkColors, [
        const Color(0xFF000000),
        const Color(0x80FF0000),
      ]);
      expect(skin.typography.accent, 'Caveat');
      expect(skin.stickers, isEmpty);
    });

    void expectInvalid(
      void Function(Map<String, dynamic> json) change,
      String messagePart,
    ) {
      final json = validJson();
      change(json);
      expect(
        () => SkinManifest.fromJson(json),
        throwsA(
          isA<SkinManifestException>().having(
            (e) => e.message,
            'message',
            contains(messagePart),
          ),
        ),
      );
    }

    test('rejects a bad id', () {
      expectInvalid((j) => j['id'] = 'Has Spaces', '"id"');
    });

    test('rejects an unknown schema version', () {
      expectInvalid((j) => j['schemaVersion'] = 2, 'schemaVersion');
    });

    test('names the missing field, including its path', () {
      expectInvalid(
        (j) => (j['colors'] as Map).remove('surface'),
        '"colors.surface"',
      );
    });

    test('rejects malformed colors', () {
      expectInvalid(
        (j) => (j['paper'] as Map)['color'] = 'white',
        'paper.color',
      );
      expectInvalid((j) => j['inkColors'] = ['#12345'], 'inkColors');
    });

    test('rejects an empty ink palette', () {
      expectInvalid((j) => j['inkColors'] = <String>[], 'inkColors');
    });

    test('rejects unknown enum values', () {
      expectInvalid((j) => j['tier'] = 'gold', '"tier"');
      expectInvalid((j) => (j['paper'] as Map)['pattern'] = 'hex', 'pattern');
    });

    test('rejects out-of-range spacing', () {
      expectInvalid((j) => (j['paper'] as Map)['spacing'] = 2, 'spacing');
    });

    test('requires a productId for paid skins', () {
      expectInvalid((j) => j['tier'] = 'paid', 'productId');

      final json = validJson()
        ..['tier'] = 'paid'
        ..['productId'] = 'skin_test';
      expect(SkinManifest.fromJson(json).productId, 'skin_test');
    });
  });

  group('parseHexColor', () {
    test('accepts #RRGGBB and #AARRGGBB', () {
      expect(parseHexColor('#ff0000'), const Color(0xFFFF0000));
      expect(parseHexColor('#80FF0000'), const Color(0x80FF0000));
    });

    test('returns null for anything else', () {
      for (final bad in ['ff0000', '#fff', '#GG0000', 'red', '']) {
        expect(parseHexColor(bad), isNull, reason: bad);
      }
    });
  });
}
