import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/app/app.dart';
import 'package:notely/core/skins/font_resolver.dart';
import 'package:notely/core/skins/skin_engine.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/core/skins/skin_providers.dart';
import 'package:notely/core/skins/skin_repository.dart';
import 'package:notely/features/auth/auth_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fonts can't be downloaded in tests, so use the platform font.
const testEngine = SkinEngine(fonts: PlatformFontResolver());

/// Loads the bundled skins and the interface themes. Call it in `setUpAll`:
/// assets can't be loaded inside `testWidgets`, whose clock is fake.
Future<List<SkinManifest>> loadTestSkins() async {
  _interface ??= await SkinRepository(rootBundle).loadInterface();
  return SkinRepository(rootBundle).loadBundled();
}

InterfaceSkins? _interface;

SkinManifest skinById(List<SkinManifest> skins, String id) =>
    skins.firstWhere((s) => s.id == id);

/// A container with the same overrides `main()` uses, plus test fonts.
Future<ProviderContainer> makeContainer(
  List<SkinManifest> skins, {
  Map<String, Object> prefs = const {},
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final interface = _interface;
  if (interface == null) throw StateError('Call loadTestSkins() first');
  final container = ProviderContainer(
    overrides: [
      interfaceSkinsProvider.overrideWithValue(interface),
      sharedPreferencesProvider.overrideWithValue(
        await SharedPreferences.getInstance(),
      ),
      bundledSkinsProvider.overrideWithValue(skins),
      fontResolverProvider.overrideWithValue(const PlatformFontResolver()),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Pumps the whole app at [size] (logical pixels).
Future<DevAuthRepository> pumpApp(
  WidgetTester tester,
  List<SkinManifest> skins, {
  Size size = const Size(400, 800),
  bool signedIn = true,
  Map<String, Object> prefs = const {},
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final auth = DevAuthRepository();
  if (signedIn) await auth.signInWithEmail('sam@example.com', 'secret1');

  final container = await makeContainer(
    skins,
    prefs: prefs,
    overrides: [authRepositoryProvider.overrideWithValue(auth)],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const NotelyApp()),
  );
  await tester.pumpAndSettle();
  return auth;
}

/// Wraps [child] in [skin]'s theme, for testing single widgets.
Widget themed(SkinManifest skin, Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: testEngine.buildTheme(skin),
  home: Scaffold(body: child),
);
