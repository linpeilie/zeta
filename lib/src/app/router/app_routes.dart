import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:zeta/src/app/router/pages/agent_conversation_route_page.dart';
import 'package:zeta/src/app/router/pages/draft_conversation_route_page.dart';
import 'package:zeta/src/app/router/pages/global_home_route_page.dart';
import 'package:zeta/src/app/router/pages/project_home_route_page.dart';
import 'package:zeta/src/app/router/pages/settings_route_page.dart';
import 'package:zeta/src/app/router/settings_route_intents.dart';
import 'package:zeta/src/features/settings/domain/settings_section.dart';
import 'package:zeta/src/features/settings/presentation/settings_can_leave.dart';
import 'package:zeta/src/ui/features/ide/views/ide_home.dart';

/// `state.pageKey` 按路由模式复用 Page；参数变化靠 child [Key] 换页，避免同模式
/// 多 Page 叠在壳 Navigator 里。
NoTransitionPage<void> _shellPage(GoRouterState state, Widget child) {
  return NoTransitionPage<void>(key: state.pageKey, child: child);
}

Widget _noPageTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) => child;

/// 设置页盖住壳，但必须 `opaque: false`：根 Navigator 遇到不透明 overlay 会把下层
/// `tickerEnabled` 关掉；`TickerMode(enabled: true)` 不能覆盖祖先（AND）。
CustomTransitionPage<void> _settingsCoveringPage(Widget child) {
  return CustomTransitionPage<void>(
    key: const ValueKey<String>('settings-page'),
    opaque: false,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: _noPageTransition,
    child: child,
  );
}

SettingsSection _settingsSectionOf(GoRouterState state) {
  final name = state.pathParameters['section'] ?? SettingsSection.general.name;
  return SettingsSection.values.asNameMap()[name] ?? SettingsSection.general;
}

Future<bool> _onExitSettings(BuildContext context, GoRouterState state) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final canLeave = container.read(settingsCanLeaveRegistryProvider).callback;
  final allowed = canLeave == null ? true : await canLeave();
  if (!allowed) {
    container.read(openUsageStatisticsAfterSettingsProvider.notifier).cancel();
  }
  return allowed;
}

/// 声明式路由表。内容路由在 [IdeHome] 壳内直渲；设置页压在根导航上。
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
      onExit: _onExitSettings,
      pageBuilder: (context, state) => _settingsCoveringPage(
        SettingsRoutePage(section: _settingsSectionOf(state)),
      ),
    ),
  ];
}
