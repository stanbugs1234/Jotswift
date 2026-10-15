import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/skins/skin_providers.dart';
import '../features/notebooks/notes_providers.dart';
import '../features/planner/planner_screen.dart';
import '../features/reminders/reminders.dart';
import '../features/shelf/shelf_actions.dart';
import '../features/shelf/shelf_view.dart';
import '../features/store/store_screen.dart';

/// Width breakpoints for the three layouts.
abstract final class Breakpoints {
  /// Below this: phone layout with a bottom navigation bar.
  static const medium = 600.0;

  /// At or above this: the sidebar starts open (large tablets, web,
  /// an iPad held sideways).
  static const expanded = 1024.0;
}

/// Whether the sidebar is open on tablets: null until the user opens or
/// hides it, then remembered on this device.
class SidebarOpenController extends Notifier<bool?> {
  static const _prefsKey = 'sidebarOpen';

  @override
  bool? build() => ref.watch(sharedPreferencesProvider).getBool(_prefsKey);

  void set(bool open) {
    state = open;
    ref.read(sharedPreferencesProvider).setBool(_prefsKey, open);
  }
}

final sidebarOpenProvider = NotifierProvider<SidebarOpenController, bool?>(
  SidebarOpenController.new,
);

/// Whether the sidebar shows at this screen width.
bool sidebarShown(BuildContext context, WidgetRef ref) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < Breakpoints.medium) return false;
  return ref.watch(sidebarOpenProvider) ?? width >= Breakpoints.expanded;
}

/// The serif used for big titles, like Noteshelf's.
TextStyle titleSerif(WidgetRef ref, TextStyle? base) =>
    ref.watch(fontResolverProvider).style('Fraunces', base);

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Must match the branch order in the router.
const _destinations = [
  _Destination('Notebooks', Icons.menu_book_outlined, Icons.menu_book),
  _Destination('Planner', Icons.view_day_outlined, Icons.view_day),
  _Destination('Calendar', Icons.calendar_month_outlined, Icons.calendar_month),
  _Destination('To-do', Icons.checklist_outlined, Icons.checklist),
];

/// The main app frame: bottom bar on phones, and on tablets and the web a
/// Noteshelf-style sidebar that can be hidden to a slim rail.
class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, required this.uri, super.key});

  final StatefulNavigationShell navigationShell;

  /// The current location, to highlight the open part of the shelf.
  final Uri uri;

  void _go(int index) => navigationShell.goBranch(
    index,
    initialLocation: index == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // While signed in, keep reminders scheduled, and open the day of a
    // tapped reminder in the Planner.
    ref.watch(reminderSyncProvider);
    ref.listen(reminderTapsProvider, (_, next) {
      if (next case AsyncData(value: final day)) {
        ref.read(plannerDayProvider.notifier).show(day);
        context.go(plannerPath);
      }
    });
    final width = MediaQuery.sizeOf(context).width;

    if (width < Breakpoints.medium) {
      return Scaffold(
        body: navigationShell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: _go,
          destinations: [
            for (final d in _destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
          ],
        ),
      );
    }

    final sidebarController = ref.read(sidebarOpenProvider.notifier);
    final Widget side;
    if (sidebarShown(context, ref)) {
      final onShelf = uri.path == '/notebooks';
      side = _Sidebar(
        branch: navigationShell.currentIndex,
        shelf: onShelf ? ShelfLocation.fromQuery(uri.queryParameters) : null,
        onBranch: _go,
        onHide: () => sidebarController.set(false),
      );
    } else {
      side = NavigationRail(
        labelType: NavigationRailLabelType.all,
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _go,
        leading: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: IconButton(
            tooltip: 'Show sidebar',
            icon: const Icon(Icons.view_sidebar_outlined),
            onPressed: () => sidebarController.set(true),
          ),
        ),
        destinations: [
          for (final d in _destinations)
            NavigationRailDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: Text(d.label),
            ),
        ],
      );
    }

    return Scaffold(
      body: Row(
        children: [
          side,
          const VerticalDivider(width: 1),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}

/// Noteshelf-style sidebar: colored tiles for Home, Starred, Unfiled and
/// Trash, a Templates tile, then categories and the other tabs in
/// sections that fold away.
class _Sidebar extends ConsumerWidget {
  const _Sidebar({
    required this.branch,
    required this.shelf,
    required this.onBranch,
    required this.onHide,
  });

  final int branch;

  /// The open shelf location, or null when the shelf isn't showing.
  final ShelfLocation? shelf;
  final ValueChanged<int> onBranch;
  final VoidCallback onHide;

  static const width = 272.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final counts = Shelf(
      ref.watch(notebooksProvider).value ?? const [],
      const [],
    );

    bool isOpen(ShelfLocation to) => branch == 0 && shelf == to;

    Widget tile(
      String label,
      IconData icon,
      Color color,
      ShelfLocation to, {
      int? count,
    }) => _SidebarTile(
      label: label,
      icon: icon,
      color: color,
      count: count,
      selected: isOpen(to),
      onTap: () => context.go(to.path),
    );

    Widget item(
      String label,
      IconData icon, {
      required bool selected,
      required VoidCallback onTap,
      Widget? trailing,
    }) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -1),
        selected: selected,
        selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(icon, size: 20),
        minLeadingWidth: 24,
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: trailing,
        onTap: onTap,
      ),
    );

    return SizedBox(
      width: width,
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        child: SafeArea(
          right: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    tooltip: 'Hide sidebar',
                    icon: const Icon(Icons.view_sidebar_outlined),
                    onPressed: onHide,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
                child: Text(
                  'Notely',
                  style: titleSerif(ref, theme.textTheme.headlineSmall),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: tile(
                                  'Home',
                                  Icons.home_outlined,
                                  _TileColors.home,
                                  const AllNotebooks(),
                                  count: counts.notebookCount,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: tile(
                                  'Starred',
                                  Icons.star_outline,
                                  _TileColors.starred,
                                  const StarredNotebooks(),
                                  count: counts.starredCount,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: tile(
                                  'Unfiled',
                                  Icons.inbox_outlined,
                                  _TileColors.unfiled,
                                  const UnfiledNotebooks(),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: tile(
                                  'Trash',
                                  Icons.delete_outline,
                                  _TileColors.trash,
                                  const TrashedNotebooks(),
                                  count: counts.trashCount,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _SidebarTile(
                            label: 'Templates',
                            icon: Icons.storefront_outlined,
                            color: _TileColors.templates,
                            badge: 'New',
                            selected: false,
                            onTap: () => context.push(storePath),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SidebarSection(
                      title: 'Categories',
                      children: [
                        item(
                          'Recent',
                          Icons.schedule,
                          selected: isOpen(const RecentNotebooks()),
                          onTap: () => context.go(const RecentNotebooks().path),
                        ),
                        for (final c in categories)
                          item(
                            c.title,
                            Icons.folder_outlined,
                            selected: isOpen(InCategory(c.id)),
                            onTap: () => context.go(InCategory(c.id).path),
                            trailing: IconButton(
                              tooltip: 'Category options',
                              iconSize: 18,
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.more_horiz),
                              onPressed: () => showCategoryMenu(
                                context,
                                ref,
                                c,
                                isOpen: shelf == InCategory(c.id),
                              ),
                            ),
                          ),
                        item(
                          'New category',
                          Icons.add_circle_outline,
                          selected: false,
                          onTap: () => createCategory(context, ref),
                        ),
                      ],
                    ),
                    _SidebarSection(
                      title: 'Plan',
                      children: [
                        for (var i = 1; i < _destinations.length; i++)
                          item(
                            _destinations[i].label,
                            branch == i
                                ? _destinations[i].selectedIcon
                                : _destinations[i].icon,
                            selected: branch == i,
                            onTap: () => onBranch(i),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: item(
                  'Settings',
                  Icons.settings_outlined,
                  selected: false,
                  onTap: () => context.push('/settings'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sidebar tiles' colors, as in Noteshelf: the same in every skin so
/// each place is easy to spot.
abstract final class _TileColors {
  static const home = Color(0xFFE0533F);
  static const starred = Color(0xFFC79A2E);
  static const unfiled = Color(0xFF4C8BC9);
  static const trash = Color(0xFF8C8C8C);
  static const templates = Color(0xFF3E9A6B);
}

/// A rounded, tinted tile; filled with its color when [selected].
class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
    this.count,
    this.badge,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  /// Shown at the top right, unless zero.
  final int? count;

  /// A small label at the top right, like "New".
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final foreground = selected ? Colors.white : theme.colorScheme.onSurface;
    final count = this.count;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? color : color.withValues(alpha: dark ? 0.24 : 0.14),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      icon,
                      size: 20,
                      color: selected ? Colors.white : color,
                    ),
                    const Spacer(),
                    if (count != null && count > 0)
                      Text(
                        '$count',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (badge case final badge?)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badge,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A titled part of the sidebar that folds away with its chevron.
class _SidebarSection extends StatefulWidget {
  const _SidebarSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  State<_SidebarSection> createState() => _SidebarSectionState();
}

class _SidebarSectionState extends State<_SidebarSection> {
  var _open = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.title, style: theme.textTheme.titleSmall),
                ),
                AnimatedRotation(
                  turns: _open ? 0 : -0.25,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    Icons.expand_more,
                    size: 20,
                    semanticLabel: _open
                        ? 'Hide ${widget.title}'
                        : 'Show ${widget.title}',
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_open) ...widget.children,
      ],
    );
  }
}
