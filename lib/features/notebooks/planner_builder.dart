import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/catalog_item.dart';
import '../../core/catalog/planner_series.dart';
import '../../core/catalog/template_spec.dart';
import '../canvas/templates.dart';
import 'domain/notebook_models.dart';

/// Shapes a planner before it's made: the month it starts, its layout and
/// first day of the week, and which groups of pages to include. Shows
/// nothing for planners without these choices.
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
    this.from,
    this.onFrom,
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

  /// The month a dated planner starts; null for [TemplateSpec.startFor]
  /// today. Without [onFrom] it can't be changed.
  final DateTime? from;
  final ValueChanged<DateTime?>? onFrom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = ref.watch(templateSpecProvider(template)).value;
    final months = onFrom == null
        ? const <DateTime>[]
        : spec?.months ?? const <DateTime>[];
    if (spec == null ||
        spec.options.isEmpty && spec.groups.isEmpty && months.length < 2) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final skipped = skip ?? spec.defaultSkipped;
    final start = from ?? spec.startFor(DateTime.now()) ?? months.firstOrNull;
    final counts = <String, int>{};
    for (final p in spec.pages) {
      if (p.group case final g?) counts[g] = (counts[g] ?? 0) + 1;
    }
    final total = spec.pageCount(skip: skipped, from: start);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (months.length > 1 && start != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text('Starts', style: theme.textTheme.labelLarge),
                ),
                DropdownButton<DateTime>(
                  value: start,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final m in months)
                      DropdownMenuItem(value: m, child: Text(monthYear(m))),
                  ],
                  onChanged: (m) => onFrom!(m),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _months(months.where((m) => !m.isBefore(start)).length),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
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

  static String _months(int n) => n == 1 ? '1 month' : '$n months';

  static Widget? _icon(String option, String choice) =>
      switch ((option, choice)) {
        ('layout', 'landscape') => const Icon(Icons.crop_landscape),
        ('layout', 'portrait') => const Icon(Icons.crop_portrait),
        _ => null,
      };
}

/// Runs [work] (which makes a planner's pages) behind a "Setting up your
/// planner..." dialog with its progress. Says so and returns null if it
/// fails.
Future<T?> withPlannerProgress<T>(
  BuildContext context,
  Future<T> Function(void Function(int done, int total) onProgress) work,
) async {
  final progress = ValueNotifier<(int, int)>((0, 0));
  final navigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.maybeOf(context);
  var showing = true;
  unawaited(
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: ValueListenableBuilder(
            valueListenable: progress,
            builder: (context, value, _) {
              final (done, total) = value;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Setting up your planner…'),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: total == 0 ? null : done / total,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    total == 0 ? '' : '$done of $total pages',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ).whenComplete(() => showing = false),
  );
  try {
    return await work((done, total) => progress.value = (done, total));
  } on Object catch (e) {
    debugPrint('Could not set up a planner: $e');
    messenger?.showSnackBar(
      const SnackBar(
        content: Text(
          'Could not set up the planner. Check your connection and try '
          'again.',
        ),
      ),
    );
    return null;
  } finally {
    if (showing) navigator.pop();
    progress.dispose();
  }
}

/// What to add of a planner: its PDF, the page groups to leave out, and
/// the month it starts (null for all of it).
typedef PlannerChoice = ({String file, Set<String> skip, DateTime? from});

/// Asks how to add the whole planner [item] to a notebook: its layout,
/// week start and which pages, as when making a notebook from it. Returns
/// null if cancelled.
Future<PlannerChoice?> showAddPlannerSheet(
  BuildContext context,
  CatalogItem item,
) => showModalBottomSheet<PlannerChoice>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => _AddPlannerSheet(item: item),
);

class _AddPlannerSheet extends ConsumerStatefulWidget {
  const _AddPlannerSheet({required this.item});

  final CatalogItem item;

  @override
  ConsumerState<_AddPlannerSheet> createState() => _AddPlannerSheetState();
}

class _AddPlannerSheetState extends ConsumerState<_AddPlannerSheet> {
  Map<String, String> _options = const {};
  String _file = PageTemplate.defaultFile;
  Set<String>? _skip;
  DateTime? _from;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spec = ref.watch(templateSpecProvider(widget.item)).value;
    final skip = _skip ?? spec?.defaultSkipped ?? const <String>{};
    final from = _from ?? spec?.startFor(DateTime.now());
    final count = spec?.pageCount(skip: skip, from: from);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Add ${widget.item.name}', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Every page goes into this notebook as new sections, with '
              'the links between them.',
              style: theme.textTheme.bodyMedium,
            ),
            if (spec == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              PlannerBuilder(
                template: widget.item,
                options: _options,
                skip: _skip,
                onOptions: (options, file) => setState(() {
                  _options = options;
                  _file = file;
                }),
                onSkip: (skip) => setState(() => _skip = skip),
                from: _from,
                onFrom: (from) => setState(() => _from = from),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.library_add_outlined),
                  label: Text(
                    count == null
                        ? 'Add planner'
                        : 'Add ${PlannerBuilder._pages(count)}',
                  ),
                  onPressed: spec == null
                      ? null
                      : () => Navigator.pop(context, (
                          file: _file,
                          skip: skip,
                          from: from,
                        )),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
