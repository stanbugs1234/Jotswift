import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/motion/motion.dart';
import '../core/settings/appearance.dart';
import '../core/skins/skin_providers.dart';
import 'router.dart';

class NotelyApp extends ConsumerWidget {
  const NotelyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      builder: (context, child) => MotionScope(child: child!),
    );
  }
}
