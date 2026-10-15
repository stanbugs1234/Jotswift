import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/catalog/catalog_item.dart';
import 'package:notely/core/catalog/catalog_providers.dart';
import 'package:notely/core/catalog/catalog_repository.dart';
import 'package:notely/core/catalog/pack_cache.dart';
import 'package:notely/core/catalog/pack_disk_memory.dart';
import 'package:notely/core/entitlements/entitlements.dart';
import 'package:notely/core/settings/user_settings_repository.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/auth/auth_repository.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';
import 'package:notely/features/notebooks/notes_providers.dart';
import 'package:notely/features/shelf/cover_view.dart';

import '../../core/catalog/catalog_test.dart' show FakeDownloader, zip;
import '../../helpers.dart';

/// A 1x1 PNG (decodable, unlike made-up bytes).
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAj'
  'CB0C8AAAAASUVORK5CYII=',
);

CatalogItem cover(
  String id,
  FakeDownloader downloader, {
  String visibility = 'public',
  Map<String, Object?> unlock = const {'free': true},
}) {
  final pack = zip({'cover.webp': _png});
  downloader.files['catalog/$id/1/pack.zip'] = pack;
  downloader.files['catalog/$id/1/preview.webp'] = Uint8List.fromList(_png);
  return CatalogItem.fromMap(id, {
    'kind': 'cover',
    'name': id == 'night_sky' ? 'Night Sky' : id,
    'version': 1,
    'visibility': visibility,
    'unlock': unlock,
    'color': 0xFF1C2A57,
    'files': {
      'pack': 'catalog/$id/1/pack.zip',
      'sha256': sha256.convert(pack).toString(),
      'bytes': pack.length,
      'preview': 'catalog/$id/1/preview.webp',
    },
  })!;
}

final sageDot = CatalogItem.fromMap('sage_dot', {
  'kind': 'paper',
  'name': 'Sage Dot',
  'version': 1,
  'visibility': 'public',
  'unlock': {'free': true},
  'paper': {
    'color': 0xFFEEF2EA,
    'lineColor': 0xFFAFC0A8,
    'pattern': 'dot',
    'spacing': 26,
  },
})!;

void main() {
  late List<SkinManifest> skins;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    skins = await loadTestSkins();
  });

  group('offered items', () {
    test('only readable, visible items the user may use', () async {
      final d = FakeDownloader();
      final settings = InMemoryUserSettingsRepository();
      final auth = DevAuthRepository();
      await auth.signInWithEmail('sam@example.com', 'secret1');
      final container = await makeContainer(
        skins,
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          userSettingsRepositoryProvider.overrideWithValue(settings),
          catalogRepositoryProvider.overrideWithValue(
            InMemoryCatalogRepository([
              cover('free', d),
              cover('hidden', d, visibility: 'hidden'),
              cover('retired', d, visibility: 'retired'),
              cover('beta', d, visibility: 'testers'),
              cover('pro', d, unlock: {'pro': true}),
              sageDot,
            ]),
          ),
        ],
      );
      List<String> ids(CatalogKind kind) => [
        for (final i in container.read(offeredCatalogProvider(kind))) i.id,
      ];
      container
        ..listen(catalogProvider, (_, _) {})
        ..listen(isTesterProvider, (_, _) {});
      await pumpEventQueue();

      expect(ids(CatalogKind.cover), ['free']);
      expect(ids(CatalogKind.paper), ['sage_dot']);

      settings.setTester(auth.currentUser!.uid, tester: true);
      await pumpEventQueue();
      // Testers also get Pro, so they can try paid items too.
      expect(ids(CatalogKind.cover), ['free', 'beta', 'pro']);
    });

    test('Pro items are offered with Pro', () async {
      final d = FakeDownloader();
      final container = await makeContainer(
        skins,
        overrides: [
          catalogRepositoryProvider.overrideWithValue(
            InMemoryCatalogRepository([
              cover('pro', d, unlock: {'pro': true}),
            ]),
          ),
          entitlementsProvider.overrideWithValue(const Entitlements(pro: true)),
        ],
      );
      container.listen(catalogProvider, (_, _) {});
      await pumpEventQueue();
      expect(
        container.read(offeredCatalogProvider(CatalogKind.cover)),
        hasLength(1),
      );
    });
  });

  group('pickers', () {
    late InMemoryNotesBackend backend;
    late InMemoryCatalogRepository catalog;
    late FakeDownloader downloader;
    late String uid;

    Future<void> pump(WidgetTester tester) async {
      backend = InMemoryNotesBackend();
      downloader = FakeDownloader();
      catalog = InMemoryCatalogRepository([
        cover('night_sky', downloader),
        sageDot,
      ]);
      final auth = await pumpApp(
        tester,
        skins,
        size: const Size(900, 2600),
        overrides: [
          notesBackendProvider.overrideWithValue(backend),
          catalogRepositoryProvider.overrideWithValue(catalog),
          packCacheProvider.overrideWithValue(
            PackCache(downloader, MemoryPackDisk()),
          ),
        ],
      );
      uid = auth.currentUser!.uid;
    }

    Future<Notebook> onlyNotebook() async =>
        (await backend.notebooks(uid).watchNotebooks().first).single;

    Future<void> tap(WidgetTester tester, Finder finder) async {
      await tester.tap(finder.last);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }

    testWidgets('a catalog cover can be picked and is downloaded', (
      tester,
    ) async {
      await pump(tester);
      await tap(tester, find.text('New notebook'));
      await tap(tester, find.text('Designs'));

      expect(find.text('More covers'), findsOneWidget);
      await tap(tester, find.bySemanticsLabel('Night Sky cover'));
      await tap(tester, find.text('Create'));

      final nb = await onlyNotebook();
      expect(nb.cover.kind, CoverKind.art);
      expect(nb.cover.coverId, 'night_sky');
      expect(downloader.requested, contains('catalog/night_sky/1/pack.zip'));

      await tester.pageBack();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(CoverView),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a catalog paper can be picked', (tester) async {
      await pump(tester);
      await tap(tester, find.text('New notebook'));

      expect(find.text('More papers'), findsOneWidget);
      await tap(tester, find.bySemanticsLabel('Sage Dot paper'));
      await tap(tester, find.text('Create'));

      expect((await onlyNotebook()).paper, sageDot.paper);
      expect((await onlyNotebook()).paper!.pattern, PaperPattern.dot);
    });

    testWidgets('a retired cover still shows on notebooks that use it', (
      tester,
    ) async {
      await pump(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      );
      await container
          .read(notebookRepositoryProvider)
          .createNotebook(
            const NewNotebook(
              title: 'Old',
              cover: NotebookCover.art('night_sky', color: 0xFF1C2A57),
            ),
          );
      catalog.items = [cover('night_sky', downloader, visibility: 'retired')];
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(CoverView),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );
      // It isn't offered for new notebooks any more.
      await tap(tester, find.text('New notebook'));
      await tap(tester, find.text('Designs'));
      expect(find.text('More covers'), findsNothing);
    });
  });
}
