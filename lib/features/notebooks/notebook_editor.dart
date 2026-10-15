import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/paper/paper_style.dart';
import '../../core/skins/skin_manifest.dart';
import '../../core/skins/skin_providers.dart';
import '../../core/skins/widgets/paper.dart';
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
  const NotebookEditor({required this.initial, this.editing, super.key});

  final NewNotebook initial;

  /// The notebook being changed, or null for a new one.
  final Notebook? editing;

  static Future<NewNotebook?> show(
    BuildContext context, {
    required NewNotebook initial,
    Notebook? editing,
  }) => Navigator.of(context, rootNavigator: true).push<NewNotebook>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) => NotebookEditor(initial: initial, editing: editing),
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

  void _save() {
    final title = _title.text.trim();
    final style = _style;
    // Save the paper and style the user saw, so later changes to the
    // default style don't change this notebook.
    Navigator.pop(
      context,
      NewNotebook(
        title: title.isEmpty ? 'Untitled notebook' : title,
        cover: _cover,
        paper: _paper ?? style.paper.style,
        paperSize: _size,
        orientation: _orientation,
        collectionId: style.id,
        place: widget.initial.place,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styles = ref.watch(usableSkinsProvider);
    ref.watch(activeSkinProvider);
    final style = _style;
    final paper = _paper ?? style.paper.style;
    final isNew = widget.editing == null;

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
              onPressed: _save,
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
                  heading('Cover'),
                  CoverPicker(
                    selected: _cover,
                    onChanged: (c) => setState(() => _cover = c),
                  ),
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
                  if (isNew) ...[
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
