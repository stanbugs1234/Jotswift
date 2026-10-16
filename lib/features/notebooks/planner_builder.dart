import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/catalog_item.dart';
import '../canvas/templates.dart';
import 'domain/notebook_models.dart';

/// Shapes a planner before it's made: its layout and first day of the
/// week, and which groups of pages to include. Shows nothing for planners
/// without these choices.
///
/// Leaving pages out keeps a planner from feeling overwhelming, and isn't
/// final: a link to a page that was left out offers to add it.
class PlannerBuilder extends ConsumerWidget {
  const PlannerBuilder({
    required this.template,
    required this.options,
    required this.skip,
    required this.onOptions,
    required this.onSkip,
    super.key,
  });

  final CatalogItem template;

  /// Chosen options by id; the first choice for any not chosen.
  final Map<String, String> options;

  /// Groups to leave out; null for the planner's defaults.
  final Set<String>? skip;

  /// New options, and the PDF they pick.
  final void Function(Map<String, String> options, String file) onOptions;
  final ValueChanged<Set<String>> onSkip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = ref.watch(templateSpecProvider(template)).value;
    if (spec == null || spec.options.isEmpty && spec.groups.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final skipped = skip ?? spec.defaultSkipped;
    final counts = <String, int>{};
    for (final p in spec.pages) {
      if (p.group case final g?) counts[g] = (counts[g] ?? 0) + 1;
    }
    final total = spec.pageCount(skip: skipped);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final option in spec.options)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text(option.title, style: theme.textTheme.labelLarge),
                ),
                Flexible(
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      for (final c in option.choices)
                        ButtonSegment(
                          value: c.id,
                          label: Text(c.name),
                          icon: _icon(option.id, c.id),
                        ),
                    ],
                    selected: {
                      options[option.id] ??
                          option.choices.firstOrNull?.id ??
                          '',
                    },
                    onSelectionChanged: (picked) {
                      final next = {...options, option.id: picked.first};
                      onOptions(
                        next,
                        spec.variantFor(next)?.file ?? PageTemplate.defaultFile,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        if (spec.groups.any((g) => g.optional)) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 4),
            child: Text('Include', style: theme.textTheme.labelLarge),
          ),
          for (final g in spec.groups)
            if (g.optional && (counts[g.id] ?? 0) > 0)
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(g.title),
                subtitle: Text(_pages(counts[g.id]!)),
                value: !skipped.contains(g.id),
                onChanged: (on) => onSkip(
                  on ? ({...skipped}..remove(g.id)) : {...skipped, g.id},
                ),
              ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '${_pages(total)}, with links between them. Anything you leave '
            'out can be added later: tap a link to it, or use New page.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  static String _pages(int n) => n == 1 ? '1 page' : '$n pages';

  static Widget? _icon(String option, String choice) =>
      switch ((option, choice)) {
        ('layout', 'landscape') => const Icon(Icons.crop_landscape),
        ('layout', 'portrait') => const Icon(Icons.crop_portrait),
        _ => null,
      };
}
