import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_repository.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/home/placeholder_screen.dart';
import '../features/notebooks/notebook_screen.dart';
import '../features/notebooks/page_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shelf/shelf_screen.dart';
import '../features/shelf/shelf_view.dart';
import '../features/skins/sample_pages.dart';
import '../features/skins/skin_detail_screen.dart';
import '../features/skins/skin_picker_screen.dart';
import 'shell.dart';

const signInPath = '/sign-in';
const homePath = '/notebooks';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run the redirect whenever the user signs in or out.
  final authChanged = ValueNotifier(0);
  ref
    ..listen(authStateProvider, (_, _) => authChanged.value++)
    ..onDispose(authChanged.dispose);

  final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: homePath,
    refreshListenable: authChanged,
    redirect: (context, state) {
      final signedIn = ref.read(authRepositoryProvider).currentUser != null;
      final onSignIn = state.matchedLocation == signInPath;
      if (!signedIn) return onSignIn ? null : signInPath;
      if (onSignIn) return homePath;
      return null;
    },
    routes: [
      GoRoute(
        path: signInPath,
        builder: (context, state) => const SignInScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) =>
            AppShell(navigationShell: shell, uri: state.uri),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/notebooks',
                builder: (context, state) => ShelfScreen(
                  location: ShelfLocation.fromQuery(state.uri.queryParameters),
                ),
                routes: [
                  GoRoute(
                    path: ':notebookId',
                    builder: (context, state) => NotebookScreen(
                      notebookId: state.pathParameters['notebookId']!,
                    ),
                    routes: [
                      // Full screen (above the tab bar) to give ink room.
                      GoRoute(
                        path: 'pages/:pageId',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (context, state) =>
                            PageScreen(pageId: state.pathParameters['pageId']!),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          _tab('/planner', 'Planner', SamplePageKind.planner, 'Phase 3'),
          _tab('/calendar', 'Calendar', SamplePageKind.calendar, 'Phase 3'),
          _tab('/todo', 'To-do', SamplePageKind.todo, 'Phase 3'),
        ],
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: 'skins',
            builder: (context, state) => const SkinPickerScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    SkinDetailScreen(skinId: state.pathParameters['id']!),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

StatefulShellBranch _tab(
  String path,
  String title,
  SamplePageKind kind,
  String comingIn,
) {
  return StatefulShellBranch(
    routes: [
      GoRoute(
        path: path,
        builder: (context, state) =>
            PlaceholderScreen(title: title, kind: kind, comingIn: comingIn),
      ),
    ],
  );
}
