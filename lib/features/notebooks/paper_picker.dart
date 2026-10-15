import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/paper/basic_papers.dart';
import '../../core/paper/paper_style.dart';
import '../../core/skins/skin_providers.dart';
import '../../core/skins/widgets/paper.dart';
import 'notes_providers.dart';

/// A paper offered by a notebook style, shown with the style's name.
typedef NamedPaper = ({String name, PaperStyle paper});

/// Line spacing choices, relative to each pattern's usual spacing.
enum PaperSpacing {
  narrow('Narrow', 0.8),
  medium('Medium', 1),
  wide('Wide', 1.25);

  const PaperSpacing(this.label, this.factor);

  final String label;
  final double factor;
}

/// Picks a paper: ruling, color (four basics or any color), line spacing,
/// favorites and the papers of the notebook styles.
class PaperPicker extends ConsumerWidget {
  const PaperPicker({
    required this.selected,
    required this.onChanged,
    this.stylePapers = const [],
    super.key,
  });

  final PaperStyle selected;
  final ValueChanged<PaperStyle> onChanged;
  final List<NamedPaper> stylePapers;

  /// [pattern] on [color] at [spacing], with ruling that suits the color.
  static PaperStyle make(
    PaperPattern pattern,
    Color color, {
    PaperSpacing spacing = PaperSpacing.medium,
  }) {
    final basic = BasicPaperColor.values
        .where((b) => b.color == color)
        .firstOrNull;
    final light = color.computeLuminance() > 0.4;
    final lineColor =
        basic?.lineColor ??
        Color.lerp(color, light ? Colors.black : Colors.white, 0.2)!;
    final margin =
        basic?.marginColor ??
        (light ? const Color(0xFFE3A99A) : const Color(0xFF8A5A5A));
    final lined =
        pattern == PaperPattern.lined || pattern == PaperPattern.narrowLined;
    return PaperStyle(
      color: color,
      lineColor: lineColor,
      marginColor: lined ? margin : null,
      pattern: pattern,
      spacing: (defaultSpacing(pattern) * spacing.factor).roundToDouble(),
    );
  }

  PaperSpacing get _spacing {
    final ratio = selected.spacing / defaultSpacing(selected.pattern);
    return PaperSpacing.values.reduce(
      (a, b) => (a.factor - ratio).abs() <= (b.factor - ratio).abs() ? a : b,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final favorites = ref.watch(favoritePapersProvider).value ?? const [];
    final isFavorite = favorites.contains(selected);
    final isBasicColor = BasicPaperColor.values.any(
      (b) => b.color == selected.color,
    );

    Widget heading(String text, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(text, style: theme.textTheme.titleSmall)),
          ?trailing,
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading(
          'Paper',
          trailing: IconButton(
            tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
            icon: Icon(isFavorite ? Icons.star : Icons.star_border),
            onPressed: () => ref
                .read(favoritePapersRepositoryProvider)
                .setFavoritePaper(selected, favorite: !isFavorite),
          ),
        ),
        if (favorites.isNotEmpty) ...[
          _PaperRow(
            papers: [for (final p in favorites) (name: '', paper: p)],
            selected: selected,
            onChanged: onChanged,
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final b in BasicPaperColor.values)
              ChoiceChip(
                avatar: _Swatch(color: b.color),
                label: Text(_colorName(b)),
                selected: selected.color == b.color,
                onSelected: (_) => onChanged(
                  make(selected.pattern, b.color, spacing: _spacing),
                ),
              ),
            ChoiceChip(
              avatar: isBasicColor
                  ? const Icon(Icons.palette_outlined, size: 18)
                  : _Swatch(color: selected.color),
              label: const Text('Custom'),
              selected: !isBasicColor,
              onSelected: (_) async {
                final color = await pickColor(context, selected.color);
                if (color != null) {
                  onChanged(make(selected.pattern, color, spacing: _spacing));
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        _PaperRow(
          papers: [
            for (final pattern in PaperPattern.values)
              (
                name: _patternName(pattern),
                paper: make(pattern, selected.color, spacing: _spacing),
              ),
          ],
          selected: selected,
          onChanged: onChanged,
          matchPatternOnly: true,
        ),
        const SizedBox(height: 12),
        SegmentedButton<PaperSpacing>(
          showSelectedIcon: false,
          segments: [
            for (final s in PaperSpacing.values)
              ButtonSegment(value: s, label: Text(s.label)),
          ],
          selected: {_spacing},
          onSelectionChanged: (s) => onChanged(
            make(selected.pattern, selected.color, spacing: s.first),
          ),
        ),
        if (stylePapers.isNotEmpty) ...[
          heading('From notebook styles'),
          _PaperRow(
            papers: stylePapers,
            selected: selected,
            onChanged: onChanged,
          ),
        ],
      ],
    );
  }

  static String _colorName(BasicPaperColor color) => switch (color) {
    BasicPaperColor.white => 'White',
    BasicPaperColor.cream => 'Cream',
    BasicPaperColor.gray => 'Gray',
    BasicPaperColor.dark => 'Dark',
  };

  static String _patternName(PaperPattern pattern) => switch (pattern) {
    PaperPattern.blank => 'Blank',
    PaperPattern.lined => 'Lined',
    PaperPattern.narrowLined => 'Narrow',
    PaperPattern.grid => 'Grid',
    PaperPattern.dot => 'Dot',
    PaperPattern.music => 'Music',
    PaperPattern.cornell => 'Cornell',
  };
}

/// A scrolling row of small paper previews.
class _PaperRow extends StatelessWidget {
  const _PaperRow({
    required this.papers,
    required this.selected,
    required this.onChanged,
    this.matchPatternOnly = false,
  });

  final List<NamedPaper> papers;
  final PaperStyle selected;
  final ValueChanged<PaperStyle> onChanged;

  /// Highlight by pattern (the color row decides the rest).
  final bool matchPatternOnly;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: papers.any((p) => p.name.isNotEmpty) ? 112 : 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: papers.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final (:name, :paper) = papers[i];
          final isSelected = matchPatternOnly
              ? paper.pattern == selected.pattern
              : paper == selected;
          return Semantics(
            button: true,
            selected: isSelected,
            label: name.isEmpty ? 'Favorite paper' : '$name paper',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => onChanged(paper),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 86,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isSelected ? scheme.primary : scheme.outline,
                        width: isSelected ? 3 : 1,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: CustomPaint(
                      painter: PaperPainter(paper, scale: 0.35),
                    ),
                  ),
                  if (name.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        name,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 18,
    height: 18,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Theme.of(context).colorScheme.outline),
    ),
  );
}

/// Asks for any color with hue, saturation and lightness sliders. Returns
/// null if cancelled.
Future<Color?> pickColor(BuildContext context, Color initial) =>
    showDialog<Color>(
      context: context,
      builder: (context) => _ColorDialog(initial: initial),
    );

class _ColorDialog extends StatefulWidget {
  const _ColorDialog({required this.initial});

  final Color initial;

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late HSLColor _color = HSLColor.fromColor(widget.initial);

  @override
  Widget build(BuildContext context) {
    Widget slider(
      String label,
      double value,
      double max,
      HSLColor Function(double) change,
    ) => Row(
      children: [
        SizedBox(width: 84, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            max: max,
            label: label,
            onChanged: (v) => setState(() => _color = change(v)),
          ),
        ),
      ],
    );

    return AlertDialog(
      title: const Text('Paper color'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 64,
            decoration: BoxDecoration(
              color: _color.toColor(),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          const SizedBox(height: 12),
          slider('Hue', _color.hue, 360, _color.withHue),
          slider('Saturation', _color.saturation, 1, _color.withSaturation),
          slider('Lightness', _color.lightness, 1, _color.withLightness),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _color.toColor()),
          child: const Text('Use color'),
        ),
      ],
    );
  }
}

/// Each usable notebook style's paper, named after the style.
final stylePapersProvider = Provider<List<NamedPaper>>(
  (ref) => [
    for (final s in ref.watch(usableSkinsProvider))
      (name: s.name, paper: s.paper.style),
  ],
);

/// The result of [showPagePaperSheet]: the page's own paper, or null to use
/// the notebook's paper.
typedef PagePaperChoice = ({PaperStyle? paper});

/// Asks for a page's paper, starting from [current]. With [notebookPaper]
/// the sheet also offers going back to the notebook's paper. Returns null
/// if cancelled.
Future<PagePaperChoice?> showPagePaperSheet(
  BuildContext context, {
  required PaperStyle current,
  bool offerNotebookPaper = false,
  String title = 'Page paper',
  String confirmLabel = 'Use this paper',
}) => showModalBottomSheet<PagePaperChoice>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => _PagePaperSheet(
    initial: current,
    offerNotebookPaper: offerNotebookPaper,
    title: title,
    confirmLabel: confirmLabel,
  ),
);

class _PagePaperSheet extends ConsumerStatefulWidget {
  const _PagePaperSheet({
    required this.initial,
    required this.offerNotebookPaper,
    required this.title,
    required this.confirmLabel,
  });

  final PaperStyle initial;
  final bool offerNotebookPaper;
  final String title;
  final String confirmLabel;

  @override
  ConsumerState<_PagePaperSheet> createState() => _PagePaperSheetState();
}

class _PagePaperSheetState extends ConsumerState<_PagePaperSheet> {
  late PaperStyle _paper = widget.initial;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            PaperPicker(
              selected: _paper,
              onChanged: (p) => setState(() => _paper = p),
              stylePapers: ref.watch(stylePapersProvider),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(context, (paper: _paper)),
              child: Text(widget.confirmLabel),
            ),
            if (widget.offerNotebookPaper)
              TextButton(
                onPressed: () => Navigator.pop(context, (paper: null)),
                child: const Text("Use the notebook's paper"),
              ),
          ],
        ),
      ),
    );
  }
}

/// The paper new pages in a notebook get: its own, else its style's.
PaperStyle notebookPaper(WidgetRef ref, String notebookId) =>
    ref.read(notebookProvider(notebookId)).value?.paper ??
    ref.read(notebookSkinProvider(notebookId)).paper.style;
