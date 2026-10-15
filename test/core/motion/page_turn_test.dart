import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/app/router.dart';
import 'package:notely/core/motion/motion.dart';
import 'package:notely/core/motion/page_turn.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/canvas/page_canvas.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';
import 'package:notely/features/notebooks/notes_providers.dart';
import 'package:notely/features/notebooks/page_order.dart';

import '../../helpers.dart';

void main() {
  late List<SkinManifest> skins;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    skins = await loadTestSkins();
  });

  group('page order', () {
    NotePage page(String id, String section, double order) => NotePage(
      id: id,
      notebookId: 'nb',
      sectionId: section,
      title: id,
      order: order,
      createdAt: 0,
      updatedAt: 0,
    );
    const sections = [
      Section(id: 's1', notebookId: 'nb', title: 'One', order: 1),
      Section(id: 's2', notebookId: 'nb', title: 'Two', order: 2),
    ];

    test('goes section by section, then by page order', () {
      final order = orderPages(sections, [
        page('b2', 's2', 1),
        page('a2', 's1', 2),
        page('a1', 's1', 1),
        page('lost', 'gone', 1),
      ]);
      expect(order, ['a1', 'a2', 'b2', 'lost']);
    });

    test('knows the neighbours of a page', () {
      final order = ['a', 'b', 'c'];
      expect(adjacentPages(order, 'a'), (previous: null, next: 'b'));
      expect(adjacentPages(order, 'b'), (previous: 'a', next: 'c'));
      expect(adjacentPages(order, 'c'), (previous: 'b', next: null));
      expect(adjacentPages(order, 'x'), (previous: null, next: null));
    });

    test('turns backward only towards earlier pages', () {
      final order = ['a', 'b', 'c'];
      expect(directionBetween(order, 'a', 'c'), TurnDirection.forward);
      expect(directionBetween(order, 'c', 'a'), TurnDirection.backward);
      expect(directionBetween(order, 'a', 'x'), TurnDirection.forward);
    });
  });

  group('turning pages', () {
    /// Opens page 1 of a 3-page notebook (pages titled P1, P2, P3).
    Future<void> openFirstPage(
      WidgetTester tester, {
      Map<String, Object> prefs = const {},
    }) async {
      final backend = InMemoryNotesBackend();
      final auth = await pumpApp(
        tester,
        skins,
        size: const Size(800, 1000),
        prefs: prefs,
        overrides: [notesBackendProvider.overrideWithValue(backend)],
      );
      final repo = backend.notebooks(auth.currentUser!.uid);
      final nb = await repo.createNotebook(
        NewNotebook(title: 'Book', cover: NotebookCover.color(0)),
      );
      final section = (await repo.watchSections(nb.id).first).single;
      final ids = <String>[];
      for (var i = 1; i <= 3; i++) {
        final p = await repo.createPage(nb.id, section.id);
        await repo.renamePage(p.id, 'P$i');
        ids.add(p.id);
      }
      final router = ProviderScope.containerOf(
        tester.element(find.byType(Navigator).first),
      ).read(routerProvider);
      router.go('/notebooks/${nb.id}/pages/${ids.first}');
      await tester.pumpAndSettle();
    }

    String title(WidgetTester tester) => tester
        .widget<Text>(
          find.descendant(of: find.byType(AppBar), matching: find.byType(Text)),
        )
        .data!;

    testWidgets('Next and Previous move through the notebook', (tester) async {
      await openFirstPage(tester);
      expect(title(tester), 'P1');

      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(title(tester), 'P2');

      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(title(tester), 'P3');
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.chevron_right),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.byTooltip('Previous page'));
      await tester.pumpAndSettle();
      expect(title(tester), 'P2');
    });

    testWidgets('both pages show while turning, then only the new one', (
      tester,
    ) async {
      await openFirstPage(tester);

      await tester.tap(find.byTooltip('Next page'));
      await tester.pump();
      await tester.pump(MotionTokens.emphasized ~/ 2);
      expect(find.byType(PageCanvas), findsNWidgets(2));
      // The page being turned away can't be drawn on.
      expect(
        find.ancestor(
          of: find.byType(PageCanvas).first,
          matching: find.byType(IgnorePointer),
        ),
        findsWidgets,
      );

      await tester.pumpAndSettle();
      expect(find.byType(PageCanvas), findsOneWidget);
      // Still the same screen: it was updated, not replaced.
      expect(find.byType(PageTurnSwitcher), findsOneWidget);
    });

    testWidgets('with animations off, the page changes at once', (
      tester,
    ) async {
      await openFirstPage(tester, prefs: {'animationLevel': 'off'});

      await tester.tap(find.byTooltip('Next page'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      // No second page turning on screen at any point.
      expect(find.byType(PageCanvas), findsOneWidget);
      await tester.pumpAndSettle();
      expect(title(tester), 'P2');
    });

    testWidgets('going back to the shelf still works', (tester) async {
      await openFirstPage(tester);
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();

      final router = ProviderScope.containerOf(
        tester.element(find.byType(Navigator).first),
      ).read(routerProvider);
      router.go('/notebooks');
      await tester.pumpAndSettle();
      expect(find.byType(PageCanvas), findsNothing);
      expect(router.state.uri.path, '/notebooks');
    });
  });

  group('Motion', () {
    Future<Motion> motionWith(
      WidgetTester tester, {
      required String level,
      required bool reduceMotion,
    }) async {
      late Motion motion;
      final container = await makeContainer(
        skins,
        prefs: {'animationLevel': level},
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: MotionScope(
              child: Builder(
                builder: (context) {
                  motion = Motion.of(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      return motion;
    }

    testWidgets('Reduce Motion turns Full into Reduced', (tester) async {
      final m = await motionWith(tester, level: 'full', reduceMotion: true);
      expect(m.level, AnimationLevel.reduced);
      expect(m.duration(MotionTokens.emphasized), MotionTokens.fade);
    });

    testWidgets('Off means no time at all', (tester) async {
      final m = await motionWith(tester, level: 'off', reduceMotion: false);
      expect(m.duration(MotionTokens.emphasized), Duration.zero);
    });

    testWidgets('Full keeps the real durations', (tester) async {
      final m = await motionWith(tester, level: 'full', reduceMotion: false);
      expect(m.duration(MotionTokens.emphasized), MotionTokens.emphasized);
    });
  });
}
