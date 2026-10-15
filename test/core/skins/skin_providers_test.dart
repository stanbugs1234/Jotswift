import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/entitlements/entitlements.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/core/settings/appearance.dart';
import 'package:notely/core/skins/skin_providers.dart';
import 'package:notely/features/auth/auth_repository.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';
import 'package:notely/features/notebooks/notes_providers.dart';

import '../../helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<SkinManifest> skins;

  setUpAll(() async => skins = await loadTestSkins());

  test('starts on the Classic skin', () async {
    final container = await makeContainer(skins);

    expect(container.read(activeSkinProvider).id, 'classic');
    expect(container.read(defaultStyleProvider).id, 'classic');
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

  test('a Pro style needs Jotswift Pro', () async {
    final botanical = skinById(skins, 'botanical');
    expect(botanical.pro, isTrue);
    expect(Entitlements.none.canUseSkin(botanical), isFalse);
    expect(Entitlements.none.canUseSkin(skinById(skins, 'kraft')), isTrue);

    final container = await makeContainer(
      skins,
      overrides: [
        entitlementsProvider.overrideWithValue(const Entitlements(pro: true)),
      ],
    );
    expect(
      await container.read(activeSkinIdProvider.notifier).select(botanical),
      isTrue,
    );
    expect(container.read(activeSkinProvider).id, 'botanical');
  });

  group('notebook styles', () {
    /// A container signed in with one notebook that has [collectionId].
    Future<(ProviderContainer, String)> withNotebook(
      String? collectionId, {
      Entitlements entitlements = Entitlements.none,
      Map<String, Object> prefs = const {},
    }) async {
      final auth = DevAuthRepository();
      await auth.signInWithEmail('sam@example.com', 'secret1');
      final backend = InMemoryNotesBackend();
      final notebook = await backend
          .notebooks(auth.currentUser!.uid)
          .createNotebook(
            NewNotebook(
              title: 'Trip',
              cover: const NotebookCover.color(1),
              collectionId: collectionId,
            ),
          );
      final container = await makeContainer(
        skins,
        prefs: prefs,
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          notesBackendProvider.overrideWithValue(backend),
          entitlementsProvider.overrideWithValue(entitlements),
        ],
      );
      container.listen(notebookProvider(notebook.id), (_, _) {});
      await pumpEventQueue();
      return (container, notebook.id);
    }

    test('a notebook without its own style uses the default', () async {
      final (container, id) = await withNotebook(
        null,
        prefs: {'activeSkinId': 'kraft'},
      );
      expect(container.read(notebookSkinProvider(id)).id, 'kraft');
    });

    test('a notebook with its own style uses it', () async {
      final (container, id) = await withNotebook('pastel');
      expect(container.read(notebookSkinProvider(id)).id, 'pastel');
      expect(container.read(notebookStyleProvider(id)).id, 'pastel');
    });

    test('a notebook keeps a style that is no longer unlocked', () async {
      final (container, id) = await withNotebook(
        'botanical',
        prefs: {'activeSkinId': 'kraft'},
      );
      expect(container.read(notebookSkinProvider(id)).id, 'botanical');
    });

    test('a missing style falls back to the default style', () async {
      final (container, id) = await withNotebook(
        'retired_style',
        prefs: {'activeSkinId': 'kraft'},
      );
      expect(container.read(notebookSkinProvider(id)).id, 'kraft');
    });
  });

  group('interface themes', () {
    test('light and dark have the right brightness', () async {
      final container = await makeContainer(skins);
      expect(container.read(lightThemeProvider).brightness, Brightness.light);
      expect(container.read(darkThemeProvider).brightness, Brightness.dark);
    });

    test('appearance defaults to the system setting', () async {
      final container = await makeContainer(skins);
      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test('an unknown saved appearance follows the system', () async {
      final container = await makeContainer(
        skins,
        prefs: {'appearance': 'sepia'},
      );
      expect(container.read(themeModeProvider), ThemeMode.system);
    });
  });
}
