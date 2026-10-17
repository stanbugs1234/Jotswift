import 'dart:math' as math;

import '../../shared/ui/skeleton.dart';
import '../../shared/ui/tokens.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/catalog_item.dart';
import '../../core/catalog/catalog_providers.dart';
import '../../core/catalog/template_spec.dart';
import '../canvas/templates.dart';
import '../store/store_item.dart';

/// A template as a card: its first page, name and page count, with a
/// button to look through every page. Tap to choose it; long-press also
/// looks inside. [preview] replaces the template's picture (for a blank
/// notebook or one of the user's own templates).
class TemplateCard extends StatelessWidget {
  const TemplateCard({
    required this.title,
    required this.selected,
    required this.onTap,
    this.item,
    this.preview,
    this.subtitle,
    this.onLookInside,
    super.key,
  });

  final CatalogItem? item;
  final Widget? preview;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLookInside;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final item = this.item;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title${item?.linked ?? false ? ', linked pages' : ''}',
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        onLongPress: onLookInside,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.md),
                  border: Border.all(
                    color: selected ? scheme.primary : scheme.outlineVariant,
                    width: selected ? 3 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    selected ? Radii.md - 3 : Radii.md - 1,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ?preview,
                      if (preview == null && item != null)
                        ItemPreview(item: item),
                      if (item?.linked ?? false)
                        const Positioned(
                          top: 6,
                          right: 6,
                          child: LinkedPagesBadge(size: 13),
                        ),
                      if (selected)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Icon(
                            Icons.check_circle,
                            color: scheme.primary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: Insets.sm),
            SizedBox(
              height: _textHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge,
                        ),
                        if (subtitle case final s?)
                          Text(
                            s,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (onLookInside case final look?)
                    IconButton(
                      tooltip: 'Look inside',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      iconSize: 20,
                      icon: const Icon(Icons.visibility_outlined),
                      onPressed: look,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Room under a card's picture: two lines of name and one of detail.
const _textHeight = 62.0;

/// A template's page count and whether its pages link, for a card.
String? templateSummary(CatalogItem item) => switch (item.pageCount) {
  final n? => item.linked ? '$n pages · linked' : '$n pages',
  null => item.linked ? 'Linked pages' : null,
};

/// A grid of cards that fills the width: as many columns as fit at about
/// [maxCardWidth], each card's picture 3:4 with room for its name below.
class TemplateCardGrid extends StatelessWidget {
  const TemplateCardGrid({
    required this.itemCount,
    required this.itemBuilder,
    this.maxCardWidth = 190,
    super.key,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double maxCardWidth;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      const gap = Insets.lg;
      final width = constraints.crossAxisExtent;
      final columns = math.max(
        2,
        ((width + gap) / (maxCardWidth + gap)).ceil(),
      );
      final cardWidth = (width - gap * (columns - 1)) / columns;
      return SliverGrid.builder(
        itemCount: itemCount,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: gap,
          mainAxisSpacing: Insets.xl,
          // The 3:4 picture, the gap and two lines of text.
          mainAxisExtent: cardWidth * 4 / 3 + Insets.sm + _textHeight,
        ),
        itemBuilder: itemBuilder,
      );
    },
  );
}

/// Shows every page of [item], by section. Returns true if the user chose
/// to use it. A [locked] item can't be downloaded yet, so it shows its
/// sample pages instead, with [lockedAction] (e.g. "Get with Pro") in place
/// of "Use this".
Future<bool?> showTemplatePages(
  BuildContext context,
  CatalogItem item, {
  bool locked = false,
  Widget? lockedAction,
}) => Navigator.of(context).push<bool>(
  MaterialPageRoute(
    builder: (_) => locked
        ? _SamplePagesScreen(item: item, action: lockedAction)
        : TemplatePagesScreen(item: item),
  ),
);

/// A locked template's sample pages, in a grid.
class _SamplePagesScreen extends StatelessWidget {
  const _SamplePagesScreen({required this.item, this.action});

  final CatalogItem item;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = item.samples.length;
    final total = item.pageCount;
    return Scaffold(
      appBar: AppBar(
        title: Text(item.name),
        actions: [
          if (action case final a?)
            Padding(padding: const EdgeInsets.only(right: 8), child: a),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Text(
                total != null && total > shown
                    ? '$shown of its $total pages. Unlock it to use them all.'
                    : 'Unlock it to use these pages.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid.builder(
              itemCount: shown,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 240,
                mainAxisSpacing: 20,
                crossAxisSpacing: 16,
                childAspectRatio: 0.66,
              ),
              itemBuilder: (context, i) =>
                  _SampleThumb(sample: item.samples[i], expand: true),
            ),
          ),
        ],
      ),
    );
  }
}

/// A sample page's picture and title.
class _SampleThumb extends ConsumerWidget {
  const _SampleThumb({required this.sample, this.expand = false});

  final CatalogSample sample;

  /// Fills its cell instead of the strip's fixed size.
  final bool expand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final image = ref.watch(catalogImageProvider(sample.path));
    final picture = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: switch (image) {
        AsyncData(:final value) => Image(image: value, fit: BoxFit.contain),
        AsyncError() => const SizedBox.expand(),
        _ => const Skeleton(radius: 0),
      },
    );
    return SizedBox(
      width: expand ? null : 150,
      child: Column(
        children: [
          if (expand)
            Expanded(child: picture)
          else
            SizedBox(height: 194, child: picture),
          const SizedBox(height: 4),
          Text(
            sample.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

/// A template's pages, section by section, to look through before
/// choosing it.
class TemplatePagesScreen extends ConsumerWidget {
  const TemplatePagesScreen({required this.item, super.key});

  final CatalogItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(item.name),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Use this'),
            ),
          ),
        ],
      ),
      body: switch (ref.watch(templateSpecProvider(item))) {
        AsyncData(value: final spec) => ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (item.linked)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  children: [
                    const LinkedPagesBadge(size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Linked pages: tap a date, tab or button to jump to '
                        'that page.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            for (final section in spec.sections)
              if (section.pages.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Text(
                    section.pages.length == 1
                        ? section.title
                        : '${section.title} · ${section.pages.length} pages',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                SizedBox(
                  height: 230,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: section.pages.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, i) =>
                        _PageThumb(item: item, page: section.pages[i]),
                  ),
                ),
              ],
          ],
        ),
        AsyncError() => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Could not download this template. Check your connection.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _PageThumb extends ConsumerWidget {
  const _PageThumb({required this.item, required this.page});

  final CatalogItem item;
  final TemplatePage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final image = ref
        .watch(
          templateImageProvider((
            template: templatePage(item, page.pdfPage),
            width: 300,
          )),
        )
        .value;
    return SizedBox(
      width: 150,
      child: Column(
        children: [
          Container(
            height: 194,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: image == null
                ? const Skeleton(radius: 0)
                : RawImage(image: image, fit: BoxFit.contain),
          ),
          const SizedBox(height: 4),
          Text(
            page.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

/// A template's first pages in a row, for a store item: what's inside
/// before choosing it. A [locked] item (which can't be downloaded yet)
/// shows its sample pages; otherwise nothing shows until the pages can be
/// read.
class TemplatePageStrip extends ConsumerWidget {
  const TemplatePageStrip({
    required this.item,
    this.locked = false,
    this.max = 12,
    super.key,
  });

  final CatalogItem item;
  final bool locked;
  final int max;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (locked) {
      final samples = item.samples.take(max).toList();
      if (samples.isEmpty) return const SizedBox.shrink();
      return SizedBox(
        height: 230,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: samples.length,
          separatorBuilder: (_, _) => const SizedBox(width: Insets.md),
          itemBuilder: (context, i) => _SampleThumb(sample: samples[i]),
        ),
      );
    }
    final spec = ref.watch(templateSpecProvider(item)).value;
    if (spec == null || spec.pages.isEmpty) return const SizedBox.shrink();
    final pages = spec.pages.take(max).toList();
    return SizedBox(
      height: 230,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: pages.length,
        separatorBuilder: (_, _) => const SizedBox(width: Insets.md),
        itemBuilder: (context, i) => _PageThumb(item: item, page: pages[i]),
      ),
    );
  }
}
