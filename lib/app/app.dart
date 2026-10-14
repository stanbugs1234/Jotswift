import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/skins/skin_providers.dart';
import 'router.dart';

class MotleyApp extends ConsumerWidget {
  const MotleyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Motley',
      debugShowCheckedModeBanner: false,
      theme: ref.watch(themeProvider),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
