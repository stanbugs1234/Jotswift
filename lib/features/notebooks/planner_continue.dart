import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/catalog_item.dart';
import '../../core/catalog/catalog_providers.dart';
import '../../core/catalog/planner_series.dart';
import '../../core/entitlements/entitlements.dart';
import '../canvas/templates.dart';
import '../store/store_item_screen.dart';
import 'domain/page_template.dart';
import 'notes_providers.dart';
import 'planner_builder.dart';

/// How a dated planner goes on once its months run out: the next edition
/// of the same planner, from the month after the notebook's last one, in
/// the same layout ([file]).
typedef PlannerNext = ({
  CatalogItem edition,
  DateTime from,
  String file,

  /// A page of the notebook's planner, for the groups it was made with.
  PageTemplate made,
});

/// The next edition for the planner in [notebookId], or null if it isn't
/// a dated planner or there's none newer in the catalog.
final plannerNextProvider = FutureProvider.autoDispose
    .family<PlannerNext?, String>((ref, notebookId) async {
      final pages = await ref
          .watch(notebookRepositoryProvider)
          .watchNotebookPages(notebookId)
          .first;
      // The latest month page from the catalog.
      PageTemplate? made;
      DateTime? last;
      for (final p in pages) {
        final (template, from, to) = (p.template, p.period?.from, p.period?.to);
        if (template == null ||
            template.isImported ||
            from == null ||
            to == null ||
            from.day != 1 ||
            to != DateTime(from.year, from.month + 1, 0)) {
          continue;
        }
        if (last == null || from.isAfter(last)) (made, last) = (template, from);
      }
      if (made == null || last == null) return null;
      final next = DateTime(last.year, last.month + 1);
      final catalog = ref.watch(storeCatalogProvider);
      final current = catalog.where((i) => i.id == made!.itemId).firstOrNull;
      if (current == null) return null;
      // The edition that starts on or nearest before the next month (the
      // 2027 one for a 2026 planner), else the first to start after it.
      final later = [
        for (final e in editionsOf(current, catalog))
          if (editionDates(e) case final r? when !r.to.isBefore(next)) (e, r),
      ];
      final covering = [
        for (final (e, r) in later)
          if (!r.from.isAfter(next)) (e, r),
      ]..sort((a, b) => b.$2.from.compareTo(a.$2.from));
      final after = [
        for (final (e, r) in later)
          if (r.from.isAfter(next)) (e, r),
      ]..sort((a, b) => a.$2.from.compareTo(b.$2.from));
      final edition = (covering.firstOrNull ?? after.firstOrNull)?.$1;
      if (edition == null || edition.id == current.id) return null;
      return (edition: edition, from: next, file: made.file, made: made);
    });

/// Adds the months after the planner in [notebookId] runs out, from its
/// next edition, after saying what it adds. A locked edition opens in the
/// store first. Returns the first page added.
Future<String?> continuePlanner(
  BuildContext context,
  WidgetRef ref,
  String notebookId,
) async {
  final next = await ref.read(plannerNextProvider(notebookId).future);
  if (next == null || !context.mounted) return null;
  final (:edition, :from, :file, :made) = next;
  final to = editionDates(edition)!.to;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Continue to ${monthYear(to)}?'),
      content: Text(
        'Adds ${monthYear(from)} to ${monthYear(to)} from '
        '${edition.name}, with links between the pages, after the pages '
        'you have.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Add months'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return null;
  if (!ref.read(entitlementsProvider).canUseCatalogItem(edition)) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => StoreItemScreen(itemId: edition.id)),
    );
    if (!context.mounted ||
        !ref.read(entitlementsProvider).canUseCatalogItem(edition)) {
      return null;
    }
  }

  final add = ref.read(addPlannerPagesProvider);
  return withPlannerProgress<String?>(context, (onProgress) async {
    // Same layout if the new edition has it, and the same groups of pages
    // as the planner was made with.
    final spec = await ref.read(templateSpecProvider(edition).future);
    final sameFile =
        file == PageTemplate.defaultFile ||
        spec.variants.any((v) => v.file == file);
    final old = await ref.read(templateFileSpecProvider(made.fileKey).future);
    final pages = await ref
        .read(notebookRepositoryProvider)
        .watchNotebookPages(notebookId)
        .first;
    final had = {
      for (final p in pages)
        if (p.template?.itemId == made.itemId) p.template!.pdfPage,
    };
    final kept = {
      for (final p in old.pages)
        if (had.contains(p.pdfPage)) p.group,
    };
    return add(
      notebookId,
      edition,
      file: sameFile ? file : PageTemplate.defaultFile,
      skip: {
        for (final g in spec.groups)
          if (g.optional && old.groups.any((o) => o.id == g.id))
            if (!kept.contains(g.id)) g.id,
      },
      from: from,
      datedOnly: true,
      onProgress: onProgress,
    );
  });
}
