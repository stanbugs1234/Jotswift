import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/skins/skin_providers.dart';
import '../../core/skins/widgets/page_style.dart';
import '../skins/sample_pages.dart';

/// A tab that isn't built yet. Shows a sample page in the default notebook
/// style.
class PlaceholderScreen extends ConsumerWidget {
  const PlaceholderScreen({
    required this.title,
    required this.kind,
    required this.comingIn,
    super.key,
  });

  final String title;
  final SamplePageKind kind;

  /// e.g. "Phase 2", from the roadmap in PLAN.md.
  final String comingIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Notebook styles',
            icon: const Icon(Icons.palette_outlined),
            onPressed: () => context.push('/settings/skins'),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Sample page. Editing arrives in $comingIn.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                AspectRatio(
                  aspectRatio: 3 / 4,
                  child: PageStyle(
                    style: ref.watch(defaultStyleProvider),
                    child: SamplePage(kind: kind, date: DateTime.now()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
