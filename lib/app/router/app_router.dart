import 'package:agent_management_repository/agent_management_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:project_session_repository/project_session_repository.dart';
import 'package:workspace_repository/workspace_repository.dart';
import 'package:zeta/agent_chat/agent_chat.dart';
import 'package:zeta/agent_management/agent_management.dart';
import 'package:zeta/ide_session/ide_session.dart';
import 'package:zeta/ide_shell/ide_shell.dart';
import 'package:zeta/settings/settings.dart';
import 'package:zeta/usage_statistics/usage_statistics.dart';

part 'app_router.g.dart';

@TypedShellRoute<IdeShellRoute>(
  routes: <TypedRoute<RouteData>>[
    TypedGoRoute<HomeRoute>(
      name: 'home',
      path: '/home',
    ),
    TypedGoRoute<ProjectRoute>(
      name: 'project',
      path: '/projects/:projectId',
      routes: <TypedRoute<RouteData>>[
        TypedGoRoute<ThreadRoute>(
          name: 'thread',
          path: 'threads/:threadId',
        ),
      ],
    ),
    TypedGoRoute<SettingsRoute>(
      name: 'settings',
      path: '/settings',
      routes: <TypedRoute<RouteData>>[
        TypedGoRoute<AgentManagementRoute>(
          name: 'agents',
          path: 'agents',
          routes: <TypedRoute<RouteData>>[
            TypedGoRoute<AgentManagementAgentRoute>(
              name: 'agent',
              path: ':agentId',
            ),
          ],
        ),
      ],
    ),
    TypedGoRoute<UsageStatisticsRoute>(
      name: 'usage-statistics',
      path: '/usage-statistics',
    ),
  ],
)
class IdeShellRoute extends ShellRouteData {
  const IdeShellRoute();

  @override
  Widget builder(
    BuildContext context,
    GoRouterState state,
    Widget navigator,
  ) {
    return IdeShellPage(child: navigator);
  }
}

class HomeRoute extends GoRouteData with $HomeRoute {
  const HomeRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const IdeHomePage();
  }
}

class ProjectRoute extends GoRouteData with $ProjectRoute {
  const ProjectRoute({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return IdeProjectPage(projectId: projectId);
  }
}

class ThreadRoute extends GoRouteData with $ThreadRoute {
  const ThreadRoute({
    required this.projectId,
    required this.threadId,
  });

  final String projectId;
  final String threadId;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    final path = context.read<WorkspaceRepository>().resolveProjectPath(
      projectId,
    );
    final providerId = context
        .read<ProjectSessionRepository>()
        .snapshot
        ?.activeAgentProviderId;
    return AgentConversationPage(
      providerId: providerId ?? '',
      threadId: threadId,
      projectPath: path,
    );
  }
}

class SettingsRoute extends GoRouteData with $SettingsRoute {
  const SettingsRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const SettingsPage();
  }
}

class AgentManagementRoute extends GoRouteData with $AgentManagementRoute {
  const AgentManagementRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const AgentManagementPage();
  }
}

class AgentManagementAgentRoute extends GoRouteData
    with $AgentManagementAgentRoute {
  const AgentManagementAgentRoute({required this.agentId});

  final String agentId;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return AgentManagementPage(providerId: agentId);
  }
}

class UsageStatisticsRoute extends GoRouteData with $UsageStatisticsRoute {
  const UsageStatisticsRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const UsageStatisticsPage();
  }
}

GoRouter createIdeRouter({
  required String initialLocation,
  Listenable? refreshListenable,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: refreshListenable,
    redirect: ideRouterRedirect,
    routes: $appRoutes,
  );
}

String locationFromSession({
  required IdeSessionInitialRoute route,
  required WorkspaceRepository workspaceRepository,
}) {
  final projectPath = route.projectPath?.trim();
  if (projectPath == null || projectPath.isEmpty) {
    return const HomeRoute().location;
  }
  final projectId = workspaceRepository.projectIdFor(projectPath);
  final threadId = route.threadId?.trim();
  if (threadId != null && threadId.isNotEmpty && !route.projectHomeActive) {
    return ThreadRoute(
      projectId: projectId,
      threadId: threadId,
    ).location;
  }
  return ProjectRoute(projectId: projectId).location;
}

Future<String?> ideRouterRedirect(
  BuildContext context,
  GoRouterState state,
) async {
  final workspace = context.read<WorkspaceRepository>();
  final sessions = context.read<ProjectSessionRepository>();
  final management = context.read<AgentManagementRepository>();
  final projectId = state.pathParameters['projectId'];
  if (projectId != null) {
    final path = workspace.resolveProjectPath(projectId);
    if (path == null) {
      return const HomeRoute().location;
    }
    try {
      await workspace.loadChildren(
        rootPath: path,
        directoryPath: path,
      );
    } on WorkspaceRepositoryException catch (error) {
      if (error.failure.code == WorkspaceRepositoryFailureCode.notFound) {
        return const HomeRoute().location;
      }
      rethrow;
    }
    final threadId = state.pathParameters['threadId'];
    if (threadId != null && !_threadKnown(sessions.snapshot, path, threadId)) {
      return ProjectRoute(projectId: projectId).location;
    }
    if (threadId != null &&
        (sessions.snapshot?.activeAgentProviderId == null ||
            sessions.snapshot!.activeAgentProviderId!.trim().isEmpty)) {
      return ProjectRoute(projectId: projectId).location;
    }
  }
  final agentId = state.pathParameters['agentId'];
  if (agentId != null) {
    final known = management.definitions.any(
      (definition) => definition.providerId == agentId,
    );
    if (!known) {
      return const AgentManagementRoute().location;
    }
  }
  return null;
}

bool _threadKnown(
  ProjectSessionSnapshot? snapshot,
  String projectPath,
  String threadId,
) {
  if (snapshot == null) {
    return false;
  }
  if (snapshot.selectedThreadIdsByProject[projectPath] == threadId) {
    return true;
  }
  if (snapshot.agentThreadIdsByProject[projectPath] == threadId) {
    return true;
  }
  final cached = snapshot.cachedThreadsByProject[projectPath];
  return cached != null && cached.any((thread) => thread.id == threadId);
}
