import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/motion/motion.dart';
import '../core/settings/appearance.dart';
import '../core/skins/skin_providers.dart';
import '../features/imports/open_in.dart';
import 'router.dart';

class NotelyApp extends ConsumerWidget {
  const NotelyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(openInListenerProvider);
    final animations = ref.watch(animationLevelProvider);
    return MaterialApp.router(
      title: 'Jotswift',
      debugShowCheckedModeBanner: false,
      theme: ref.watch(lightThemeProvider),
      darkTheme: ref.watch(darkThemeProvider),
      themeMode: ref.watch(themeModeProvider),
      // Light/dark and style changes crossfade.
      themeAnimationDuration: animations == AnimationLevel.off
          ? Duration.zero
          : MotionTokens.standard,
      themeAnimationCurve: MotionTokens.move,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) {
        // On tablets, messages are a card no wider than a phone, centered,
        // rather than stretching across the screen.
        final width = MediaQuery.sizeOf(context).width;
        final theme = Theme.of(context);
        return Theme(
          data: width < 600
              ? theme
              : theme.copyWith(
                  snackBarTheme: theme.snackBarTheme.copyWith(width: 440),
                ),
          child: MotionScope(child: child!),
        );
      },
    );
  }
}
