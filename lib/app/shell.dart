import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Width breakpoints for the three layouts.
abstract final class Breakpoints {
  /// Below this: phone layout with a bottom navigation bar.
  static const medium = 600.0;

  /// At or above this: wide sidebar with labels (large tablets, web).
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

/// The main app frame: bottom bar on phones, side rail on tablets and web.
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  void _go(int index) => navigationShell.goBranch(
    index,
    initialLocation: index == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context) {
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

    final extended = width >= Breakpoints.expanded;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: extended,
            labelType: extended ? null : NavigationRailLabelType.all,
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _go,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Motley',
                style: Theme.of(context).textTheme.titleLarge,
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
          ),
          const VerticalDivider(width: 1),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}
