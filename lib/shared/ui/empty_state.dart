import 'package:flutter/material.dart';

import 'tokens.dart';

/// What a screen or section shows when there's nothing in it: an icon,
/// a title, a line saying what goes here, and what to do about it.
///
/// [compact] is for a section within a screen (a day's events, a list):
/// a smaller icon beside the text instead of above it.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.compact = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? message;

  /// A button that fills the space, if there's an obvious next step.
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Insets.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: muted),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                  if (message case final m?) ...[
                    const SizedBox(height: 2),
                    Text(
                      m,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                  if (action case final a?) ...[
                    const SizedBox(height: Insets.sm),
                    a,
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Insets.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 40, color: scheme.primary),
              ),
              const SizedBox(height: Insets.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              if (message case final m?) ...[
                const SizedBox(height: Insets.sm),
                Text(
                  m,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ],
              if (action case final a?) ...[
                const SizedBox(height: Insets.xl),
                a,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
