import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/entitlements/entitlements.dart';
import '../../core/skins/skin_manifest.dart';
import '../../core/skins/skin_providers.dart';
import '../store/paywall.dart';
import 'sample_pages.dart';

const notebookStylePath = '/settings/style';

/// Picks the default style for notebooks that don't choose their own.
/// Each notebook can still pick its own style in its editor.
class NotebookStyleScreen extends ConsumerWidget {
  const NotebookStyleScreen({super.key});

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    SkinManifest skin,
  ) async {
    if (!ref.read(entitlementsProvider).canUseSkin(skin)) {
      final pro = await showPaywall(
        context,
        ref,
        reason: '${skin.name} is included in Jotswift Pro.',
      );
      if (!pro) return;
    }
    await ref.read(activeSkinIdProvider.notifier).select(skin);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('New notebooks now use ${skin.name}')),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skins = ref.watch(bundledSkinsProvider);
    final activeId = ref.watch(activeSkinProvider).id;
    final entitlements = ref.watch(entitlementsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Notebook style')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.62,
        ),
        itemCount: skins.length,
        itemBuilder: (context, i) => SkinCard(
          skin: skins[i],
          isActive: skins[i].id == activeId,
          isLocked: !entitlements.canUseSkin(skins[i]),
          onTap: () => _pick(context, ref, skins[i]),
        ),
      ),
    );
  }
}

/// A small preview of [skin], drawn in that skin's own theme.
class SkinCard extends ConsumerWidget {
  const SkinCard({
    required this.skin,
    required this.isActive,
    required this.isLocked,
    required this.onTap,
    super.key,
  });

  final SkinManifest skin;
  final bool isActive;
  final bool isLocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(skinEngineProvider).buildTheme(skin);
    final status = isActive
        ? 'In use'
        : skin.pro
        ? 'Pro'
        : 'Free';

    return Semantics(
      button: true,
      label: '${skin.name} style, $status',
      child: Theme(
        data: theme,
        child: Material(
          color: skin.colors.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isActive ? theme.colorScheme.primary : skin.colors.outline,
              width: isActive ? 3 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: IgnorePointer(
                      child: FittedBox(
                        child: SizedBox(
                          width: 300,
                          height: 400,
                          child: SampleNotePage(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          skin.name,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: skin.colors.onSurface,
                          ),
                        ),
                      ),
                      if (isLocked)
                        Icon(
                          Icons.lock_outline,
                          size: 16,
                          color: skin.colors.onSurface,
                        )
                      else if (isActive)
                        Icon(
                          Icons.check_circle,
                          size: 18,
                          color: skin.colors.primary,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      for (final c in skin.inkColors.take(4))
                        Container(
                          width: 12,
                          height: 12,
                          margin: const EdgeInsets.only(right: 3),
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(color: skin.colors.outline),
                          ),
                        ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          status,
                          textAlign: TextAlign.end,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: skin.colors.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
