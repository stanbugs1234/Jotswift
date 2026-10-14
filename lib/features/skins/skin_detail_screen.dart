import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/entitlements/entitlements.dart';
import '../../core/skins/skin_manifest.dart';
import '../../core/skins/skin_providers.dart';
import 'sample_pages.dart';

/// Full preview of one skin on every page type ("try before you buy").
/// The whole screen is drawn in the previewed skin, not the active one.
class SkinDetailScreen extends ConsumerStatefulWidget {
  const SkinDetailScreen({required this.skinId, super.key});

  final String skinId;

  @override
  ConsumerState<SkinDetailScreen> createState() => _SkinDetailScreenState();
}

class _SkinDetailScreenState extends ConsumerState<SkinDetailScreen> {
  SamplePageKind _page = SamplePageKind.note;

  @override
  Widget build(BuildContext context) {
    final skin = ref
        .watch(bundledSkinsProvider)
        .where((s) => s.id == widget.skinId)
        .firstOrNull;
    if (skin == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This skin is no longer available.')),
      );
    }

    final theme = ref.watch(skinEngineProvider).buildTheme(skin);
    final isActive = ref.watch(activeSkinProvider).id == skin.id;
    final canUse = ref.watch(entitlementsProvider).canUseSkin(skin);

    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(title: Text(skin.name)),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(skin.description, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 16),
                    SegmentedButton<SamplePageKind>(
                      showSelectedIcon: false,
                      segments: [
                        for (final k in SamplePageKind.values)
                          ButtonSegment(
                            value: k,
                            icon: Icon(k.icon),
                            tooltip: k.label,
                          ),
                      ],
                      selected: {_page},
                      onSelectionChanged: (s) =>
                          setState(() => _page = s.first),
                    ),
                    const SizedBox(height: 16),
                    AspectRatio(
                      aspectRatio: 3 / 4,
                      child: SamplePage(kind: _page, date: DateTime.now()),
                    ),
                    const SizedBox(height: 16),
                    _ApplyButton(
                      skin: skin,
                      isActive: isActive,
                      canUse: canUse,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ApplyButton extends ConsumerWidget {
  const _ApplyButton({
    required this.skin,
    required this.isActive,
    required this.canUse,
  });

  final SkinManifest skin;
  final bool isActive;
  final bool canUse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isActive) {
      return const FilledButton(onPressed: null, child: Text('In use'));
    }
    if (canUse) {
      return FilledButton(
        onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          await ref.read(activeSkinIdProvider.notifier).select(skin);
          messenger.showSnackBar(
            SnackBar(content: Text('${skin.name} is now your skin')),
          );
        },
        child: const Text('Use this skin'),
      );
    }
    final what = skin.tier == SkinTier.pro ? 'Notely Pro' : 'this skin';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: null,
          icon: const Icon(Icons.lock_outline),
          label: Text('Unlock $what'),
        ),
        const SizedBox(height: 8),
        Text(
          'The store opens in a later update. You can preview this skin now.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
