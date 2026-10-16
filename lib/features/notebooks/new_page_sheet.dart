import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/catalog/catalog_item.dart';
import '../../core/catalog/catalog_providers.dart';
import '../../core/catalog/template_spec.dart';
import '../../core/entitlements/entitlements.dart';
import '../../core/paper/paper_style.dart';
import '../../core/skins/widgets/paper.dart';
import '../canvas/templates.dart';
import '../store/store_item.dart';
import '../store/store_screen.dart';
import 'data/notes_repository.dart';

/// What the New page sheet chose.
sealed class NewPageChoice {
  const NewPageChoice();
}

/// A blank page on the notebook's paper.
class BlankPageChoice extends NewPageChoice {
  const BlankPageChoice();
}

/// A blank page on a paper still to be picked.
class OtherPaperChoice extends NewPageChoice {
  const OtherPaperChoice();
}

/// A page of a template.
class TemplatePageChoice extends NewPageChoice {
  const TemplatePageChoice(this.page);

  final NewPage page;
}

/// Asks what kind of page to add: blank, another paper, or any page of any
/// template. Templates the user doesn't have yet are listed too and open
/// their store page. Returns null if cancelled.
Future<NewPageChoice?> showNewPageSheet(
  BuildContext context, {
  required PaperStyle paper,
}) => showModalBottomSheet<NewPageChoice>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => _NewPageSheet(paper: paper),
);

/// One row of the sheet.
sealed class _Row {
  const _Row();
}

class _Heading extends _Row {
  const _Heading(this.text);
  final String text;
}

class _Usable extends _Row {
  const _Usable(this.item);
  final CatalogItem item;
}

class _Locked extends _Row {
  const _Locked(this.item);
  final CatalogItem item;
}

class _NewPageSheet extends ConsumerWidget {
  const _NewPageSheet({required this.paper});

  final PaperStyle paper;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final entitlements = ref.watch(entitlementsProvider);
    final templates = [
      for (final t in ref.watch(storeCatalogProvider))
        if (t.kind == CatalogKind.template && t.templateMode != null) t,
    ];
    final usable = templates.where(entitlements.canUseCatalogItem).toList();
    final locked = templates.where((t) => !usable.contains(t)).toList();
    // Page packs first, then the pages of planners.
    usable.sort(
      (a, b) =>
          (a.templateMode == TemplateMode.pages ? 0 : 1) -
          (b.templateMode == TemplateMode.pages ? 0 : 1),
    );
    final rows = <_Row>[
      for (final item in usable) _Usable(item),
      if (locked.isNotEmpty) const _Heading('More in the store'),
      for (final item in locked) _Locked(item),
    ];

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          itemCount: rows.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('New page', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _Tile(
                        label: 'Blank page',
                        onTap: () =>
                            Navigator.pop(context, const BlankPageChoice()),
                        child: CustomPaint(
                          painter: PaperPainter(paper, scale: 0.18),
                          child: const SizedBox.expand(),
                        ),
                      ),
                      _Tile(
                        label: 'Other paper…',
                        onTap: () =>
                            Navigator.pop(context, const OtherPaperChoice()),
                        child: Icon(
                          Icons.palette_outlined,
                          size: 36,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (templates.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Text(
                        'Templates appear here once they download. Check '
                        'your connection.',
                      ),
                    ),
                ],
              );
            }
            return switch (rows[i - 1]) {
              _Heading(:final text) => Padding(
                padding: const EdgeInsets.only(top: 28, bottom: 4),
                child: Text(text, style: theme.textTheme.titleMedium),
              ),
              _Usable(:final item) => _TemplateRow(item: item),
              _Locked(:final item) => _LockedRow(item: item),
            };
          },
        ),
      ),
    );
  }
}

/// A template the user has: its pages, or for a planner, one tile per
/// section that opens the section's pages.
class _TemplateRow extends ConsumerWidget {
  const _TemplateRow({required this.item});

  final CatalogItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Row(
            children: [
              Flexible(
                child: Text(item.name, style: theme.textTheme.titleSmall),
              ),
              if (item.linked) ...[
                const SizedBox(width: 8),
                const LinkedPagesBadge(size: 12),
              ],
            ],
          ),
        ),
        switch (ref.watch(templateSpecProvider(item))) {
          AsyncData(value: final spec) when spec.mode == TemplateMode.pages =>
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final page in spec.pages)
                  _TemplatePageTile(item: item, page: page),
              ],
            ),
          AsyncData(value: final spec) => SizedBox(
            height: 190,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final section in spec.sections)
                  if (section.pages.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _TemplatePageTile(
                        item: item,
                        page: section.pages.first,
                        label: section.pages.length == 1
                            ? section.pages.first.title
                            : '${section.title} · ${section.pages.length} ›',
                        semantics: section.pages.length == 1
                            ? null
                            : '${section.title} pages of ${item.name}',
                        onTap: section.pages.length == 1
                            ? null
                            : () => _openSection(context, item, section),
                      ),
                    ),
              ],
            ),
          ),
          AsyncError() => const Text(
            'Could not download these templates. Check your connection.',
          ),
          _ => const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          ),
        },
      ],
    );
  }

  Future<void> _openSection(
    BuildContext context,
    CatalogItem item,
    ({String title, List<TemplatePage> pages}) section,
  ) async {
    final choice = await Navigator.of(context).push<TemplatePageChoice>(
      MaterialPageRoute(
        builder: (_) => _SectionPagesScreen(item: item, section: section),
      ),
    );
    if (choice != null && context.mounted) Navigator.pop(context, choice);
  }
}

/// Every page of one planner section, to pick one.
class _SectionPagesScreen extends StatelessWidget {
  const _SectionPagesScreen({required this.item, required this.section});

  final CatalogItem item;
  final ({String title, List<TemplatePage> pages}) section;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${item.name} · ${section.title}')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 130,
          mainAxisExtent: 190,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: section.pages.length,
        itemBuilder: (context, i) =>
            _TemplatePageTile(item: item, page: section.pages[i]),
      ),
    );
  }
}

/// A template the user doesn't have yet: opens its store page.
class _LockedRow extends ConsumerWidget {
  const _LockedRow({required this.item});

  final CatalogItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 44,
        height: 56,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: ItemPreview(item: item),
        ),
      ),
      title: Row(
        children: [
          Flexible(child: Text(item.name)),
          if (item.linked) ...[
            const SizedBox(width: 8),
            const LinkedPagesBadge(size: 12),
          ],
        ],
      ),
      subtitle: Text(kindLabel(item)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(ref.watch(itemBadgeProvider(item))),
          const SizedBox(width: 6),
          const Icon(Icons.lock_outline, size: 18),
        ],
      ),
      onTap: () {
        final router = GoRouter.of(context);
        Navigator.pop(context);
        router.push('$storePath/${item.id}');
      },
    );
  }
}

/// A template page's picture and title. Picks the page unless [onTap]
/// says otherwise.
class _TemplatePageTile extends ConsumerWidget {
  const _TemplatePageTile({
    required this.item,
    required this.page,
    this.label,
    this.semantics,
    this.onTap,
  });

  final CatalogItem item;
  final TemplatePage page;
  final String? label;
  final String? semantics;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref
        .watch(
          templateImageProvider((
            template: templatePage(item, page.pdfPage),
            width: 240,
          )),
        )
        .value;
    return _Tile(
      label: label ?? page.title,
      semantics: semantics ?? '${page.title} template',
      onTap:
          onTap ??
          () => Navigator.pop(
            context,
            TemplatePageChoice(templateNewPage(item, page)),
          ),
      child: image == null
          ? const Center(child: CircularProgressIndicator())
          : RawImage(image: image, fit: BoxFit.contain),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.onTap,
    required this.child,
    this.semantics,
  });

  final String label;
  final String? semantics;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: semantics ?? label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          width: 110,
          child: Column(
            children: [
              Container(
                height: 140,
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: theme.colorScheme.outline),
                ),
                child: child,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
