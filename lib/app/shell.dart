import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/sync/sync_indicator.dart';
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

  /// At or above this: the sidebar with categories (large tablets, web).
  static const expanded = 1024.0;
}

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

/// The main app frame: bottom bar on phones, side rail on small tablets,
/// and a sidebar with the shelf's categories on large tablets and the web.
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
        body: OfflineBanner(child: navigationShell),
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

    final Widget side;
    if (width >= Breakpoints.expanded) {
      final onShelf = uri.path == '/notebooks';
      side = _Sidebar(
        branch: navigationShell.currentIndex,
        shelf: onShelf ? ShelfLocation.fromQuery(uri.queryParameters) : null,
        onBranch: _go,
      );
    } else {
      side = NavigationRail(
        labelType: NavigationRailLabelType.all,
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _go,
        leading: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Text('Jotswift', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              const SyncIndicator(),
            ],
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
          Expanded(child: OfflineBanner(child: navigationShell)),
        ],
      ),
    );
  }
}

/// Noteshelf-style sidebar: the shelf's views and categories, then the
/// other tabs.
class _Sidebar extends ConsumerWidget {
  const _Sidebar({
    required this.branch,
    required this.shelf,
    required this.onBranch,
  });

  final int branch;

  /// The open shelf location, or null when the shelf isn't showing.
  final ShelfLocation? shelf;
  final ValueChanged<int> onBranch;

  static const width = 260.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final categories = ref.watch(categoriesProvider).value ?? const [];

    Widget item(
      String label,
      IconData icon, {
      required bool selected,
      required VoidCallback onTap,
      Widget? trailing,
    }) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: ListTile(
        dense: true,
        selected: selected,
        selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(icon, size: 22),
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: trailing,
        onTap: onTap,
      ),
    );

    Widget shelfItem(
      String label,
      IconData icon,
      ShelfLocation to, {
      Widget? trailing,
    }) => item(
      label,
      icon,
      selected: branch == 0 && shelf == to,
      onTap: () => context.go(to.path),
      trailing: trailing,
    );

    return SizedBox(
      width: width,
      child: Material(
        color: theme.colorScheme.surface,
        child: SafeArea(
          right: false,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 8, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Jotswift', style: theme.textTheme.titleLarge),
                    ),
                    const SyncIndicator(),
                  ],
                ),
              ),
              shelfItem(
                'All notebooks',
                Icons.menu_book_outlined,
                const AllNotebooks(),
              ),
              shelfItem('Recent', Icons.schedule, const RecentNotebooks()),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 16, 6),
                child: Text('CATEGORIES', style: theme.textTheme.labelSmall),
              ),
              for (final c in categories)
                shelfItem(
                  c.title,
                  Icons.label_outline,
                  InCategory(c.id),
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
                Icons.add,
                selected: false,
                onTap: () => createCategory(context, ref),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1),
              ),
              for (var i = 1; i < _destinations.length; i++)
                item(
                  _destinations[i].label,
                  branch == i
                      ? _destinations[i].selectedIcon
                      : _destinations[i].icon,
                  selected: branch == i,
                  onTap: () => onBranch(i),
                ),
              item(
                'Templates',
                Icons.storefront_outlined,
                selected: false,
                onTap: () => context.push(storePath),
              ),
              item(
                'Settings',
                Icons.settings_outlined,
                selected: false,
                onTap: () => context.push('/settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
