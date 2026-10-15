import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/notebooks/notes_providers.dart';
import '../purchases/purchases_providers.dart';
import 'entitlements.dart';

/// Notebooks a free account can have. Pro has no limit.
const freeNotebookLimit = 3;

/// Whether the user may make another notebook. There's no limit until the
/// store is open on this device, since Pro couldn't be bought yet.
final canCreateNotebookProvider = Provider<bool>((ref) {
  if (!ref.watch(purchasesClientProvider).isAvailable) return true;
  if (ref.watch(entitlementsProvider).pro) return true;
  final count = ref.watch(notebooksProvider).value?.length ?? 0;
  return count < freeNotebookLimit;
});
