import '../../shared/ui/skeleton.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/catalog_item.dart';
import '../../core/catalog/catalog_providers.dart';
import '../../core/catalog/template_spec.dart';
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
import 'template_gallery.dart';
import 'notes_providers.dart' show myTemplatesProvider;

/// Makes a new notebook, or (with [editing]) changes one: title, cover,
/// paper and style. Returns the choices, or null if cancelled.
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

  /// One of the user's own templates to copy, instead of a planner.
  Notebook? _mine;
  bool _saving = false;

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
            ? (template?.name ?? mine?.title ?? 'Untitled notebook')
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
      mine: mine,
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
    final planners = isNew
        ? [
            for (final t in ref.watch(
              offeredCatalogProvider(CatalogKind.template),
            ))
              if (t.templateMode == TemplateMode.notebook) t,
          ]
        : const <CatalogItem>[];
    final template = _template;
    final mine = _mine;
    final myTemplates = isNew
        ? ref.watch(myTemplatesProvider).value ?? const <Notebook>[]
        : const <Notebook>[];

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(text, style: theme.textTheme.titleSmall),
    );

    void pickStyle(SkinManifest next) => setState(() {
      // Keep a paper the user chose; follow the style otherwise.
      if (_paper == null || _paper == style.paper.style) {
        _paper = next.paper.style;
      }
      _styleId = next.id;
    });

    final page = _size.dimensions(_orientation);

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(isNew ? 'New notebook' : 'Edit notebook'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
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
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      hintText: 'e.g. School, Work, Journal',
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                  if ((planners.isNotEmpty || myTemplates.isNotEmpty)) ...[
                    heading('Start with'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Blank pages'),
                          selected: template == null && mine == null,
                          onSelected: (_) => setState(() {
                            _template = null;
                            _mine = null;
                          }),
                        ),
                        for (final t in myTemplates)
                          ChoiceChip(
                            avatar: const Icon(
                              Icons.copy_all_outlined,
                              size: 18,
                            ),
                            tooltip: 'My template',
                            label: Text(t.title),
                            selected: t.id == mine?.id,
                            onSelected: (_) => setState(() {
                              _mine = t;
                              _template = null;
                              _cover = t.cover;
                              _styleId = t.collectionId ?? _styleId;
                            }),
                          ),
                      ],
                    ),
                    if (planners.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      TemplateGallery(
                        templates: planners,
                        selected: template,
                        onSelected: (t) => setState(() {
                          _template = t;
                          _mine = null;
                          _variant = PageTemplate.defaultFile;
                          _options = const {};
                          _skip = null;
                        }),
                      ),
                    ],
                    if (mine != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'A copy of your template: its sections, pages and '
                          'everything on them. Manage your templates in '
                          'Settings.',
                          style: theme.textTheme.bodySmall,
                        ),
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
                      ),
                    if (template != null &&
                        (ref
                                .watch(templateSpecProvider(template))
                                .value
                                ?.options
                                .isEmpty ??
                            true))
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
                    onChanged: (c) => setState(() => _cover = c),
                  ),
                  if (template == null && mine == null)
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
                  heading('Style (ink colors and fonts)'),
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
                  if (isNew && template == null) ...[
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

  /// One of the user's own templates to copy.
  Notebook? mine,
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
