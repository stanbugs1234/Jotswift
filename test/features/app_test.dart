import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/app/app.dart';
import 'package:notely/app/router.dart';
import 'package:notely/core/skins/notely_skin.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/auth/sign_in_screen.dart';
import 'package:notely/features/canvas/page_canvas.dart';

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
          .extension<NotelySkin>()!
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

    testWidgets('a link opened while signed out comes back after sign-in', (
      tester,
    ) async {
      await pumpApp(tester, skins, signedIn: false);
      final router = ProviderScope.containerOf(
        tester.element(find.byType(NotelyApp)),
      ).read(routerProvider);
      router.go('/todo');
      await tester.pumpAndSettle();
      expect(find.byType(SignInScreen), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'a@b.co');
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'secret1',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path, '/todo');
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

    testWidgets('wide screens get a sidebar with the shelf categories', (
      tester,
    ) async {
      await pumpApp(tester, skins, size: const Size(1366, 1024));

      expect(find.byType(NavigationRail), findsNothing);
      expect(find.text('All notebooks'), findsOneWidget);
      expect(find.text('CATEGORIES'), findsOneWidget);
      expect(find.text('Planner'), findsOneWidget);
    });

    testWidgets('tabs switch between sections', (tester) async {
      await pumpApp(tester, skins);

      for (final (tab, title) in [
        ('Planner', 'Today'),
        ('Calendar', 'Month'),
        ('To-do', 'Today'),
        ('Notebooks', 'Notebooks'),
      ]) {
        await tester.tap(find.widgetWithText(NavigationDestination, tab));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(AppBar, title), findsWidgets);
      }
    });
  });

  group('notebook styles', () {
    /// The style the Planner's notes page is drawn in (the default style).
    Future<String> sampleStyle(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(NavigationDestination, 'Planner'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();
      return skinAt(tester, find.byType(PageCanvas));
    }

    testWidgets('picking a style changes pages but not the app screens', (
      tester,
    ) async {
      await pumpApp(tester, skins);
      final background = Theme.of(tester.element(find.byType(Scaffold).last))
          .scaffoldBackgroundColor;

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notebook style'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pastel'));
      await tester.pumpAndSettle();

      expect(find.text('In use'), findsOneWidget);
      for (var i = 0; i < 2; i++) {
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      expect(await sampleStyle(tester), 'pastel');
      expect(
        Theme.of(tester.element(find.byType(Scaffold).last))
            .scaffoldBackgroundColor,
        background,
      );
    });

    testWidgets('the saved style is used on launch', (tester) async {
      await pumpApp(tester, skins, prefs: {'activeSkinId': 'minimal_dark'});

      expect(await sampleStyle(tester), 'minimal_dark');
    });

    testWidgets('a Pro style asks for Pro', (tester) async {
      await pumpApp(tester, skins);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notebook style'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Botanical'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Botanical'));
      await tester.pumpAndSettle();

      expect(find.text('Botanical is included in Jotswift Pro.'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('In use'), findsOneWidget, reason: 'Classic still');
      expect(find.text('Botanical is included in Jotswift Pro.'), findsNothing);
    });
  });

  group('appearance', () {
    Brightness brightness(WidgetTester tester) =>
        Theme.of(tester.element(find.byType(Scaffold).last)).brightness;

    testWidgets('follows the system until changed in Settings', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await pumpApp(tester, skins);
      expect(brightness(tester), Brightness.dark);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(brightness(tester), Brightness.light);
    });

    testWidgets('the saved appearance is used on launch', (tester) async {
      await pumpApp(tester, skins, prefs: {'appearance': 'dark'});

      expect(brightness(tester), Brightness.dark);
    });

    testWidgets('pages keep their paper in dark mode', (tester) async {
      await pumpApp(tester, skins, prefs: {'appearance': 'dark'});

      await tester.tap(find.widgetWithText(NavigationDestination, 'Planner'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();
      final style = Theme.of(tester.element(find.byType(PageCanvas)))
          .extension<NotelySkin>()!;
      expect(style.id, 'classic');
      expect(style.paperColor, skinById(skins, 'classic').paper.color);
    });
  });
}
