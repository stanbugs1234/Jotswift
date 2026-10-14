import 'package:flutter_test/flutter_test.dart';
import 'package:motley/core/entitlements/entitlements.dart';
import 'package:motley/core/skins/motley_skin.dart';
import 'package:motley/core/skins/skin_manifest.dart';
import 'package:motley/core/skins/skin_providers.dart';

import '../../helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<SkinManifest> skins;

  setUpAll(() async => skins = await loadTestSkins());

  test('starts on the Classic skin', () async {
    final container = await makeContainer(skins);

    expect(container.read(activeSkinProvider).id, 'classic');
    expect(
      container.read(themeProvider).extension<MotleySkin>()!.id,
      'classic',
    );
  });

  test('selecting a free skin applies and remembers it', () async {
    final container = await makeContainer(skins);
    final pastel = skinById(skins, 'pastel');

    final ok = await container
        .read(activeSkinIdProvider.notifier)
        .select(pastel);

    expect(ok, isTrue);
    expect(container.read(activeSkinProvider).id, 'pastel');
    expect(
      container.read(sharedPreferencesProvider).getString('activeSkinId'),
      'pastel',
    );
  });

  test('restores the saved skin on launch', () async {
    final container = await makeContainer(
      skins,
      prefs: {'activeSkinId': 'kraft'},
    );

    expect(container.read(activeSkinProvider).id, 'kraft');
  });

  test('a locked skin cannot be selected', () async {
    final container = await makeContainer(skins);
    final botanical = skinById(skins, 'botanical');

    final ok = await container
        .read(activeSkinIdProvider.notifier)
        .select(botanical);

    expect(ok, isFalse);
    expect(container.read(activeSkinProvider).id, 'classic');
  });

  test('falls back to Classic if the saved skin is locked or gone', () async {
    for (final saved in ['botanical', 'deleted_skin']) {
      final container = await makeContainer(
        skins,
        prefs: {'activeSkinId': saved},
      );
      expect(container.read(activeSkinProvider).id, 'classic', reason: saved);
    }
  });

  test('an owned paid skin can be used', () async {
    final container = await makeContainer(
      skins,
      overrides: [
        entitlementsProvider.overrideWithValue(
          const Entitlements(ownedSkinIds: {'botanical'}),
        ),
      ],
    );
    final botanical = skinById(skins, 'botanical');

    expect(
      await container.read(activeSkinIdProvider.notifier).select(botanical),
      isTrue,
    );
    expect(container.read(activeSkinProvider).id, 'botanical');
  });

  group('Entitlements.canUseSkin', () {
    SkinManifest withTier(SkinTier tier) {
      final s = skinById(skins, 'classic');
      return SkinManifest(
        id: 'x',
        version: 1,
        name: 'X',
        description: '',
        tier: tier,
        productId: 'skin_x',
        brightness: s.brightness,
        colors: s.colors,
        paper: s.paper,
        inkColors: s.inkColors,
        typography: s.typography,
        cornerRadius: s.cornerRadius,
      );
    }

    test('free skins are always usable', () {
      expect(Entitlements.none.canUseSkin(withTier(SkinTier.free)), isTrue);
    });

    test('paid skins need to be owned', () {
      final paid = withTier(SkinTier.paid);
      expect(Entitlements.none.canUseSkin(paid), isFalse);
      expect(const Entitlements(ownedSkinIds: {'x'}).canUseSkin(paid), isTrue);
    });

    test('pro skins need Motley Pro', () {
      final pro = withTier(SkinTier.pro);
      expect(Entitlements.none.canUseSkin(pro), isFalse);
      expect(const Entitlements(pro: true).canUseSkin(pro), isTrue);
    });
  });
}
