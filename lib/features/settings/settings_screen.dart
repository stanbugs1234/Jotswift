import '../../shared/ui/tokens.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/entitlements/entitlements.dart';
import '../../core/purchases/purchases_providers.dart';
import '../../core/input/finger_drawing.dart';
import '../../core/motion/motion.dart';
import '../../core/motion/page_turn.dart';
import '../../core/settings/appearance.dart';
import '../../core/skins/skin_providers.dart';
import '../auth/auth_repository.dart';
import '../calendar/calendar_providers.dart' show monthAnimationProvider;
import '../calendar/templates/calendar_look.dart' show calendarTemplateProvider;
import '../calendar/templates/calendar_templates_screen.dart';
import '../canvas/ink_tools.dart';
import '../canvas/pen_rail.dart';
import '../canvas/toolbar_layout.dart';
import '../canvas/pencil_actions.dart';
import '../skins/notebook_style_screen.dart';
import '../store/paywall.dart';
import 'page_turn_picker.dart';
import '../store/store_actions.dart';
import '../store/store_screen.dart';
import '../notebooks/my_templates.dart';
import '../notebooks/notes_providers.dart' show myTemplatesProvider;

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'This permanently deletes your account and all your notebooks, '
          'tasks and events. It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(authRepositoryProvider).deleteAccount();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).value;
    final skin = ref.watch(activeSkinProvider);

    final theme = Theme.of(context);
    final purchases = ref.watch(purchasesClientProvider).isAvailable;

    // A choice of a few, under the row it belongs to.
    Widget segments<T>(
      List<(T, String)> options,
      T selected,
      ValueChanged<T> onChanged,
    ) => Padding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.md),
      child: SegmentedButton<T>(
        showSelectedIcon: false,
        segments: [
          for (final (value, label) in options)
            ButtonSegment(value: value, label: Text(label)),
        ],
        selected: {selected},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );

    Widget link(
      IconData icon,
      String title,
      String? subtitle,
      VoidCallback onTap,
    ) => ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              gutterOf(context),
              Insets.sm,
              gutterOf(context),
              Insets.xxl,
            ),
            children: [
              _Group(
                title: 'Account',
                children: [
                  ListTile(
                    leading: const Icon(Icons.account_circle_outlined),
                    title: Text(
                      user?.displayName ?? user?.email ?? 'Signed in',
                    ),
                    subtitle: const Text('Signed in'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Sign out'),
                    onTap: () => ref.read(authRepositoryProvider).signOut(),
                  ),
                ],
              ),
              _Group(
                title: 'Appearance',
                children: [
                  const ListTile(
                    leading: Icon(Icons.contrast),
                    title: Text('Light or dark'),
                    subtitle: Text(
                      'Pages keep their own paper in light and dark.',
                    ),
                  ),
                  segments(
                    const [
                      (ThemeMode.system, 'System'),
                      (ThemeMode.light, 'Light'),
                      (ThemeMode.dark, 'Dark'),
                    ],
                    ref.watch(themeModeProvider),
                    ref.read(appearanceProvider.notifier).set,
                  ),
                  link(
                    Icons.palette_outlined,
                    'Notebook style',
                    skin.name,
                    () => context.push(notebookStylePath),
                  ),
                  const ListTile(
                    leading: Icon(Icons.animation),
                    title: Text('Animations'),
                    subtitle: Text(
                      'Page turns, opening notebooks and other motion. '
                      "Your device's Reduce Motion setting also tones them "
                      'down.',
                    ),
                  ),
                  segments(
                    const [
                      (AnimationLevel.full, 'Full'),
                      (AnimationLevel.reduced, 'Reduced'),
                      (AnimationLevel.off, 'Off'),
                    ],
                    ref.watch(animationLevelProvider),
                    ref.read(animationLevelProvider.notifier).set,
                  ),
                  link(
                    Icons.auto_stories_outlined,
                    'Page turn style',
                    ref.watch(pageTurnStyleProvider).label,
                    () => showPageTurnPicker(context),
                  ),
                  link(
                    Icons.calendar_month_outlined,
                    'Calendar template & animation',
                    '${ref.watch(calendarTemplateProvider).name} · '
                        '${ref.watch(monthAnimationProvider).label}',
                    () => showCalendarTemplates(context),
                  ),
                ],
              ),
              _Group(
                title: 'Apple Pencil & touch',
                children: [
                  ListTile(
                    leading: const Icon(Icons.draw_outlined),
                    title: const Text('Fingers'),
                    subtitle: Text(switch (ref.watch(fingerDrawingProvider)) {
                      FingerDrawing.device =>
                        ref.watch(devicePencilProvider).pencilOnly
                            ? 'Fingers scroll and zoom: your iPad is set to '
                                  'Only Draw with Apple Pencil.'
                            : ref.watch(fingersDrawProvider)
                            ? 'Fingers draw, following this device.'
                            : 'Fingers scroll and zoom, since you use a '
                                  'stylus.',
                      FingerDrawing.on => 'Fingers draw on pages.',
                      FingerDrawing.off =>
                        'Fingers scroll and zoom; only the pen draws.',
                    }),
                  ),
                  segments(
                    const [
                      (FingerDrawing.device, 'Follow device'),
                      (FingerDrawing.on, 'Finger draws'),
                      (FingerDrawing.off, 'Pen only'),
                    ],
                    ref.watch(fingerDrawingProvider),
                    ref.read(fingerDrawingProvider.notifier).set,
                  ),
                  link(
                    Icons.handyman_outlined,
                    'Toolbar',
                    'Put the page tools in your order, and hide the ones you '
                        'don\'t use.',
                    () => showToolbarEditor(context),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.touch_app_outlined),
                    title: const Text('Tap to undo'),
                    subtitle: const Text(
                      'Tap with two fingers to undo, three to redo. A quick '
                      'pinch fits the page to the screen.',
                    ),
                    value: ref.watch(fingerTapUndoProvider),
                    onChanged: ref.read(fingerTapUndoProvider.notifier).set,
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.gesture),
                    title: const Text('Scribble to erase'),
                    subtitle: const Text(
                      'Scribble over writing with the pen to erase it.',
                    ),
                    value: ref.watch(scribbleEraseProvider),
                    onChanged: ref.read(scribbleEraseProvider.notifier).set,
                  ),
                  // Phones always keep pen options in the toolbar.
                  if (MediaQuery.sizeOf(context).shortestSide >=
                      PenRail.minShortestSide) ...[
                    ListTile(
                      leading: const Icon(Icons.view_sidebar_outlined),
                      title: const Text('Pen colors and sizes'),
                      subtitle: Text(switch (ref.watch(penPanelSideProvider)) {
                        PenPanelSide.left =>
                          'In a panel on the left of the page.',
                        PenPanelSide.right =>
                          'In a panel on the right of the page.',
                        PenPanelSide.toolbar =>
                          'In the toolbar above the page.',
                      }),
                    ),
                    segments(
                      const [
                        (PenPanelSide.left, 'Left'),
                        (PenPanelSide.right, 'Right'),
                        (PenPanelSide.toolbar, 'Toolbar'),
                      ],
                      ref.watch(penPanelSideProvider),
                      ref.read(penPanelSideProvider.notifier).set,
                    ),
                  ],
                  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
                    for (final gesture in PencilGesture.values)
                      _PencilGestureTile(gesture: gesture),
                ],
              ),
              _Group(
                title: 'Templates & Pro',
                children: [
                  link(
                    Icons.auto_awesome_outlined,
                    'Jotswift Pro',
                    ref.watch(entitlementsProvider).pro
                        ? 'You have Pro'
                        : 'Unlimited notebooks and everything marked Pro',
                    () => showPaywall(context, ref),
                  ),
                  link(
                    Icons.storefront_outlined,
                    'Templates',
                    'Planners, covers, papers and stickers',
                    () => context.push(storePath),
                  ),
                  link(
                    Icons.copy_all_outlined,
                    'My templates',
                    switch (ref.watch(myTemplatesProvider).value?.length ?? 0) {
                      0 =>
                        'Save any notebook as a template to start new ones '
                            'from',
                      1 => '1 template',
                      final n => '$n templates',
                    },
                    () => context.push(myTemplatesPath),
                  ),
                  if (purchases)
                    ListTile(
                      leading: const Icon(Icons.restore),
                      title: const Text('Restore purchases'),
                      onTap: () => restorePurchases(context, ref),
                    ),
                ],
              ),
              _Group(
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.delete_forever_outlined,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      'Delete account',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    onTap: () => _confirmDelete(context, ref),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Settings that belong together, on one rounded card under a heading.
class _Group extends StatelessWidget {
  const _Group({required this.children, this.title});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title case final t?)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.lg,
                Insets.sm,
                Insets.lg,
                Insets.sm,
              ),
              child: Text(
                t,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Material(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(Radii.md),
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

/// What an Apple Pencil double-tap or squeeze does.
class _PencilGestureTile extends ConsumerWidget {
  const _PencilGestureTile({required this.gesture});

  final PencilGesture gesture;

  static String label(PencilAction action) => switch (action) {
    PencilAction.system => 'As in iPad Settings',
    PencilAction.switchEraser => 'Eraser and back',
    PencilAction.switchPrevious => 'Previous tool',
    PencilAction.showColors => 'Colors and pen options',
    PencilAction.off => 'Nothing',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(pencilActionProvider(gesture));
    // The current choice on the right, as a menu, like iOS Settings.
    return ListTile(
      leading: const SizedBox(width: 24),
      title: Text(
        gesture == PencilGesture.tap
            ? 'Pencil double-tap'
            : 'Pencil squeeze (Apple Pencil Pro)',
      ),
      trailing: PopupMenuButton<PencilAction>(
        tooltip: 'Change',
        initialValue: action,
        onSelected: ref.read(pencilActionProvider(gesture).notifier).set,
        itemBuilder: (context) => [
          for (final a in PencilAction.values)
            PopupMenuItem(value: a, child: Text(label(a))),
        ],
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label(action),
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
            Icon(
              Icons.unfold_more,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
