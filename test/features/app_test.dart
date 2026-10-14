import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motley/core/skins/motley_skin.dart';
import 'package:motley/core/skins/skin_manifest.dart';
import 'package:motley/features/auth/sign_in_screen.dart';

import '../helpers.dart';

void main() {
  late List<SkinManifest> skins;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    skins = await loadTestSkins();
  });

  /// The skin used to draw [at] (by default, the screen on top).
  String skinAt(WidgetTester tester, [Finder? at]) =>
      Theme.of(tester.element(at ?? find.byType(Scaffold).last))
          .extension<MotleySkin>()!
          .id;

  group('sign-in', () {
    testWidgets('signed-out users see the sign-in screen', (tester) async {
      await pumpApp(tester, skins, signedIn: false);

      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.text('Continue with Apple'), findsOneWidget);
    });

    testWidgets('signing in with email opens Notebooks', (tester) async {
      await pumpApp(tester, skins, signedIn: false);

      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'a@b.co');
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'secret1',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.byType(SignInScreen), findsNothing);
      expect(find.widgetWithText(AppBar, 'Notebooks'), findsOneWidget);
    });

    testWidgets('shows an error for a short password', (tester) async {
      await pumpApp(tester, skins, signedIn: false);

      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'a@b.co');
      await tester.enterText(find.widgetWithText(TextField, 'Password'), '123');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.textContaining('at least 6'), findsOneWidget);
      expect(find.byType(SignInScreen), findsOneWidget);
    });

    testWidgets('signing out returns to sign-in', (tester) async {
      await pumpApp(tester, skins);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(find.byType(SignInScreen), findsOneWidget);
    });
  });

  group('layout', () {
    testWidgets('phones get a bottom navigation bar', (tester) async {
      await pumpApp(tester, skins, size: const Size(390, 844));

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('tablets get a navigation rail', (tester) async {
      await pumpApp(tester, skins, size: const Size(820, 1180));

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('wide screens get an extended sidebar', (tester) async {
      await pumpApp(tester, skins, size: const Size(1366, 1024));

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isTrue);
    });

    testWidgets('tabs switch between sections', (tester) async {
      await pumpApp(tester, skins);

      for (final tab in ['Planner', 'Calendar', 'To-do', 'Notebooks']) {
        await tester.tap(find.widgetWithText(NavigationDestination, tab));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(AppBar, tab), findsOneWidget);
      }
    });
  });

  group('skins', () {
    testWidgets('picking a free skin applies it to the whole app', (
      tester,
    ) async {
      await pumpApp(tester, skins);
      expect(skinAt(tester), 'classic');

      await tester.tap(find.byTooltip('Skins'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pastel'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Use this skin'), 200);
      await tester.tap(find.text('Use this skin'));
      await tester.pumpAndSettle();

      expect(find.text('In use'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(skinAt(tester), 'pastel');
    });

    testWidgets('the saved skin is used on launch', (tester) async {
      await pumpApp(tester, skins, prefs: {'activeSkinId': 'minimal_dark'});

      expect(skinAt(tester), 'minimal_dark');
    });

    testWidgets('locked skins can be previewed but not applied', (
      tester,
    ) async {
      await pumpApp(tester, skins);

      await tester.tap(find.byTooltip('Skins'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Botanical'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Botanical'));
      await tester.pumpAndSettle();

      // The preview screen is drawn in the Botanical skin.
      expect(
        skinAt(tester, find.byWidgetPredicate((w) => w is SegmentedButton)),
        'botanical',
      );
      await tester.scrollUntilVisible(find.text('Unlock this skin'), 200);
      final button = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Unlock this skin'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('the preview switches between page types', (tester) async {
      await pumpApp(tester, skins);

      await tester.tap(find.byTooltip('Skins'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kraft Paper'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('To-do'));
      await tester.pumpAndSettle();
      expect(find.text('This week'), findsOneWidget);

      await tester.tap(find.byTooltip('Planner'));
      await tester.pumpAndSettle();
      expect(find.text('SCHEDULE'), findsOneWidget);
    });
  });
}
