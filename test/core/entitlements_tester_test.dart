import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/catalog/catalog_providers.dart';
import 'package:notely/core/entitlements/entitlements.dart';

void main() {
  test('testers get Pro so they can try everything before release', () {
    ProviderContainer make({required bool tester}) {
      final c = ProviderContainer(
        overrides: [
          isTesterProvider.overrideWithValue(AsyncData(tester)),
          accountEntitlementsProvider.overrideWithValue(
            const AsyncData(Entitlements(products: {'pack_x'})),
          ),
          deviceEntitlementsProvider.overrideWithValue(
            const AsyncData(Entitlements.none),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    final tester = make(tester: true).read(entitlementsProvider);
    expect(tester.pro, isTrue);
    expect(tester.owns('pack_x'), isTrue, reason: 'purchases still count');
    expect(make(tester: false).read(entitlementsProvider).pro, isFalse);
  });
}
