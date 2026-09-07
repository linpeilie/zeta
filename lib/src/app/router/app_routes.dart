import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// 声明式路由表。本步中栏与设置页使用占位 widget，W4 替换为真实页面。
List<RouteBase> buildAppRoutes({
  required GlobalKey<NavigatorState> rootNavigatorKey,
  required GlobalKey<NavigatorState> shellNavigatorKey,
}) {
  return <RouteBase>[
    ShellRoute(
      navigatorKey: shellNavigatorKey,
      builder: (context, state, child) => child,
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => const NoTransitionPage<void>(
            child: _AppRoutePlaceholder(name: 'home'),
          ),
        ),
        GoRoute(
          path: '/project/:projectId',
          pageBuilder: (context, state) => NoTransitionPage<void>(
            child: _AppRoutePlaceholder(
              name: 'project:${state.pathParameters['projectId']}',
            ),
          ),
        ),
        GoRoute(
          path: '/project/:projectId/draft/:providerId',
          pageBuilder: (context, state) => NoTransitionPage<void>(
            child: _AppRoutePlaceholder(
              name:
                  'draft:${state.pathParameters['projectId']}:${state.pathParameters['providerId']}',
            ),
          ),
        ),
        GoRoute(
          path: '/project/:projectId/thread/:threadId',
          pageBuilder: (context, state) => NoTransitionPage<void>(
            child: _AppRoutePlaceholder(
              name:
                  'thread:${state.pathParameters['projectId']}:${state.pathParameters['threadId']}',
            ),
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/settings',
      redirect: (context, state) => '/settings/general',
    ),
    GoRoute(
      path: '/settings/:section',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (context, state) => NoTransitionPage<void>(
        key: const ValueKey<String>('settings-page'),
        child: _AppRoutePlaceholder(
          name: 'settings:${state.pathParameters['section']}',
        ),
      ),
    ),
  ];
}

final class _AppRoutePlaceholder extends StatelessWidget {
  const _AppRoutePlaceholder({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return SizedBox.shrink(key: ValueKey<String>('route-placeholder-$name'));
  }
}
