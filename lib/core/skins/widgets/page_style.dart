import 'package:flutter/material.dart';

import '../notely_skin.dart';

/// Draws the pages inside [child] in [style] (paper, ink palette and accent
/// font), while buttons, bars and menus keep the app's own theme.
class PageStyle extends StatelessWidget {
  const PageStyle({required this.style, required this.child, super.key});

  final NotelySkin style;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        extensions: [
          ...theme.extensions.values.where((e) => e is! NotelySkin),
          style,
        ],
      ),
      child: child,
    );
  }
}
