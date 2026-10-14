import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../skins/sample_pages.dart';

/// A tab that isn't built yet. Shows a sample page in the active skin so the
/// skin can be tried out everywhere in the app.
class PlaceholderScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Skins',
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
                  child: SamplePage(kind: kind, date: DateTime.now()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
