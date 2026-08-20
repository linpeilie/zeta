// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_router.dart';

// **************************************************************************
// GoRouterGenerator
// **************************************************************************

List<RouteBase> get $appRoutes => [$ideShellRoute];

RouteBase get $ideShellRoute => ShellRouteData.$route(
  factory: $IdeShellRouteExtension._fromState,
  routes: [
    GoRouteData.$route(
      path: '/home',
      name: 'home',
      hasOverriddenOnExit: false,
      factory: $HomeRoute._fromState,
    ),
    GoRouteData.$route(
      path: '/projects/:projectId',
      name: 'project',
      hasOverriddenOnExit: false,
      factory: $ProjectRoute._fromState,
      routes: [
        GoRouteData.$route(
          path: 'threads/:threadId',
          name: 'thread',
          hasOverriddenOnExit: false,
          factory: $ThreadRoute._fromState,
        ),
      ],
    ),
    GoRouteData.$route(
      path: '/settings',
      name: 'settings',
      hasOverriddenOnExit: false,
      factory: $SettingsRoute._fromState,
      routes: [
        GoRouteData.$route(
          path: 'agents',
          name: 'agents',
          hasOverriddenOnExit: false,
          factory: $AgentManagementRoute._fromState,
          routes: [
            GoRouteData.$route(
              path: ':agentId',
              name: 'agent',
              hasOverriddenOnExit: false,
              factory: $AgentManagementAgentRoute._fromState,
            ),
          ],
        ),
      ],
    ),
    GoRouteData.$route(
      path: '/usage-statistics',
      name: 'usage-statistics',
      hasOverriddenOnExit: false,
      factory: $UsageStatisticsRoute._fromState,
    ),
  ],
);

extension $IdeShellRouteExtension on IdeShellRoute {
  static IdeShellRoute _fromState(GoRouterState state) => const IdeShellRoute();
}

mixin $HomeRoute on GoRouteData {
  static HomeRoute _fromState(GoRouterState state) => const HomeRoute();

  @override
  String get location => GoRouteData.$location('/home');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $ProjectRoute on GoRouteData {
  static ProjectRoute _fromState(GoRouterState state) =>
      ProjectRoute(projectId: state.pathParameters['projectId']!);

  ProjectRoute get _self => this as ProjectRoute;

  @override
  String get location => GoRouteData.$location(
    '/projects/${Uri.encodeComponent(_self.projectId)}',
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $ThreadRoute on GoRouteData {
  static ThreadRoute _fromState(GoRouterState state) => ThreadRoute(
    projectId: state.pathParameters['projectId']!,
    threadId: state.pathParameters['threadId']!,
  );

  ThreadRoute get _self => this as ThreadRoute;

  @override
  String get location => GoRouteData.$location(
    '/projects/${Uri.encodeComponent(_self.projectId)}/threads/${Uri.encodeComponent(_self.threadId)}',
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $SettingsRoute on GoRouteData {
  static SettingsRoute _fromState(GoRouterState state) => const SettingsRoute();

  @override
  String get location => GoRouteData.$location('/settings');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $AgentManagementRoute on GoRouteData {
  static AgentManagementRoute _fromState(GoRouterState state) =>
      const AgentManagementRoute();

  @override
  String get location => GoRouteData.$location('/settings/agents');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $AgentManagementAgentRoute on GoRouteData {
  static AgentManagementAgentRoute _fromState(GoRouterState state) =>
      AgentManagementAgentRoute(agentId: state.pathParameters['agentId']!);

  AgentManagementAgentRoute get _self => this as AgentManagementAgentRoute;

  @override
  String get location => GoRouteData.$location(
    '/settings/agents/${Uri.encodeComponent(_self.agentId)}',
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $UsageStatisticsRoute on GoRouteData {
  static UsageStatisticsRoute _fromState(GoRouterState state) =>
      const UsageStatisticsRoute();

  @override
  String get location => GoRouteData.$location('/usage-statistics');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}
