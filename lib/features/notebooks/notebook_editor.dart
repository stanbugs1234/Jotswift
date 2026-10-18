import '../../shared/ui/tokens.dart';
import '../../shared/ui/skeleton.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/catalog_item.dart';
import '../../core/catalog/catalog_providers.dart';
import '../../core/catalog/planner_series.dart';
import '../../core/entitlements/entitlements.dart';
import '../../core/paper/paper_style.dart';
import '../../core/skins/skin_manifest.dart';
import '../../core/skins/skin_providers.dart';
import '../../core/skins/widgets/paper.dart';
import '../canvas/templates.dart';
import '../shelf/cover_view.dart';
import 'cover_picker.dart';
import 'domain/notebook_models.dart';
import 'paper_picker.dart';
import 'planner_builder.dart';
import 'notebook_start.dart';
import 'template_gallery.dart';
import '../store/store_item.dart' show ItemPreview;
import '../store/store_item_screen.dart';
import 'notes_providers.dart' show myTemplatesProvider;
import '../../core/planner/recipe.dart';
import 'custom_planner.dart';
import 'custom_planner_screen.dart';

/// Makes a new notebook, or (with [editing]) changes one: title, cover,
/// paper and theme. Returns the choices, or null if cancelled.
///
/// Size and orientation can only be chosen for a new notebook: ink is saved
/// in page units, so changing them later would move it.
class NotebookEditor extends ConsumerStatefulWidget {
  const NotebookEditor({
    required this.initial,
    this.editing,
    this.template,
    super.key,
  });

  final NewNotebook initial;

  /// The planner a new notebook starts with, if one was already chosen.
  final CatalogItem? template;

  /// The notebook being changed, or null for a new one.
  final Notebook? editing;

  static Future<NotebookEditorResult?> show(
    BuildContext context, {
    required NewNotebook initial,
    Notebook? editing,
    CatalogItem? template,
  }) => Navigator.of(context, rootNavigator: true).push<NotebookEditorResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) => NotebookEditor(
        initial: initial,
        editing: editing,
        template: template,
      ),
    ),
  );

  @override
  ConsumerState<NotebookEditor> createState() => _NotebookEditorState();
}

class _NotebookEditorState extends ConsumerState<NotebookEditor> {
  late final _title = TextEditingController(text: widget.initial.title);
  late NotebookCover _cover = widget.initial.cover;
  late PaperStyle? _paper = widget.initial.paper;
  late PaperSize _size = widget.initial.paperSize;
  late PaperOrientation _orientation = widget.initial.orientation;
  late String? _styleId = widget.initial.collectionId;

  /// The planner the new notebook starts from, or null for blank pages.
  late CatalogItem? _template = widget.template;

  /// The planner's colourway, or its layout and week start: which PDF of
  /// its pack.
  String _variant = PageTemplate.defaultFile;

  /// The planner builder's choices (layout, week start), by option id.
  Map<String, String> _options = const {};

  /// Page groups to leave out; null for the planner's defaults.
  Set<String>? _skip;

  /// The month a dated planner starts; null for this month (or all of it).
  DateTime? _from;

  /// One of the user's own templates to copy, instead of a planner.
  Notebook? _mine;

  /// A planner the user built, instead of a catalog one.
  PlannerRecipe? _recipe;
  bool _saving = false;

  /// Whether the user picked the cover or theme, which then stay; until
  /// then they follow the planner's collection.
  bool _coverChosen = false;
  bool _styleChosen = false;

  @override
  void initState() {
    super.initState();
    if (widget.editing == null) _matchPlanner(widget.template);
  }

  /// On the first step, choosing what the notebook starts from. Skipped
  /// when a planner was already chosen, and when editing.
  late bool _choosing = widget.editing == null && widget.template == null;

  bool _usable(CatalogItem item) =>
      ref.read(entitlementsProvider).canUseCatalogItem(item);

  void _start({PlannerSeries? series, Notebook? mine}) => setState(() {
    _choosing = false;
    _recipe = null;
    _setTemplate(series?.defaultEdition(DateTime.now(), usable: _usable));
    _mine = mine;
    if (mine != null) {
      _cover = mine.cover;
      _styleId = mine.collectionId ?? _styleId;
    }
  });

  void _setTemplate(CatalogItem? template) {
    _template = template;
    _variant = PageTemplate.defaultFile;
    _options = const {};
    _skip = null;
    _from = null;
    _matchPlanner(template);
  }

  /// Builds a planner (from [from], else from scratch) and starts with it.
  Future<void> _build({PlannerRecipe? from}) async {
    final recipe = await CustomPlannerScreen.show(
      context,
      from ?? _recipe ?? newPlannerRecipe(),
    );
    if (recipe == null || !mounted) return;
    setState(() {
      _choosing = false;
      _mine = null;
      _setTemplate(null);
      _recipe = recipe;
      _matchPlanner(null, collection: recipe.collectionId);
    });
  }

  /// Gives the notebook [template]'s cover and theme, from its collection
  /// (or [collection]), unless the user chose their own.
  void _matchPlanner(CatalogItem? template, {String? collection}) {
    collection ??= template?.collectionId;
    if (!_coverChosen) {
      final art = collection == null
          ? null
          : ref
                .read(offeredCatalogProvider(CatalogKind.cover))
                .where((c) => c.collectionId == collection)
                .firstOrNull;
      _cover = art == null
          ? widget.initial.cover
          : NotebookCover.art(
              art.id,
              color: art.color ?? widget.initial.cover.color,
            );
    }
    if (!_styleChosen) {
      _styleId =
          collection != null &&
              ref.read(usableSkinsProvider).any((s) => s.id == collection)
          ? collection
          : widget.initial.collectionId;
    }
  }

  /// Shows a locked planner in the store, and starts with it if it was
  /// unlocked there.
  Future<void> _unlock(CatalogItem item) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => StoreItemScreen(itemId: item.id)),
    );
    if (mounted && _usable(item)) {
      setState(() {
        _choosing = false;
        _mine = null;
        _setTemplate(item);
      });
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  /// The chosen style, or the default style if none is chosen (or the
  /// chosen one is locked).
  SkinManifest get _style =>
      ref
          .read(usableSkinsProvider)
          .where((s) => s.id == _styleId)
          .firstOrNull ??
      ref.read(activeSkinProvider);

  Future<void> _save() async {
    final title = _title.text.trim();
    final style = _style;
    final template = _template;
    var (size, orientation) = (_size, _orientation);
    final mine = _mine;
    final recipe = _recipe;
    if (recipe != null) {
      if (!await mayMakeCustomPlanner(context, ref) || !mounted) return;
      (size, orientation) = closestPaperSize(recipePageSize(recipe));
    }
    if (mine != null) (size, orientation) = (mine.paperSize, mine.orientation);
    if (template != null) {
      // A planner's pages are sized to fit its PDF.
      setState(() => _saving = true);
      try {
        final pdf = await ref.read(
          templatePdfProvider(templatePage(template, 1, file: _variant).fileKey)
              .future,
        );
        (size, orientation) = closestPaperSize(pdf.pageSize(1));
      } on Object catch (e) {
        debugPrint('Could not open ${template.id}: $e');
        if (!mounted) return;
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not download the planner. Check your connection and '
              'try again.',
            ),
          ),
        );
        return;
      }
    }
    if (!mounted) return;
    // Save the paper and style the user saw, so later changes to the
    // default style don't change this notebook.
    Navigator.pop(context, (
      notebook: NewNotebook(
        title: title.isEmpty
            ? ((template == null ? null : plannerName(template)) ??
                  recipe?.title ??
                  mine?.title ??
                  'Untitled notebook')
            : title,
        cover: _cover,
        paper: _paper ?? style.paper.style,
        paperSize: size,
        orientation: orientation,
        collectionId: style.id,
        place: widget.initial.place,
      ),
      template: template,
      variant: _variant,
      skip: template == null
          ? const <String>{}
          : _skip ??
                ref
                    .read(templateSpecProvider(template))
                    .value
                    ?.defaultSkipped ??
                const <String>{},
      from: template == null
          ? null
          : _from ??
                ref
                    .read(templateSpecProvider(template))
                    .value
                    ?.startFor(DateTime.now()),
      mine: mine,
      recipe: recipe,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styles = ref.watch(usableSkinsProvider);
    ref.watch(activeSkinProvider);
    final style = _style;
    final paper = _paper ?? style.paper.style;
    final isNew = widget.editing == null;
    ref.watch(entitlementsProvider);
    final series = isNew
        ? plannerSeries(ref.watch(storeCatalogProvider))
        : const <PlannerSeries>[];
    final loadingCatalog = isNew && !ref.watch(catalogProvider).hasValue;
    final template = _template;
    final editions = template == null
        ? const <CatalogItem>[]
        : series
                  .where((s) => s.key == seriesKey(template))
                  .firstOrNull
                  ?.editions ??
              [template];
    final spec = template == null
        ? null
        : ref.watch(templateSpecProvider(template)).value;
    final mine = _mine;
    final myTemplates = isNew
        ? ref.watch(myTemplatesProvider).value ?? const <Notebook>[]
        : const <Notebook>[];

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(text, style: theme.textTheme.titleSmall),
    );

    void pickStyle(SkinManifest next) => setState(() {
      _styleChosen = true;
      // Keep a paper the user chose; follow the style otherwise.
      if (_paper == null || _paper == style.paper.style) {
        _paper = next.paper.style;
      }
      _styleId = next.id;
    });

    final page = _size.dimensions(_orientation);
    final canChoose =
        isNew &&
        (series.isNotEmpty || myTemplates.isNotEmpty || loadingCatalog);

    if (_choosing && canChoose) {
      return Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: const Text('New notebook'),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: NotebookStartChooser(
                series: series,
                usable: _usable,
                loading: loadingCatalog,
                myTemplates: myTemplates,
                blankPaper: paper,
                onBlank: _start,
                onBuild: _build,
                onTemplate: (s) => _start(series: s),
                onLocked: (s) =>
                    _unlock(s.defaultEdition(DateTime.now(), usable: _usable)),
                onMine: (t) => _start(mine: t),
              ),
            ),
          ),
        ),
      );
    }

    // Back (and the back gesture) returns to the first step.
    return PopScope(
      canPop: !canChoose,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _choosing = true);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: canChoose
              ? BackButton(onPressed: () => setState(() => _choosing = true))
              : const CloseButton(),
          title: Text(isNew ? 'New notebook' : 'Edit notebook'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: Insets.lg),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(isNew ? 'Create' : 'Save'),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Preview: the cover and a page.
                    SizedBox(
                      height: 170,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          CoverView(cover: _cover),
                          const SizedBox(width: 20),
                          if (template != null)
                            _TemplatePreview(template: template, file: _variant)
                          else if (_recipe case final r?)
                            RecipePage(
                              recipeKey: recipeKey(r),
                              group: 'home',
                              landscape: r.landscape,
                              width: 400,
                            )
                          else
                            AspectRatio(
                              aspectRatio: page.width / page.height,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                                child: CustomPaint(
                                  painter: PaperPainter(
                                    paper,
                                    scale: 170 / page.height,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _title,
                      // No keyboard until asked for: on a tablet it would
                      // hide half of the choices below.
                      onTapOutside: (_) => FocusScope.of(context).unfocus(),
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: 'Title',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        // Left empty, the notebook takes this name.
                        hintText:
                            (template == null ? null : plannerName(template)) ??
                            _recipe?.title ??
                            mine?.title ??
                            'e.g. School, Work, Journal',
                      ),
                      onSubmitted: (_) => _save(),
                    ),
                    if (canChoose) ...[
                      heading('Start with'),
                      _StartSummary(
                        template: template,
                        mine: mine,
                        recipe: _recipe,
                        paper: paper,
                        onChange: () => setState(() => _choosing = true),
                      ),
                      if (_recipe != null)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            onPressed: _build,
                            icon: const Icon(Icons.tune),
                            label: const Text('Change what\'s inside'),
                          ),
                        ),
                      if (editions.length > 1)
                        _EditionPicker(
                          editions: editions,
                          selected: template!,
                          usable: _usable,
                          onChanged: (e) => _usable(e)
                              ? setState(() => _setTemplate(e))
                              : _unlock(e),
                        ),
                      if (template != null)
                        _ColourwayPicker(
                          template: template,
                          selected: _variant,
                          onChanged: (file) => setState(() => _variant = file),
                        ),
                      if (template != null)
                        PlannerBuilder(
                          template: template,
                          options: _options,
                          skip: _skip,
                          onOptions: (options, file) => setState(() {
                            _options = options;
                            _variant = file;
                          }),
                          onSkip: (skip) => setState(() => _skip = skip),
                          from: _from,
                          onFrom: (from) => setState(() => _from = from),
                        ),
                      if (template != null)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            onPressed: () => _build(
                              from: recipeForPlanner(
                                template,
                                from: _from ?? spec?.startFor(DateTime.now()),
                              ),
                            ),
                            icon: const Icon(Icons.tune),
                            label: const Text('Customize: choose every page'),
                          ),
                        ),
                      if (template != null &&
                          spec != null &&
                          spec.options.isEmpty &&
                          spec.groups.isEmpty &&
                          spec.months.length < 2)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            template.linked
                                ? '${template.pageCount ?? 'All'} pages, with '
                                      'links between them. Pages are sized to '
                                      'fit the planner.'
                                : '${template.pageCount ?? 'All'} pages. Pages '
                                      'are sized to fit the planner.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                    ],
                    heading('Cover'),
                    CoverPicker(
                      selected: _cover,
                      onChanged: (c) => setState(() {
                        _cover = c;
                        _coverChosen = true;
                      }),
                    ),
                    if (template == null && mine == null && _recipe == null)
                      PaperPicker(
                        selected: paper,
                        onChanged: (p) => setState(() => _paper = p),
                        stylePapers: ref.watch(stylePapersProvider),
                      ),
                    if (!isNew)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          "Pages that have their own paper keep it.",
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    heading('Theme'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in styles)
                          ChoiceChip(
                            label: Text(s.name),
                            selected: s.id == style.id,
                            onSelected: (_) => pickStyle(s),
                          ),
                      ],
                    ),
                    if (isNew && template == null && _recipe == null) ...[
                      heading('Page size'),
                      SegmentedButton<PaperSize>(
                        showSelectedIcon: false,
                        segments: [
                          for (final s in PaperSize.values)
                            ButtonSegment(value: s, label: Text(s.label)),
                        ],
                        selected: {_size},
                        onSelectionChanged: (s) =>
                            setState(() => _size = s.first),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<PaperOrientation>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: PaperOrientation.portrait,
                            icon: Icon(Icons.crop_portrait),
                            label: Text('Portrait'),
                          ),
                          ButtonSegment(
                            value: PaperOrientation.landscape,
                            icon: Icon(Icons.crop_landscape),
                            label: Text('Landscape'),
                          ),
                        ],
                        selected: {_orientation},
                        onSelectionChanged: (s) =>
                            setState(() => _orientation = s.first),
                      ),
                    ],
                    const SizedBox(height: 32),
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

/// What the notebook starts from, on the details step, with a way back to
/// choose again.
class _StartSummary extends StatelessWidget {
  const _StartSummary({
    required this.template,
    required this.mine,
    required this.paper,
    required this.onChange,
    this.recipe,
  });

  final CatalogItem? template;
  final Notebook? mine;
  final PlannerRecipe? recipe;
  final PaperStyle paper;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final template = this.template;
    final mine = this.mine;
    final recipe = this.recipe;
    final (title, subtitle) = switch ((template, mine)) {
      _ when recipe != null => (
        recipe.title,
        'Your own planner: ${recipe.pageCount} pages, with links between '
            'them.',
      ),
      (final t?, _) => (plannerName(t), templateSummary(t) ?? 'Planner'),
      (_, final m?) => (
        m.title,
        'A copy of your template: its sections, pages and everything on '
            'them.',
      ),
      _ => ('Blank notebook', 'Pick its paper below.'),
    };
    return Material(
      color: theme.colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Padding(
        padding: const EdgeInsets.all(Insets.md),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              height: 64,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: switch ((template, mine)) {
                  _ when recipe != null => RecipePage(
                    recipeKey: recipeKey(recipe),
                    group: 'home',
                    landscape: recipe.landscape,
                  ),
                  (final t?, _) => ItemPreview(item: t),
                  (_, final m?) => CoverView(cover: m.cover, elevation: 0),
                  _ => ColoredBox(
                    color: paper.color,
                    child: CustomPaint(
                      painter: PaperPainter(paper, scale: 0.3),
                    ),
                  ),
                },
              ),
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: onChange, child: const Text('Change')),
          ],
        ),
      ),
    );
  }
}

/// What the editor returns: the notebook, and the planner it starts from.
typedef NotebookEditorResult = ({
  NewNotebook notebook,
  CatalogItem? template,

  /// The planner's colourway (its PDF in the pack).
  String variant,

  /// The planner's page groups to leave out.
  Set<String> skip,

  /// The month a dated planner starts, or null for all of it.
  DateTime? from,

  /// One of the user's own templates to copy.
  Notebook? mine,

  /// A planner the user built, to make.
  PlannerRecipe? recipe,
});

/// The first page of a planner, as the editor's page preview.
class _TemplatePreview extends ConsumerWidget {
  const _TemplatePreview({required this.template, required this.file});

  final CatalogItem template;
  final String file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref
        .watch(
          templateImageProvider((
            template: templatePage(template, 1, file: file),
            width: 360,
          )),
        )
        .value;
    return SizedBox(
      width: 130,
      child: image == null
          ? const Skeleton(radius: 2)
          : DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              child: RawImage(image: image, fit: BoxFit.contain),
            ),
    );
  }
}

/// Swatches for a planner's colourways, when it has more than one.
class _ColourwayPicker extends ConsumerWidget {
  const _ColourwayPicker({
    required this.template,
    required this.selected,
    required this.onChanged,
  });

  final CatalogItem template;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = ref.watch(templateSpecProvider(template)).value;
    final variants = spec?.variants ?? const [];
    // Planners with a builder pick their PDF by layout and week start.
    if (variants.length < 2 || spec!.options.isNotEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Colours', style: Theme.of(context).textTheme.labelLarge),
          for (final v in variants)
            ChoiceChip(
              avatar: CircleAvatar(
                backgroundColor: Color(v.color ?? 0xFF888888),
              ),
              label: Text(v.name),
              selected: v.file == selected,
              onSelected: (_) => onChanged(v.file),
            ),
        ],
      ),
    );
  }
}

/// A planner's editions, by their dates. Locked ones show a lock, and
/// choosing one shows it in the store.
class _EditionPicker extends StatelessWidget {
  const _EditionPicker({
    required this.editions,
    required this.selected,
    required this.usable,
    required this.onChanged,
  });

  final List<CatalogItem> editions;
  final CatalogItem selected;
  final bool Function(CatalogItem) usable;
  final ValueChanged<CatalogItem> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Dates', style: Theme.of(context).textTheme.labelLarge),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in editions)
                ChoiceChip(
                  avatar: usable(e)
                      ? null
                      : const Icon(Icons.lock_outline, size: 16),
                  label: Text(editionLabel(e) ?? e.name),
                  selected: e.id == selected.id,
                  onSelected: (_) => onChanged(e),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
