import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/app/app.dart';
import 'package:notely/core/catalog/catalog_item.dart';
import 'package:notely/core/catalog/catalog_providers.dart';
import 'package:notely/core/catalog/catalog_repository.dart';
import 'package:notely/core/entitlements/entitlements.dart';
import 'package:notely/core/entitlements/feature_gate.dart';
import 'package:notely/core/purchases/purchases_client.dart';
import 'package:notely/core/purchases/purchases_providers.dart';
import 'package:notely/core/settings/user_settings_repository.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/auth/auth_repository.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';
import 'package:notely/features/notebooks/notes_providers.dart';
import 'package:notely/features/store/store_item.dart';

import '../../helpers.dart';

/// A store that sells [prices] and remembers what was bought.
class FakePurchases implements PurchasesClient {
  FakePurchases({this.prices = const {}, this.available = true});

  final Map<String, String> prices;
  final bool available;
  final bought = <String>{};
  final _receipts = StreamController<Entitlements>.broadcast();
  String? user;
  int restores = 0;

  /// What the next purchase does.
  PurchaseOutcome next = PurchaseOutcome.purchased;

  Entitlements get _receipt => Entitlements(
    pro: bought.any(ProProducts.isPro),
    products: {...bought.where((p) => !ProProducts.isPro(p))},
  );

  @override
  bool get isAvailable => available;

  @override
  Future<void> logIn(String uid) async => user = uid;

  @override
  Future<void> logOut() async => user = null;

  @override
  Stream<Entitlements> get receipts async* {
    yield _receipt;
    yield* _receipts.stream;
  }

  @override
  Future<Map<String, StoreOffer>> offers(List<String> productIds) async => {
    for (final id in productIds)
      if (prices[id] case final price?)
        id: StoreOffer(
          productId: id,
          title: 'Product $id',
          price: price,
          trialDays: id == ProProducts.yearly ? 7 : null,
        ),
  };

  @override
  Future<PurchaseOutcome> buy(String productId) async {
    if (next == PurchaseOutcome.purchased) {
      bought.add(productId);
      _receipts.add(_receipt);
    }
    return next;
  }

  @override
  Future<void> restore() async => restores++;
}

CatalogItem item(
  String id,
  String kind,
  Map<String, Object?> unlock, {
  Map<String, Object?> extra = const {},
}) => CatalogItem.fromMap(id, {
  'kind': kind,
  'name': id,
  'version': 1,
  'visibility': 'public',
  'unlock': unlock,
  ...extra,
})!;

const _paper = {
  'paper': {
    'color': 0xFFEEF2EA,
    'lineColor': 0xFFAFC0A8,
    'pattern': 'dot',
    'spacing': 26,
  },
};

final freePaper = item('free_paper', 'paper', {'free': true}, extra: _paper);
final soldPaper = item('sold_paper', 'paper', {
  'pro': true,
  'products': ['pack_sold'],
}, extra: _paper);
final proPaper = item('pro_paper', 'paper', {'pro': true}, extra: _paper);

void main() {
  late List<SkinManifest> skins;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    skins = await loadTestSkins();
  });

  group('Entitlements', () {
    final now = DateTime.utc(2026, 10, 14);

    test('read from the account', () {
      final e = Entitlements.fromMap({
        'pro': true,
        'proUntil': DateTime.utc(2026, 11, 14),
        'products': ['pack_a', 3, null],
        'grants': ['gift'],
      }, now: now);
      expect(e.pro, isTrue);
      expect(e.products, {'pack_a'});
      expect(e.grants, {'gift'});
      expect(Entitlements.fromMap('junk', now: now), Entitlements.none);
    });

    test('Pro that has ended is off', () {
      final e = Entitlements.fromMap({
        'pro': true,
        'proUntil': DateTime.utc(2026, 10, 1),
      }, now: now);
      expect(e.pro, isFalse);
      expect(
        Entitlements.fromMap({'pro': true}, now: now).pro,
        isTrue,
        reason: 'no end date',
      );
    });

    test('the device receipt adds to the account', () {
      final merged = const Entitlements(
        products: {'pack_a'},
        grants: {'gift'},
      ).merge(const Entitlements(pro: true, products: {'pack_b'}));
      expect(merged.pro, isTrue);
      expect(merged.products, {'pack_a', 'pack_b'});
      expect(merged.grants, {'gift'});
    });

    test('every unlock rule', () {
      expect(accessOf(Entitlements.none, freePaper), ItemAccess.free);
      expect(accessOf(Entitlements.none, soldPaper), ItemAccess.locked);
      expect(
        accessOf(const Entitlements(products: {'pack_sold'}), soldPaper),
        ItemAccess.owned,
      );
      expect(
        accessOf(const Entitlements(pro: true), soldPaper),
        ItemAccess.pro,
      );
      expect(
        accessOf(const Entitlements(grants: {'pro_paper'}), proPaper),
        ItemAccess.owned,
      );
      expect(accessOf(const Entitlements(pro: true), proPaper), ItemAccess.pro);
    });
  });

  group('entitlements of the signed-in user', () {
    Future<(ProviderContainer, InMemoryUserSettingsRepository)> setUp(
      PurchasesClient store,
    ) async {
      final auth = DevAuthRepository();
      await auth.signInWithEmail('sam@example.com', 'secret1');
      final settings = InMemoryUserSettingsRepository();
      final container = await makeContainer(
        skins,
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          userSettingsRepositoryProvider.overrideWithValue(settings),
          purchasesClientProvider.overrideWithValue(store),
        ],
      );
      container.listen(entitlementsProvider, (_, _) {});
      return (container, settings);
    }

    test('combine the account and this device\'s receipt', () async {
      final store = FakePurchases();
      final (container, settings) = await setUp(store);
      final uid = container.read(authRepositoryProvider).currentUser!.uid;
      await pumpEventQueue();
      expect(store.user, uid, reason: 'RevenueCat uses the Firebase uid');

      settings.setEntitlements(uid, {
        'products': ['pack_a'],
      });
      await store.buy(ProProducts.yearly);
      await pumpEventQueue();
      final e = container.read(entitlementsProvider);
      expect(e.pro, isTrue);
      expect(e.products, {'pack_a'});
    });

    test('the store logs out with the account', () async {
      final store = FakePurchases();
      final (container, _) = await setUp(store);
      await pumpEventQueue();
      await container.read(authRepositoryProvider).signOut();
      await pumpEventQueue();
      expect(store.user, isNull);
    });
  });

  group('notebook limit', () {
    Future<ProviderContainer> withNotebooks(
      int count,
      PurchasesClient store,
    ) async {
      final auth = DevAuthRepository();
      await auth.signInWithEmail('sam@example.com', 'secret1');
      final container = await makeContainer(
        skins,
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          purchasesClientProvider.overrideWithValue(store),
        ],
      );
      container.listen(canCreateNotebookProvider, (_, _) {});
      for (var i = 0; i < count; i++) {
        await container
            .read(notebookRepositoryProvider)
            .createNotebook(
              const NewNotebook(title: 'N', cover: NotebookCover.color(0)),
            );
      }
      await pumpEventQueue();
      return container;
    }

    test('free accounts have $freeNotebookLimit notebooks', () async {
      final container = await withNotebooks(
        freeNotebookLimit - 1,
        FakePurchases(),
      );
      expect(container.read(canCreateNotebookProvider), isTrue);
      await container
          .read(notebookRepositoryProvider)
          .createNotebook(
            const NewNotebook(title: 'N', cover: NotebookCover.color(0)),
          );
      await pumpEventQueue();
      expect(container.read(canCreateNotebookProvider), isFalse);
    });

    test('Pro has no limit', () async {
      final store = FakePurchases()..bought.add(ProProducts.monthly);
      final container = await withNotebooks(5, store);
      expect(container.read(canCreateNotebookProvider), isTrue);
    });

    test('no limit while the store isn\'t open', () async {
      final container = await withNotebooks(5, FakePurchases(available: false));
      expect(container.read(canCreateNotebookProvider), isTrue);
    });
  });

  group('Templates screen', () {
    Future<FakePurchases> open(
      WidgetTester tester, {
      FakePurchases? store,
    }) async {
      final purchases =
          store ??
          FakePurchases(
            prices: {
              'pack_sold': r'$1.99',
              ProProducts.yearly: r'$19.99',
              ProProducts.monthly: r'$2.99',
            },
          );
      await pumpApp(
        tester,
        skins,
        size: const Size(800, 1000),
        overrides: [
          purchasesClientProvider.overrideWithValue(purchases),
          catalogRepositoryProvider.overrideWithValue(
            InMemoryCatalogRepository([freePaper, soldPaper, proPaper]),
          ),
        ],
      );
      await tester.tap(find.text('Templates').first);
      await tester.pumpAndSettle();
      return purchases;
    }

    testWidgets('shows prices and what\'s free', (tester) async {
      await open(tester);
      expect(find.text('Papers'), findsOneWidget);
      expect(find.bySemanticsLabel('free_paper, Paper, Free'), findsOneWidget);
      expect(
        find.bySemanticsLabel(r'sold_paper, Paper, $1.99'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('pro_paper, Paper, Pro'), findsOneWidget);
    });

    testWidgets('buying an item unlocks it', (tester) async {
      final store = await open(tester);
      await tester.tap(find.bySemanticsLabel(RegExp('^sold_paper')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(r'Buy · $1.99'));
      await tester.pumpAndSettle();

      expect(store.bought, {'pack_sold'});
      expect(find.text('You own this'), findsOneWidget);
      expect(find.text('New notebook with this paper'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NotelyApp)),
      );
      expect(
        container.read(offeredCatalogProvider(CatalogKind.paper)),
        contains(soldPaper),
        reason: 'it now shows in the paper picker',
      );
    });

    testWidgets('a cancelled purchase changes nothing', (tester) async {
      final store = await open(tester)
        ..next = PurchaseOutcome.cancelled;
      await tester.tap(find.bySemanticsLabel(RegExp('^sold_paper')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(r'Buy · $1.99'));
      await tester.pumpAndSettle();
      expect(store.bought, isEmpty);
      expect(find.text('You own this'), findsNothing);
    });

    testWidgets('Pro unlocks Pro items, yearly with a trial first', (
      tester,
    ) async {
      final store = await open(tester);
      await tester.tap(find.text('Notely Pro'));
      await tester.pumpAndSettle();
      expect(find.text(r'$19.99/year'), findsOneWidget);
      expect(find.text('7 days free'), findsOneWidget);
      await tester.tap(find.text('Start free trial'));
      await tester.pumpAndSettle();

      expect(store.bought, {ProProducts.yearly});
      expect(find.text('Start free trial'), findsNothing, reason: 'closed');
      expect(
        find.bySemanticsLabel('pro_paper, Paper, In your Pro'),
        findsOneWidget,
      );
      expect(find.text('Notely Pro'), findsNothing, reason: 'no banner');
    });

    testWidgets('restore purchases', (tester) async {
      final store = await open(tester);
      await tester.tap(find.text('Restore purchases'));
      await tester.pumpAndSettle();
      expect(store.restores, 1);
      expect(find.text('Your purchases are restored.'), findsOneWidget);
    });

    testWidgets('nothing can be bought before the store opens', (tester) async {
      await open(tester, store: FakePurchases(available: false));
      expect(find.text('Restore purchases'), findsNothing);
      await tester.tap(find.bySemanticsLabel(RegExp('^sold_paper')));
      await tester.pumpAndSettle();
      expect(find.text('Purchases open soon.'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    });
  });

  testWidgets('a free account at the limit sees Pro before a new notebook', (
    tester,
  ) async {
    final store = FakePurchases(
      prices: {ProProducts.yearly: r'$19.99', ProProducts.monthly: r'$2.99'},
    );
    await pumpApp(
      tester,
      skins,
      overrides: [purchasesClientProvider.overrideWithValue(store)],
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NotelyApp)),
    );
    for (var i = 0; i < freeNotebookLimit; i++) {
      await container
          .read(notebookRepositoryProvider)
          .createNotebook(
            const NewNotebook(title: 'N', cover: NotebookCover.color(0)),
          );
    }
    await tester.pumpAndSettle();

    await tester.tap(find.text('New notebook'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Free accounts have up to 3'), findsOneWidget);

    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subscribe'));
    await tester.pumpAndSettle();
    expect(store.bought, {ProProducts.monthly});
    expect(find.text('Create'), findsOneWidget, reason: 'the editor opens');
  });
}
