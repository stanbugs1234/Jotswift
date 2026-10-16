import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart' show titleSerif;

/// The title of a main tab (Notebooks, Planner, Calendar, To-do), in the
/// app bar: the serif, at the start. Every tab names itself the same way.
///
/// Use it with `centerTitle: false`; screens opened from a tab keep the
/// usual centered title.
class TabTitle extends ConsumerWidget {
  const TabTitle(this.text, {super.key, this.textKey});

  final String text;

  /// A key for the [Text] itself, for tests that read it.
  final Key? textKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Text(
    text,
    key: textKey,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    // A step smaller on phones, where the bar also holds several buttons.
    style: titleSerif(
      ref,
      MediaQuery.sizeOf(context).width < 600
          ? Theme.of(context).textTheme.titleLarge
          : Theme.of(context).textTheme.headlineSmall,
    ),
  );
}
