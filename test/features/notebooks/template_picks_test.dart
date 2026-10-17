import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/notebooks/template_picks.dart';

import '../../helpers.dart';

void main() {
  late List<SkinManifest> skins;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    skins = await loadTestSkins();
  });

  TemplatePick pick(int page) =>
      TemplatePick(itemId: 'pages', pdfPage: page, title: 'Page $page');

  test('a starred page is a favorite until starred again', () async {
    final container = await makeContainer(skins);
    final favorites = container.read(favoriteTemplatePagesProvider.notifier);
    await favorites.toggle(pick(1));
    await favorites.toggle(pick(2));
    expect(favorites.picks, [pick(2), pick(1)], reason: 'newest first');
    expect(favorites.isFavorite(pick(1)), isTrue);

    await favorites.toggle(pick(1));
    expect(favorites.picks, [pick(2)]);
  });

  test('recent pages are newest first, once each, and capped', () async {
    final container = await makeContainer(skins);
    final recent = container.read(recentTemplatePagesProvider.notifier);
    for (var i = 1; i <= RecentTemplatePages.max + 3; i++) {
      await recent.add(pick(i));
    }
    await recent.add(pick(5));
    expect(recent.picks.first, pick(5));
    expect(recent.picks, hasLength(RecentTemplatePages.max));
    expect(recent.picks.where((p) => p == pick(5)), hasLength(1));
  });

  test('saved picks survive a restart, and bad data is ignored', () async {
    final container = await makeContainer(
      skins,
      prefs: {'recentTemplatePages': '[{"i":"a","p":3,"t":"Week"}, 7]'},
    );
    expect(container.read(recentTemplatePagesProvider.notifier).picks, [
      const TemplatePick(itemId: 'a', pdfPage: 3, title: 'Week'),
    ]);
    final broken = await makeContainer(
      skins,
      prefs: {'favoriteTemplatePages': 'not json'},
    );
    expect(broken.read(favoriteTemplatePagesProvider.notifier).picks, isEmpty);
  });
}
