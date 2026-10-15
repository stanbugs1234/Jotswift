import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/entitlements/entitlements.dart';
import '../../core/purchases/purchases_providers.dart';
import '../../core/input/finger_drawing.dart';
import '../../core/motion/motion.dart';
import '../../core/settings/appearance.dart';
import '../../core/skins/skin_providers.dart';
import '../auth/auth_repository.dart';
import '../calendar/calendar_providers.dart' show monthAnimationProvider;
import '../calendar/templates/calendar_look.dart' show calendarTemplateProvider;
import '../calendar/templates/calendar_templates_screen.dart';
import '../skins/notebook_style_screen.dart';
import '../store/paywall.dart';
import '../store/store_actions.dart';
import '../store/store_screen.dart';

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

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(user?.displayName ?? user?.email ?? 'Signed in'),
            subtitle: const Text('Account'),
          ),
          const ListTile(
            leading: Icon(Icons.contrast),
            title: Text('Appearance'),
            subtitle: Text('Pages keep their own paper in light and dark.'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('System')),
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
              ],
              selected: {ref.watch(themeModeProvider)},
              onSelectionChanged: (s) =>
                  ref.read(appearanceProvider.notifier).set(s.first),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.draw_outlined),
            title: const Text('Apple Pencil & touch'),
            subtitle: Text(switch (ref.watch(fingerDrawingProvider)) {
              FingerDrawing.device =>
                ref.watch(devicePencilProvider).pencilOnly
                    ? 'Fingers scroll and zoom: your iPad is set to Only '
                          'Draw with Apple Pencil.'
                    : ref.watch(fingersDrawProvider)
                    ? 'Fingers draw, following this device.'
                    : 'Fingers scroll and zoom, since you use a stylus.',
              FingerDrawing.on => 'Fingers draw on pages.',
              FingerDrawing.off =>
                'Fingers scroll and zoom; only the pen draws.',
            }),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
            child: SegmentedButton<FingerDrawing>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: FingerDrawing.device,
                  label: Text('Follow device'),
                ),
                ButtonSegment(
                  value: FingerDrawing.on,
                  label: Text('Finger draws'),
                ),
                ButtonSegment(
                  value: FingerDrawing.off,
                  label: Text('Pen only'),
                ),
              ],
              selected: {ref.watch(fingerDrawingProvider)},
              onSelectionChanged: (s) =>
                  ref.read(fingerDrawingProvider.notifier).set(s.first),
            ),
          ),
          const ListTile(
            leading: Icon(Icons.animation),
            title: Text('Animations'),
            subtitle: Text(
              'Page turns, opening notebooks and other motion. '
              "Your device's Reduce Motion setting also tones them down.",
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
            child: SegmentedButton<AnimationLevel>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: AnimationLevel.full, label: Text('Full')),
                ButtonSegment(
                  value: AnimationLevel.reduced,
                  label: Text('Reduced'),
                ),
                ButtonSegment(value: AnimationLevel.off, label: Text('Off')),
              ],
              selected: {ref.watch(animationLevelProvider)},
              onSelectionChanged: (s) =>
                  ref.read(animationLevelProvider.notifier).set(s.first),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: const Text('Calendar template & animation'),
            subtitle: Text(
              '${ref.watch(calendarTemplateProvider).name} · '
              '${ref.watch(monthAnimationProvider).label}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showCalendarTemplates(context),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Notebook style'),
            subtitle: Text(skin.name),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(notebookStylePath),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('Jotswift Pro'),
            subtitle: Text(
              ref.watch(entitlementsProvider).pro
                  ? 'You have Pro'
                  : 'Unlimited notebooks and everything marked Pro',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showPaywall(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: const Text('Templates'),
            subtitle: const Text('Planners, covers, papers and stickers'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(storePath),
          ),
          if (ref.watch(purchasesClientProvider).isAvailable)
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Restore purchases'),
              onTap: () => restorePurchases(context, ref),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () => ref.read(authRepositoryProvider).signOut(),
          ),
          ListTile(
            leading: Icon(
              Icons.delete_forever_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            title: const Text('Delete account'),
            onTap: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }
}
