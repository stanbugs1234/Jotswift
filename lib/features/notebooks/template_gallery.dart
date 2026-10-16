import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/catalog_item.dart';
import '../../core/catalog/template_spec.dart';
import '../canvas/templates.dart';
import '../store/store_item.dart';

/// Planners to start a notebook with, as cards showing what each looks
/// like. Tap a card to choose it; "Look inside" shows every page first.
class TemplateGallery extends StatelessWidget {
  const TemplateGallery({
    required this.templates,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final List<CatalogItem> templates;
  final CatalogItem? selected;
  final ValueChanged<CatalogItem> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 286,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: templates.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final t = templates[i];
          return _TemplateCard(
            item: t,
            selected: t.id == selected?.id,
            onTap: () => onSelected(t),
            onLookInside: () async {
              if (await showTemplatePages(context, t) == true) onSelected(t);
            },
          );
        },
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onLookInside,
  });

  final CatalogItem item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLookInside;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      width: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            selected: selected,
            label: '${item.name}${item.linked ? ', linked pages' : ''}',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              onLongPress: onLookInside,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: 168,
                    width: 132,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? scheme.primary
                            : scheme.outlineVariant,
                        width: selected ? 3 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(selected ? 7 : 9),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ItemPreview(item: item),
                          if (item.linked)
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
                  const SizedBox(height: 4),
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge,
                  ),
                  if (item.pageCount case final n?)
                    Text('$n pages', style: theme.textTheme.labelSmall),
                ],
              ),
            ),
          ),
          const Spacer(),
          TextButton.icon(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
            onPressed: onLookInside,
            icon: const Icon(Icons.visibility_outlined, size: 16),
            label: const Text('Look inside'),
          ),
        ],
      ),
    );
  }
}

/// Shows every page of [item], by section. Returns true if the user chose
/// to use it.
Future<bool?> showTemplatePages(BuildContext context, CatalogItem item) =>
    Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TemplatePagesScreen(item: item)),
    );

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
                ? const Center(child: CircularProgressIndicator())
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
