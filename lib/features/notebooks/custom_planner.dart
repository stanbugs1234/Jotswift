import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/catalog_item.dart';
import '../../core/catalog/catalog_providers.dart';
import '../../core/catalog/planner_series.dart';
import '../../core/entitlements/entitlements.dart';
import '../../core/pdf/pdf_renderer.dart';
import '../../core/planner/book.dart' show day;
import '../../core/planner/pdf_ops.dart';
import '../../core/planner/presets.dart';
import '../../core/planner/recipe.dart';
import '../canvas/templates.dart';
import '../imports/document_import.dart';
import '../store/paywall.dart';
import 'domain/notebook_models.dart';

/// Whether making a planner of your own needs Jotswift Pro. Building one
/// to look at doesn't.
const customPlannersNeedPro = true;

/// The month a new dated planner starts: this one.
DateTime thisMonth([DateTime? now]) {
  final n = now ?? DateTime.now();
  return day(n.year, n.month, 1);
}

/// Where Build your own starts.
PlannerRecipe newPlannerRecipe() => standardRecipe(start: thisMonth());

/// [item] (a catalog planner) as a recipe to change: its own, for the
/// Life-style planners, else the standard layout in its collection's look.
/// Dated from [from] (this month if null), or undated like [item].
PlannerRecipe recipeForPlanner(CatalogItem item, {DateTime? from}) {
  final undated = item.id.endsWith('_undated');
  final start = undated
      ? null
      : (from == null ? thisMonth() : day(from.year, from.month, 1));
  final key = seriesKey(item).replaceFirst(RegExp(r'_planner$'), '');
  final preset = lifePlannerRecipes[key];
  if (preset != null) return preset().copyWith(start: () => start);
  final look = collectionLooks[item.collectionId];
  return standardRecipe(
    title: plannerName(item),
    style: look?.$2,
    collectionId: look == null ? null : item.collectionId,
    start: start,
  );
}

/// Pages of a planner the app made carry its recipe in their spec: the
/// recipe of [item], if it's one.
Future<PlannerRecipe?> recipeOf(Ref ref, CatalogItem item) async {
  final files = await ref.read(packCacheProvider).files(item);
  final json = files['template.json'];
  if (json == null) return null;
  final spec = jsonDecode(utf8.decode(json));
  return spec is Map && spec['recipe'] is Map
      ? PlannerRecipe.fromMap((spec['recipe'] as Map).cast())
      : null;
}

/// Makes [recipe]'s planner and keeps it like an imported document: its
/// listing, to make pages from.
Future<CatalogItem> makeAndKeepPlanner(Ref ref, PlannerRecipe recipe) async {
  final made = await makePlannerInBackground(recipe);
  return ref
      .read(documentImporterProvider)
      .keepPlanner(
        recipe.title,
        made.pdf,
        Uint8List.fromList(utf8.encode(jsonEncode(made.spec))),
      );
}

/// Makes [notebook] from [recipe], its pages in the planner's sections.
Future<Notebook> createCustomPlanner(
  Ref ref,
  NewNotebook notebook,
  PlannerRecipe recipe, {
  void Function(int done, int total)? onProgress,
}) async {
  onProgress?.call(0, 0);
  final item = await makeAndKeepPlanner(ref, recipe);
  return createNotebookFromTemplate(
    ref,
    notebook,
    item,
    onProgress: onProgress,
  );
}

/// [createCustomPlanner], for widgets.
final createCustomPlannerProvider =
    Provider<
      Future<Notebook> Function(
        NewNotebook,
        PlannerRecipe, {
        void Function(int done, int total)? onProgress,
      })
    >(
      (ref) =>
          (notebook, recipe, {onProgress}) => createCustomPlanner(
            ref,
            notebook,
            recipe,
            onProgress: onProgress,
          ),
    );

/// Whether the user may make a planner of their own, offering Pro if not.
Future<bool> mayMakeCustomPlanner(BuildContext context, WidgetRef ref) async {
  if (!customPlannersNeedPro || ref.read(entitlementsProvider).pro) return true;
  return showPaywall(
    context,
    ref,
    reason: 'Planners you build yourself are included in Jotswift Pro.',
  );
}

/// The page size of [recipe]'s planner, in PDF points.
ui.Size recipePageSize(PlannerRecipe recipe) =>
    recipe.landscape ? const ui.Size(792, 612) : const ui.Size(612, 792);

/// One page of a recipe, drawn: the first page of [group] (see
/// [previewPage]), [width] pixels wide. [recipe] is the recipe's JSON, so
/// equal recipes share pictures.
final recipePageProvider = FutureProvider.autoDispose
    .family<ui.Image, ({String recipe, String group, int width})>((
      ref,
      key,
    ) async {
      final recipe = PlannerRecipe.fromMap(
        (jsonDecode(key.recipe) as Map).cast(),
      );
      final pdf = await ref
          .read(pdfRendererProvider)
          .open(previewPage(recipe, key.group), name: 'preview-${key.group}');
      try {
        return await pdf.render(1, width: key.width);
      } finally {
        await pdf.dispose();
      }
    });

/// A recipe's key for [recipePageProvider].
String recipeKey(PlannerRecipe recipe) => jsonEncode(recipe.toMap());

/// The colours of a look, for its swatch.
(Color, Color, Color) lookColors(PlannerStyle style) {
  Color c(Rgb rgb) => Color.from(
    alpha: 1,
    red: rgb.$1.toDouble(),
    green: rgb.$2.toDouble(),
    blue: rgb.$3.toDouble(),
  );
  return (c(style.accent), c(style.tab), c(style.paper ?? (1, 1, 1)));
}
