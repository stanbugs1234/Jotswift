import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/motion/page_turn.dart';

/// Lets the page turn style be chosen, showing it on two small pages.
Future<void> showPageTurnPicker(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => const PageTurnPicker(),
    );

class PageTurnPicker extends ConsumerStatefulWidget {
  const PageTurnPicker({super.key});

  @override
  ConsumerState<PageTurnPicker> createState() => _PageTurnPickerState();
}

class _PageTurnPickerState extends ConsumerState<PageTurnPicker> {
  static const _pages = [1, 2, 3];
  var _page = 1;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _next());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// On through the pages, then back to the first: both directions show.
  void _next() {
    if (mounted) setState(() => _page = _page == 3 ? 1 : _page + 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = ref.watch(pageTurnStyleProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Page turn style', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'How notebook pages change. You can also drag a page over '
              "from the screen's edge.",
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  height: 156,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: PageTurnSwitcher(
                      pageKey: _page,
                      order: _pages,
                      style: style,
                      child: _MiniPage(number: _page),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in PageTurnStyle.values)
                        ChoiceChip(
                          label: Text(s.label),
                          selected: s == style,
                          onSelected: (_) {
                            ref.read(pageTurnStyleProvider.notifier).set(s);
                            _next();
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A tiny lined page with a number, for the preview.
class _MiniPage extends StatelessWidget {
  const _MiniPage({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = [
      scheme.primary,
      scheme.tertiary,
      scheme.secondary,
    ][(number - 1) % 3];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$number',
              style: TextStyle(
                color: accent,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < 7; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: FractionallySizedBox(
                  widthFactor: i.isEven ? 1 : 0.75,
                  child: Container(
                    height: 2,
                    color: accent.withValues(alpha: 0.35),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
