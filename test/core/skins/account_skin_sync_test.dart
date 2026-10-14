import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/settings/user_settings_repository.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/core/skins/skin_providers.dart';
import 'package:notely/features/auth/auth_repository.dart';

import '../../helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<SkinManifest> skins;

  setUpAll(() async => skins = await loadTestSkins());

  /// A container signed in as [email], sharing [settings] (the "server").
  Future<ProviderContainer> signedInDevice(
    InMemoryUserSettingsRepository settings, {
    String email = 'sam@example.com',
    Map<String, Object> prefs = const {},
  }) async {
    final auth = DevAuthRepository();
    await auth.signInWithEmail(email, 'secret1');
    final container = await makeContainer(
      skins,
      prefs: prefs,
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        userSettingsRepositoryProvider.overrideWithValue(settings),
      ],
    );
    // Keep the providers alive, as the running app would.
    container.listen(activeSkinIdProvider, (_, _) {});
    await pumpEventQueue();
    return container;
  }

  String uidFor(String email) => 'dev-${email.hashCode}';

  test('a picked skin is saved to the account', () async {
    final settings = InMemoryUserSettingsRepository();
    final device = await signedInDevice(settings);

    await device
        .read(activeSkinIdProvider.notifier)
        .select(skinById(skins, 'kraft'));
    await pumpEventQueue();

    expect(
      await settings.watchActiveSkinId(uidFor('sam@example.com')).first,
      'kraft',
    );
  });

  test("a new device picks up the account's skin", () async {
    final settings = InMemoryUserSettingsRepository();
    await settings.setActiveSkinId(uidFor('sam@example.com'), 'pastel');

    final device = await signedInDevice(settings);

    expect(device.read(activeSkinProvider).id, 'pastel');
    expect(
      device.read(sharedPreferencesProvider).getString('activeSkinId'),
      'pastel',
    );
  });

  test('a change on one device reaches another', () async {
    final settings = InMemoryUserSettingsRepository();
    final phone = await signedInDevice(settings);
    final tablet = await signedInDevice(settings);

    await phone
        .read(activeSkinIdProvider.notifier)
        .select(skinById(skins, 'minimal_dark'));
    await pumpEventQueue();

    expect(tablet.read(activeSkinProvider).id, 'minimal_dark');
  });

  test("first sign-in keeps the device's skin and saves it", () async {
    final settings = InMemoryUserSettingsRepository();

    final device = await signedInDevice(
      settings,
      prefs: {'activeSkinId': 'kraft'},
    );

    expect(device.read(activeSkinProvider).id, 'kraft');
    expect(
      await settings.watchActiveSkinId(uidFor('sam@example.com')).first,
      'kraft',
    );
  });

  test('accounts do not share skins', () async {
    final settings = InMemoryUserSettingsRepository();
    final sam = await signedInDevice(settings);
    final alex = await signedInDevice(settings, email: 'alex@example.com');

    await sam
        .read(activeSkinIdProvider.notifier)
        .select(skinById(skins, 'pastel'));
    await pumpEventQueue();

    expect(alex.read(activeSkinProvider).id, 'classic');
  });
}
