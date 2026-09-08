import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:zeta/src/app/router/pages/agent_conversation_route_page.dart';
import 'package:zeta/src/app/router/pages/draft_conversation_route_page.dart';
import 'package:zeta/src/app/router/pages/global_home_route_page.dart';
import 'package:zeta/src/app/router/pages/project_home_route_page.dart';
import 'package:zeta/src/ui/features/ide/views/ide_home.dart';

/// `state.pageKey` 按路由模式复用 Page；参数变化靠 child [Key] 换页，避免同模式
/// 多 Page 叠在壳 Navigator 里。
NoTransitionPage<void> _shellPage(GoRouterState state, Widget child) {
  return NoTransitionPage<void>(key: state.pageKey, child: child);
}

/// 声明式路由表。内容路由在 [IdeHome] 壳内直渲；设置页仍为占位（W5 压栈）。
List<RouteBase> buildAppRoutes({
  required GlobalKey<NavigatorState> rootNavigatorKey,
  required GlobalKey<NavigatorState> shellNavigatorKey,
}) {
  return <RouteBase>[
    ShellRoute(
      navigatorKey: shellNavigatorKey,
      builder: (context, state, child) =>
          IdeHome(key: const ValueKey<String>('zeta.ide-home'), child: child),
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          pageBuilder: (context, state) =>
              _shellPage(state, const GlobalHomeRoutePage()),
        ),
        GoRoute(
          path: '/project/:projectId',
          pageBuilder: (context, state) {
            final projectId = state.pathParameters['projectId'] ?? '';
            return _shellPage(
              state,
              ProjectHomeRoutePage(
                key: ValueKey<String>('project-home-$projectId'),
                projectId: projectId,
              ),
            );
          },
        ),
        GoRoute(
          path: '/project/:projectId/draft/:providerId',
          pageBuilder: (context, state) {
            final projectId = state.pathParameters['projectId'] ?? '';
            final providerId = state.pathParameters['providerId'] ?? '';
            return _shellPage(
              state,
              DraftConversationRoutePage(
                key: ValueKey<String>('draft-$projectId-$providerId'),
                projectId: projectId,
                providerId: providerId,
              ),
            );
          },
        ),
        GoRoute(
          path: '/project/:projectId/thread/:threadId',
          pageBuilder: (context, state) {
            final projectId = state.pathParameters['projectId'] ?? '';
            final threadId = state.pathParameters['threadId'] ?? '';
            return _shellPage(
              state,
              AgentConversationRoutePage(
                key: ValueKey<String>('thread-$projectId-$threadId'),
                projectId: projectId,
                threadId: threadId,
              ),
            );
          },
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
        child: const SizedBox.shrink(),
      ),
    ),
  ];
}
