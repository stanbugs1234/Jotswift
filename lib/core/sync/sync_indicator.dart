import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_status.dart';

String syncMessage(SyncStatus s) => switch (s) {
  SyncStatus.saved => 'All changes saved',
  SyncStatus.saving => 'Saving changes…',
  SyncStatus.offline => 'Offline',
  SyncStatus.offlineWithChanges =>
    'Offline. Your changes are kept on this device and will be saved '
        'when you\'re back online.',
};

/// A small cloud that shows whether changes are saved to the account.
class SyncIndicator extends ConsumerWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider).value ?? SyncStatus.saved;
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (status) {
      SyncStatus.saved => (
        Icons.cloud_done_outlined,
        scheme.onSurface.withValues(alpha: 0.45),
      ),
      SyncStatus.saving => (Icons.cloud_upload_outlined, scheme.primary),
      SyncStatus.offline => (Icons.cloud_off_outlined, scheme.onSurface),
      SyncStatus.offlineWithChanges => (Icons.cloud_off, scheme.error),
    };
    final message = syncMessage(status);
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      child: Semantics(
        label: message,
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(icon, size: 22, color: color),
        ),
      ),
    );
  }
}

/// Shows [child] with a strip across the top while there's no connection.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider).value;
    final showing = status != null && status.isOffline;
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSecondaryContainer;
    return Column(
      children: [
        if (showing)
          Material(
            color: theme.colorScheme.secondaryContainer,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off_outlined, size: 18, color: ink),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        status == SyncStatus.offlineWithChanges
                            ? syncMessage(status)
                            : 'You\'re offline. Changes you make are kept on '
                                  'this device until you reconnect.',
                        style: theme.textTheme.bodySmall?.copyWith(color: ink),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          // Keyed so the screens below keep their state as the strip comes
          // and goes.
          key: const ValueKey('content'),
          // The strip already clears the status bar.
          child: MediaQuery.removePadding(
            context: context,
            removeTop: showing,
            child: child,
          ),
        ),
      ],
    );
  }
}
