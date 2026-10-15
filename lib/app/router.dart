import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_repository.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/calendar/calendar_screen.dart';
import '../features/notebooks/notebook_screen.dart';
import '../features/notebooks/page_screen.dart';
import '../features/planner/planner_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shelf/shelf_screen.dart';
import '../features/shelf/shelf_view.dart';
import '../features/skins/notebook_style_screen.dart';
import '../features/store/store_item_screen.dart';
import '../features/tasks/todo_screen.dart';
import '../features/store/store_screen.dart';
import 'shell.dart';

const signInPath = '/sign-in';
const homePath = '/notebooks';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Where to go after signing in: [from] if it's a path in this app,
/// otherwise the shelf.
String _safeReturn(String? from) =>
    from != null &&
        from.startsWith('/') &&
        !from.startsWith('//') &&
        !from.startsWith(signInPath)
    ? from
    : homePath;

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
      if (!signedIn) {
        if (onSignIn) return null;
        // Come back here after signing in (a link, or a refresh on the
        // web before the saved session is restored).
        final from = state.uri.toString();
        return from == homePath
            ? signInPath
            : Uri(path: signInPath, queryParameters: {'from': from}).toString();
      }
      if (onSignIn) return _safeReturn(state.uri.queryParameters['from']);
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
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: plannerPath,
                builder: (context, state) => const PlannerScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/calendar',
                builder: (context, state) => const CalendarScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/todo',
                builder: (context, state) => const TodoScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: storePath,
        builder: (context, state) => const StoreScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (context, state) =>
                StoreItemScreen(itemId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: 'style',
            builder: (context, state) => const NotebookStyleScreen(),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
