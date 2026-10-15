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
    if (template != null) {
      // A planner's pages are sized to fit its PDF.
      setState(() => _saving = true);
      try {
        final pdf = await ref.read(catalogTemplatePdfProvider(template).future);
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
        title: title.isEmpty ? (template?.name ?? 'Untitled notebook') : title,
        cover: _cover,
        paper: _paper ?? style.paper.style,
        paperSize: size,
        orientation: orientation,
        collectionId: style.id,
        place: widget.initial.place,
      ),
      template: template,
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
                          _TemplatePreview(template: template)
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
                    autofocus: isNew,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      hintText: 'e.g. School, Work, Journal',
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                  if (planners.isNotEmpty) ...[
                    heading('Start with'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Blank pages'),
                          selected: template == null,
                          onSelected: (_) => setState(() => _template = null),
                        ),
                        for (final t in planners)
                          ChoiceChip(
                            avatar: const Icon(Icons.event_note, size: 18),
                            label: Text(t.name),
                            selected: t.id == template?.id,
                            onSelected: (_) => setState(() => _template = t),
                          ),
                      ],
                    ),
                    if (template != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '${template.pageCount ?? 'All'} pages, with links '
                          'between them. Pages are sized to fit the planner.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                  heading('Cover'),
                  CoverPicker(
                    selected: _cover,
                    onChanged: (c) => setState(() => _cover = c),
                  ),
                  if (template == null)
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
typedef NotebookEditorResult = ({NewNotebook notebook, CatalogItem? template});

/// The first page of a planner, as the editor's page preview.
class _TemplatePreview extends ConsumerWidget {
  const _TemplatePreview({required this.template});

  final CatalogItem template;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref
        .watch(
          templateImageProvider((
            template: templatePage(template, 1),
            width: 360,
          )),
        )
        .value;
    return SizedBox(
      width: 130,
      child: image == null
          ? const Center(child: CircularProgressIndicator())
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
