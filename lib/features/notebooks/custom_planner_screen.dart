import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/planner_series.dart' show monthYear;
import '../../core/planner/book.dart' show day;
import '../../core/planner/page_kinds.dart';
import '../../core/planner/pdf_ops.dart';
import '../../core/planner/presets.dart';
import '../../core/planner/recipe.dart';
import '../../shared/ui/skeleton.dart';
import '../../shared/ui/tokens.dart';
import 'custom_planner.dart';

/// Builds a planner exactly as wanted: its dates, look, the pages under
/// each month, week and day, and its sections, with a picture of each
/// page. Returns the recipe; New notebook makes it.
class CustomPlannerScreen extends ConsumerStatefulWidget {
  const CustomPlannerScreen({required this.initial, super.key});

  final PlannerRecipe initial;

  static Future<PlannerRecipe?> show(
    BuildContext context,
    PlannerRecipe initial,
  ) => Navigator.of(context, rootNavigator: true).push<PlannerRecipe>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CustomPlannerScreen(initial: initial),
    ),
  );

  @override
  ConsumerState<CustomPlannerScreen> createState() =>
      _CustomPlannerScreenState();
}

/// Where a kind of page goes in the recipe.
enum _Place { front, month, week, day }

class _CustomPlannerScreenState extends ConsumerState<CustomPlannerScreen> {
  late PlannerRecipe _recipe = widget.initial;
  late final _title = TextEditingController(text: widget.initial.title);

  /// The page shown large: a group (see [previewPage]).
  String _shown = 'home';
  String _shownName = 'Home';

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _set(PlannerRecipe next) => setState(() => _recipe = next);

  void _show(String group, String name) => setState(() {
    _shown = group;
    _shownName = name;
  });

  List<KindRef> _refs(_Place place) => switch (place) {
    _Place.front => _recipe.front,
    _Place.month => _recipe.month,
    _Place.week => _recipe.week,
    _Place.day => _recipe.day,
  };

  void _setRefs(_Place place, List<KindRef> refs) => _set(switch (place) {
    _Place.front => _recipe.copyWith(front: refs),
    _Place.month => _recipe.copyWith(month: refs),
    _Place.week => _recipe.copyWith(week: refs),
    _Place.day => _recipe.copyWith(day: refs),
  });

  static KindPlace _kindPlace(_Place p) => switch (p) {
    _Place.front => KindPlace.front,
    _Place.month => KindPlace.month,
    _Place.week => KindPlace.week,
    _Place.day => KindPlace.day,
  };

  /// The group a kind's pages are previewed by.
  String _groupOf(_Place place, int i) {
    final refs = _refs(place);
    return place == _Place.month && i == 0 ? 'months' : refs[i].groupId;
  }

  Future<void> _addKind(_Place place) async {
    final at = place == _Place.front ? KindPlace.section : _kindPlace(place);
    final picked = await _pickKind(
      context,
      title: switch (place) {
        _Place.front => 'Add a page at the front',
        _Place.month => 'Add a page to each month',
        _Place.week => 'Add a page to each week',
        _Place.day => 'Add a page to each day',
      },
      fits: (k) => place == _Place.front
          ? k.needs == KindNeeds.nothing
          : k.fits(_kindPlace(place)),
      first: place == _Place.front ? KindPlace.front : at,
    );
    if (picked == null) return;
    final refs = _refs(place);
    // A second page of the same kind gets a group of its own.
    final taken = {for (final r in refs) r.groupId};
    var group = picked.id;
    for (var n = 2; taken.contains(group); n++) {
      group = '${picked.id}_$n';
    }
    final ref = KindRef(picked.id, group: group == picked.id ? null : group);
    _setRefs(place, [...refs, ref]);
    _show(
      place == _Place.month && refs.isEmpty ? 'months' : group,
      picked.name,
    );
  }

  Future<void> _addSection() async {
    final picked = await _pickKind(
      context,
      title: 'Add a section',
      fits: (k) => k.needs == KindNeeds.nothing,
      first: KindPlace.section,
    );
    if (picked == null) return;
    final keys = {for (final s in _recipe.sections) s.key};
    var key = picked.id;
    for (var n = 2; keys.contains(key); n++) {
      key = '${picked.id}_$n';
    }
    final section = SectionRecipe(
      key: key,
      title: picked.groupTitle,
      icon: picked.icon,
      runs: [PageRun(picked.id, picked.name, _defaultCount(picked))],
    );
    _set(_recipe.copyWith(sections: [..._recipe.sections, section]));
    _show('section:$key', section.title);
  }

  Future<void> _addRun(int s) async {
    final section = _recipe.sections[s];
    final picked = await _pickKind(
      context,
      title: 'Add pages to ${section.title}',
      fits: (k) => k.needs == KindNeeds.nothing,
      first: KindPlace.section,
    );
    if (picked == null) return;
    _setSection(
      s,
      section.copyWith(
        runs: [
          ...section.runs,
          PageRun(picked.id, picked.name, _defaultCount(picked)),
        ],
      ),
    );
  }

  static int _defaultCount(PageKindInfo k) =>
      const {'lined', 'dotted', 'grid', 'blank', 'checklist'}.contains(k.id)
      ? 10
      : 1;

  void _setSection(int s, SectionRecipe? section) {
    final sections = [..._recipe.sections];
    if (section == null) {
      sections.removeAt(s);
    } else {
      sections[s] = section;
    }
    _set(_recipe.copyWith(sections: sections));
  }

  Future<void> _rename(String current, ValueChanged<String> onDone) async {
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty) onDone(name.trim());
  }

  void _setTitle() {
    final title = _title.text.trim();
    if (title.isNotEmpty && title != _recipe.title) {
      _set(_recipe.copyWith(title: title));
    }
  }

  void _done() {
    _setTitle();
    Navigator.pop(context, _recipe);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = _recipe.book();
    final key = recipeKey(_recipe);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final preview = _BigPreview(
      recipeKey: key,
      group: _shown,
      name: _shownName,
      landscape: _recipe.landscape,
    );

    Widget heading(String text, [String? sub]) => Padding(
      padding: const EdgeInsets.only(top: Insets.xl, bottom: Insets.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(text, style: theme.textTheme.titleSmall),
          if (sub != null) ...[
            const SizedBox(width: Insets.sm),
            Text(
              sub,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );

    String perPage(_Place place) => switch (place) {
      _Place.front => '',
      _Place.month => '× ${book.n}',
      _Place.week => '× ${book.weekCount}',
      _Place.day => '× ${book.dayCount}',
    };

    Widget kinds(_Place place, String title, String sub) {
      final refs = _refs(place);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading(title, sub),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) {
              final next = [...refs];
              next.insert(to, next.removeAt(from));
              _setRefs(place, next);
            },
            children: [
              for (final (i, r) in refs.indexed)
                _KindRow(
                  key: ValueKey('${place.name}/${r.groupId}/$i'),
                  index: i,
                  recipeKey: key,
                  group: _groupOf(place, i),
                  name: r.title,
                  detail: [
                    if (place == _Place.month && i == 0) 'Main page',
                    r.info.about,
                    perPage(place),
                  ].where((s) => s.isNotEmpty).join(' · '),
                  landscape: _recipe.landscape,
                  selected: _shown == _groupOf(place, i),
                  onTap: () => _show(_groupOf(place, i), r.title),
                  onRename: () => _rename(r.title, (name) {
                    _setRefs(place, [
                      for (final (j, x) in refs.indexed)
                        j == i ? x.copyWith(name: name) : x,
                    ]);
                  }),
                  onRemove: () => _setRefs(place, [...refs]..removeAt(i)),
                ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => _addKind(place),
              icon: const Icon(Icons.add),
              label: const Text('Add a page'),
            ),
          ),
        ],
      );
    }

    final months = [
      for (var i = -6; i <= 18; i++)
        day(thisMonth().year, thisMonth().month + i, 1),
    ];
    final start = _recipe.start;

    final form = ListView(
      padding: EdgeInsets.fromLTRB(
        gutterOf(context),
        Insets.lg,
        gutterOf(context),
        Insets.xxxl,
      ),
      children: [
        if (!wide) ...[SizedBox(height: 240, child: preview)],
        TextField(
          controller: _title,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            floatingLabelBehavior: FloatingLabelBehavior.always,
          ),
          // On the Home page; changed when done typing, not each letter.
          onTapOutside: (_) {
            FocusScope.of(context).unfocus();
            _setTitle();
          },
          onSubmitted: (_) => _setTitle(),
        ),
        heading('Dates'),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: true, label: Text('Dated')),
            ButtonSegment(value: false, label: Text('Undated')),
          ],
          selected: {_recipe.dated},
          onSelectionChanged: (s) =>
              _set(_recipe.copyWith(start: () => s.first ? thisMonth() : null)),
        ),
        if (start != null)
          Padding(
            padding: const EdgeInsets.only(top: Insets.md),
            child: Wrap(
              spacing: Insets.lg,
              runSpacing: Insets.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Labelled(
                  'Starts',
                  DropdownButton<DateTime>(
                    value: months.contains(start) ? start : null,
                    hint: Text(monthYear(start)),
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final m in months)
                        DropdownMenuItem(value: m, child: Text(monthYear(m))),
                    ],
                    onChanged: (m) => _set(_recipe.copyWith(start: () => m)),
                  ),
                ),
                _Labelled(
                  'Length',
                  DropdownButton<int>(
                    value: _recipe.months,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (var n = 1; n <= 18; n++)
                        DropdownMenuItem(
                          value: n,
                          child: Text(n == 1 ? '1 month' : '$n months'),
                        ),
                    ],
                    onChanged: (n) => _set(_recipe.copyWith(months: n)),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: Insets.md),
          child: Wrap(
            spacing: Insets.lg,
            runSpacing: Insets.sm,
            children: [
              _Labelled(
                'Week starts',
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Monday')),
                    ButtonSegment(value: 6, label: Text('Sunday')),
                  ],
                  selected: {_recipe.weekStart},
                  onSelectionChanged: (s) =>
                      _set(_recipe.copyWith(weekStart: s.first)),
                ),
              ),
              _Labelled(
                'Layout',
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.crop_landscape),
                      label: Text('Landscape'),
                    ),
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.crop_portrait),
                      label: Text('Portrait'),
                    ),
                  ],
                  selected: {_recipe.landscape},
                  onSelectionChanged: (s) =>
                      _set(_recipe.copyWith(landscape: s.first)),
                ),
              ),
            ],
          ),
        ),
        heading('Look'),
        Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.sm,
          children: [
            for (final (id, (name, style)) in [
              ...collectionLooks.entries.map((e) => (e.key, e.value)),
              ...plainLooks.entries.map((e) => (e.key, e.value)),
            ])
              _LookChip(
                name: name,
                style: style,
                selected:
                    _sameStyle(style, _recipe.style) &&
                    (collectionLooks.containsKey(id)
                        ? _recipe.collectionId == id
                        : true),
                onTap: () => _set(
                  _recipe.copyWith(
                    style: style,
                    collectionId: () =>
                        collectionLooks.containsKey(id) ? id : null,
                  ),
                ),
              ),
          ],
        ),
        kinds(_Place.front, 'At the front', 'After the year'),
        kinds(_Place.month, 'Each month', 'Tabs open the first'),
        kinds(_Place.week, 'Each week', ''),
        kinds(_Place.day, 'Each day', ''),
        heading('Sections', 'After the months, each with its own tab'),
        for (final (s, section) in _recipe.sections.indexed)
          _SectionCard(
            key: ValueKey('section/${section.key}'),
            section: section,
            recipeKey: key,
            landscape: _recipe.landscape,
            selected: _shown == 'section:${section.key}',
            onTap: () => _show('section:${section.key}', section.title),
            onRename: () => _rename(
              section.title,
              (t) => _setSection(s, section.copyWith(title: t)),
            ),
            onRemove: () => _setSection(s, null),
            onRun: (r, run) => _setSection(
              s,
              section.copyWith(
                runs: [
                  for (final (j, x) in section.runs.indexed)
                    if (j != r) x else ?run,
                ],
              ),
            ),
            onAdd: () => _addRun(s),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: _addSection,
            icon: const Icon(Icons.add),
            label: const Text('Add a section'),
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: const Text('Build your planner'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Insets.lg),
            child: FilledButton(onPressed: _done, child: const Text('Done')),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: gutterOf(context),
            vertical: Insets.md,
          ),
          child: Text(
            '${book.pageCount} pages, with links between them.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ),
      body: SafeArea(
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: form),
                  SizedBox(
                    width: 420,
                    child: Padding(
                      padding: const EdgeInsets.all(Insets.xl),
                      child: preview,
                    ),
                  ),
                ],
              )
            : form,
      ),
    );
  }
}

bool _sameStyle(PlannerStyle a, PlannerStyle b) =>
    a.toMap().toString() == b.toMap().toString();

/// Lets the user pick a kind of page: those that [fits], [first]'s first.
Future<PageKindInfo?> _pickKind(
  BuildContext context, {
  required String title,
  required bool Function(PageKindInfo) fits,
  required KindPlace first,
}) {
  final kinds = [
    for (final k in pageKinds.values)
      if (fits(k)) k,
  ];
  const order = KindPlace.values;
  kinds.sort((a, b) {
    int rank(PageKindInfo k) => k.place == first ? -1 : order.indexOf(k.place);
    return rank(a) - rank(b);
  });
  return showModalBottomSheet<PageKindInfo>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.xl,
              0,
              Insets.xl,
              Insets.sm,
            ),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final k in kinds)
            ListTile(
              leading: Icon(plannerIcon(k.icon)),
              title: Text(k.groupTitle == k.name ? k.name : k.groupTitle),
              subtitle: k.about.isEmpty ? null : Text(k.about),
              onTap: () => Navigator.pop(context, k),
            ),
        ],
      ),
    ),
  );
}

/// The Material icon for a planner icon name.
IconData plannerIcon(String name) => switch (name) {
  'home' => Icons.home_outlined,
  'calendar' => Icons.calendar_month_outlined,
  'target' => Icons.track_changes,
  'heart' => Icons.favorite_border,
  'star' => Icons.star_border,
  'coin' => Icons.payments_outlined,
  'book' => Icons.menu_book_outlined,
  'briefcase' => Icons.work_outline,
  'check' => Icons.check_box_outlined,
  'sun' => Icons.wb_sunny_outlined,
  'moon' => Icons.nightlight_outlined,
  'drop' => Icons.water_drop_outlined,
  'bolt' => Icons.bolt,
  'cloud' => Icons.cloud_outlined,
  'list' => Icons.list,
  'leaf' => Icons.eco_outlined,
  'cap' => Icons.school_outlined,
  'chart' => Icons.show_chart,
  'pencil' => Icons.edit_outlined,
  'plane' => Icons.flight_outlined,
  'people' => Icons.people_outline,
  'gift' => Icons.card_giftcard,
  _ => Icons.description_outlined,
};

class _Labelled extends StatelessWidget {
  const _Labelled(this.label, this.child);

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(width: Insets.md),
      child,
    ],
  );
}

/// A page of the recipe, drawn small.
class RecipePage extends ConsumerWidget {
  const RecipePage({
    required this.recipeKey,
    required this.group,
    required this.landscape,
    this.width = 160,
    super.key,
  });

  final String recipeKey;
  final String group;
  final bool landscape;
  final int width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref
        .watch(
          recipePageProvider((recipe: recipeKey, group: group, width: width)),
        )
        .value;
    return AspectRatio(
      aspectRatio: landscape ? 792 / 612 : 612 / 792,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: image == null
            ? const Skeleton(radius: 0)
            : RawImage(image: image, fit: BoxFit.contain),
      ),
    );
  }
}

class _BigPreview extends StatelessWidget {
  const _BigPreview({
    required this.recipeKey,
    required this.group,
    required this.name,
    required this.landscape,
  });

  final String recipeKey;
  final String group;
  final String name;
  final bool landscape;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(
        child: Center(
          child: RecipePage(
            recipeKey: recipeKey,
            group: group,
            landscape: landscape,
            width: 900,
          ),
        ),
      ),
      const SizedBox(height: Insets.sm),
      Text(name, style: Theme.of(context).textTheme.labelLarge),
    ],
  );
}

class _KindRow extends StatelessWidget {
  const _KindRow({
    required this.index,
    required this.recipeKey,
    required this.group,
    required this.name,
    required this.detail,
    required this.landscape,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onRemove,
    super.key,
  });

  final int index;
  final String recipeKey, group, name, detail;
  final bool landscape, selected;
  final VoidCallback onTap, onRename, onRemove;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: ListTile(
      contentPadding: const EdgeInsets.only(left: Insets.xs),
      selected: selected,
      onTap: onTap,
      leading: SizedBox(
        width: 56,
        child: RecipePage(
          recipeKey: recipeKey,
          group: group,
          landscape: landscape,
        ),
      ),
      title: Text(name),
      subtitle: Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) => v == 'rename' ? onRename() : onRemove(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'remove', child: Text('Remove')),
            ],
          ),
          IconButton(
            tooltip: 'Remove $name',
            onPressed: onRemove,
            icon: const Icon(Icons.close),
          ),
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.all(Insets.sm),
              child: Icon(Icons.drag_handle),
            ),
          ),
        ],
      ),
    ),
  );
}

class _LookChip extends StatelessWidget {
  const _LookChip({
    required this.name,
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final PlannerStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (accent, tab, paper) = lookColors(style);
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onTap(),
      avatar: CircleAvatar(
        backgroundColor: paper,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: accent,
            shape: BoxShape.circle,
            border: Border.all(color: tab, width: 2),
          ),
        ),
      ),
      label: Text(name),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.recipeKey,
    required this.landscape,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onRemove,
    required this.onRun,
    required this.onAdd,
    super.key,
  });

  final SectionRecipe section;
  final String recipeKey;
  final bool landscape, selected;
  final VoidCallback onTap, onRename, onRemove, onAdd;

  /// A run changed, or removed (null).
  final void Function(int index, PageRun? run) onRun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: Insets.md),
      color: selected ? theme.colorScheme.secondaryContainer : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(Insets.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: RecipePage(
                      recipeKey: recipeKey,
                      group: 'section:${section.key}',
                      landscape: landscape,
                    ),
                  ),
                  const SizedBox(width: Insets.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(section.title, style: theme.textTheme.titleSmall),
                        Text(
                          '${section.pageCount} pages, with an index',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Rename ${section.title}',
                    onPressed: onRename,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Remove ${section.title}',
                    onPressed: onRemove,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              for (final (r, run) in section.runs.indexed)
                Row(
                  children: [
                    const SizedBox(width: 56 + Insets.md),
                    Expanded(child: Text(kindOf(run.kind).name)),
                    IconButton(
                      tooltip: 'Fewer',
                      onPressed: () => onRun(
                        r,
                        run.count > 1
                            ? run.copyWith(count: run.count - 1)
                            : null,
                      ),
                      icon: const Icon(Icons.remove),
                    ),
                    SizedBox(
                      width: 32,
                      child: Text('${run.count}', textAlign: TextAlign.center),
                    ),
                    IconButton(
                      tooltip: 'More',
                      onPressed: run.count < 100
                          ? () => onRun(r, run.copyWith(count: run.count + 1))
                          : null,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: const Text('Add pages'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
