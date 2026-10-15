import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/catalog_item.dart';
import '../../core/catalog/catalog_providers.dart';
import '../shelf/cover_designs.dart';
import '../shelf/cover_view.dart';
import 'data/cover_photos.dart';
import 'domain/notebook_models.dart';

enum _CoverTab { colors, designs, photo }

/// Picks a cover: a color, a design in any color, or the user's photo.
class CoverPicker extends ConsumerStatefulWidget {
  const CoverPicker({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final NotebookCover selected;
  final ValueChanged<NotebookCover> onChanged;

  @override
  ConsumerState<CoverPicker> createState() => _CoverPickerState();
}

class _CoverPickerState extends ConsumerState<CoverPicker> {
  late _CoverTab _tab = switch (widget.selected.kind) {
    CoverKind.color => _CoverTab.colors,
    CoverKind.art => _CoverTab.designs,
    CoverKind.photo => _CoverTab.photo,
  };
  bool _uploading = false;

  NotebookCover get _cover => widget.selected;

  Future<void> _choosePhoto() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _uploading = true);
    try {
      final path = await chooseCoverPhoto(ref);
      if (path != null) {
        widget.onChanged(NotebookCover.photo(path, color: _cover.color));
      }
    } on Object catch (e) {
      debugPrint('Could not save cover photo: $e');
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save the photo. Check your connection and try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final design = CoverDesign.byId(_cover.coverId);

    Widget colorDot(int color, VoidCallback onTap) {
      final selected = _cover.color == color;
      final scheme = Theme.of(context).colorScheme;
      return Semantics(
        button: true,
        selected: selected,
        label: 'Cover color',
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Color(color),
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? scheme.primary : scheme.outline,
                width: selected ? 3 : 1,
              ),
            ),
          ),
        ),
      );
    }

    final colors = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final c in coverColors)
          colorDot(
            c,
            () => widget.onChanged(switch (_tab) {
              _CoverTab.designs => NotebookCover.art(
                (design ?? CoverDesign.stripes).id,
                color: c,
              ),
              _ => NotebookCover.color(c),
            }),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<_CoverTab>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: _CoverTab.colors, label: Text('Colors')),
            ButtonSegment(value: _CoverTab.designs, label: Text('Designs')),
            ButtonSegment(value: _CoverTab.photo, label: Text('Photo')),
          ],
          selected: {_tab},
          onSelectionChanged: (s) => setState(() => _tab = s.first),
        ),
        const SizedBox(height: 16),
        switch (_tab) {
          _CoverTab.colors => colors,
          _CoverTab.designs => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: CoverDesign.values.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final d = CoverDesign.values[i];
                    final cover = NotebookCover.art(d.id, color: _cover.color);
                    return Semantics(
                      button: true,
                      selected: d == design,
                      label: '${d.label} design',
                      excludeSemantics: true,
                      child: GestureDetector(
                        onTap: () => widget.onChanged(cover),
                        child: Column(
                          children: [
                            Expanded(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: d == design
                                      ? Border.all(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          width: 3,
                                        )
                                      : null,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(3),
                                  child: CoverView(cover: cover),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              d.label,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              colors,
              _CatalogCovers(selected: _cover, onChanged: widget.onChanged),
            ],
          ),
          _CoverTab.photo => Row(
            children: [
              if (_cover.kind == CoverKind.photo) ...[
                SizedBox(width: 72, child: CoverView(cover: _cover)),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: _uploading
                    ? const Center(child: CircularProgressIndicator())
                    : OutlinedButton.icon(
                        onPressed: _choosePhoto,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text(
                          _cover.kind == CoverKind.photo
                              ? 'Choose another photo'
                              : 'Choose a photo',
                        ),
                      ),
              ),
            ],
          ),
        },
      ],
    );
  }
}

/// Covers from the catalog, downloaded when picked.
class _CatalogCovers extends ConsumerWidget {
  const _CatalogCovers({required this.selected, required this.onChanged});

  final NotebookCover selected;
  final ValueChanged<NotebookCover> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(offeredCatalogProvider(CatalogKind.cover));
    if (items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text('More covers', style: theme.textTheme.titleSmall),
        ),
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final item = items[i];
              final isSelected = selected.coverId == item.id;
              final preview = ref.watch(catalogPreviewProvider(item)).value;
              return Semantics(
                button: true,
                selected: isSelected,
                label: '${item.name} cover',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () {
                    onChanged(
                      NotebookCover.art(
                        item.id,
                        color: item.color ?? selected.color,
                      ),
                    );
                    // Start downloading now, so the cover is ready.
                    ref.read(catalogCoverProvider(item.id).future).ignore();
                  },
                  child: Column(
                    children: [
                      Expanded(
                        child: AspectRatio(
                          aspectRatio: CoverView.aspectRatio,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Color(item.color ?? 0xFFCCCCCC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outline,
                                width: isSelected ? 3 : 1,
                              ),
                              image: preview == null
                                  ? null
                                  : DecorationImage(
                                      image: preview,
                                      fit: BoxFit.cover,
                                    ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(item.name, style: theme.textTheme.labelSmall),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
