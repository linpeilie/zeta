import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/features/ide_session/domain/recent_project_summary.dart';
import 'package:zeta/src/ui/features/ide/views/global_home_page.dart';

import '../../../core/ide_component_test_harness.dart';

void main() {
  testWidgets('renders five recent items and dispatches homepage actions', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 21, 15);
    final projects = _projects(now, count: 6);
    final threads = _threads(now, projects: projects, count: 6);
    var openProjectCount = 0;
    String? selectedProject;
    AgentThreadSummary? selectedThread;

    await pumpIdeComponent(
      tester,
      size: const Size(1100, 900),
      child: GlobalHomePage(
        recentProjects: projects,
        recentThreads: threads,
        installedProviders: const <HomeProviderSummary>[
          HomeProviderSummary(
            id: defaultAgentProviderId,
            displayName: 'Codex CLI',
            vendor: 'OpenAI',
            version: '0.42.0',
            status: HomeProviderStatus.available,
          ),
          HomeProviderSummary(
            id: grokAgentProviderId,
            displayName: 'Grok CLI',
            vendor: 'xAI',
            status: HomeProviderStatus.needsLogin,
          ),
        ],
        now: now,
        onOpenProject: () {
          openProjectCount += 1;
        },
        onSelectProject: (path) {
          selectedProject = path;
        },
        onSelectThread: (thread) {
          selectedThread = thread;
        },
      ),
    );

    expect(find.text('欢迎使用 Zeta'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('global-home-project-/workspace/p0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('global-home-project-/workspace/p5')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('global-home-thread-codex-thread-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('global-home-thread-grok-thread-5')),
      findsNothing,
    );
    expect(find.text('Codex CLI'), findsOneWidget);
    expect(find.text('需登录'), findsOneWidget);

    final projectsTopLeft = tester.getTopLeft(
      find.byKey(const ValueKey<String>('global-home-projects-section')),
    );
    final threadsTopLeft = tester.getTopLeft(
      find.byKey(const ValueKey<String>('global-home-threads-section')),
    );
    expect(threadsTopLeft.dx, greaterThan(projectsTopLeft.dx));
    expect(threadsTopLeft.dy, closeTo(projectsTopLeft.dy, 0.5));

    await tester.tap(
      find.byKey(const ValueKey<String>('global-home-open-project')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('global-home-project-/workspace/p0')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('global-home-thread-codex-thread-0')),
    );
    await tester.pump();

    expect(openProjectCount, 1);
    expect(selectedProject, '/workspace/p0');
    expect(selectedThread?.id, 'thread-0');
    expect(tester.takeException(), isNull);
  });

  testWidgets('stacks sections in a narrow large-text viewport', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 21, 15);
    final projects = <RecentProjectSummary>[
      RecentProjectSummary(
        path:
            '/workspace/a-project-with-an-extremely-long-name-that-must-truncate',
        lastOpenedAt: now,
      ),
    ];

    await pumpIdeComponent(
      tester,
      size: const Size(520, 760),
      child: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: GlobalHomePage(
          recentProjects: projects,
          recentThreads: _threads(now, projects: projects, count: 1),
          installedProviders: const <HomeProviderSummary>[
            HomeProviderSummary(
              id: defaultAgentProviderId,
              displayName: 'Codex CLI With A Very Long Display Name',
              vendor: 'OpenAI',
              version: '0.42.0',
              status: HomeProviderStatus.updateAvailable,
            ),
          ],
          now: now,
          onOpenProject: () {},
          onSelectProject: (_) {},
          onSelectThread: (_) {},
        ),
      ),
    );

    final projectsTopLeft = tester.getTopLeft(
      find.byKey(const ValueKey<String>('global-home-projects-section')),
    );
    final threadsTopLeft = tester.getTopLeft(
      find.byKey(const ValueKey<String>('global-home-threads-section')),
    );
    expect(threadsTopLeft.dy, greaterThan(projectsTopLeft.dy));
    expect(threadsTopLeft.dx, closeTo(projectsTopLeft.dx, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows loading and non-blocking failure states', (tester) async {
    await pumpIdeComponent(
      tester,
      size: const Size(700, 760),
      child: GlobalHomePage(
        recentProjects: const <RecentProjectSummary>[],
        recentThreads: const <AgentThreadSummary>[],
        installedProviders: const <HomeProviderSummary>[],
        isLoadingRecentProjects: true,
        isLoadingRecentThreads: true,
        isLoadingProviders: true,
        onOpenProject: () {},
        onSelectProject: (_) {},
        onSelectThread: (_) {},
      ),
    );

    expect(find.text('正在读取近期项目…'), findsOneWidget);
    expect(find.text('正在加载近期会话…'), findsOneWidget);
    expect(find.text('正在检测 Provider…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps cached rows while reporting refresh failures', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 21, 15);
    final projects = _projects(now, count: 1);
    await pumpIdeComponent(
      tester,
      size: const Size(900, 760),
      child: GlobalHomePage(
        recentProjects: projects,
        recentThreads: _threads(now, projects: projects, count: 1),
        installedProviders: const <HomeProviderSummary>[
          HomeProviderSummary(
            id: defaultAgentProviderId,
            displayName: 'Codex CLI',
            vendor: 'OpenAI',
            status: HomeProviderStatus.available,
          ),
        ],
        recentThreadsError: 'thread refresh failed',
        providerError: 'provider refresh failed',
        now: now,
        onOpenProject: () {},
        onSelectProject: (_) {},
        onSelectThread: (_) {},
      ),
    );

    expect(find.text('Thread 0'), findsOneWidget);
    expect(find.text('Codex CLI'), findsOneWidget);
    expect(find.text('刷新失败'), findsOneWidget);
    expect(find.text('检测失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('maps managed Agent state to homepage Provider status', () {
    final installed = ManagedAgent.forDefinition(
      definition: AgentDefinition.codex,
      enabled: true,
    ).copyWith(installationState: AgentInstallationState.installed);

    expect(
      HomeProviderSummary.fromManagedAgent(
        installed.copyWith(runtimeState: AgentRuntimeState.running),
      ).status,
      HomeProviderStatus.running,
    );
    expect(
      HomeProviderSummary.fromManagedAgent(
        installed.copyWith(runtimeState: AgentRuntimeState.disabled),
      ).status,
      HomeProviderStatus.disabled,
    );
    expect(
      HomeProviderSummary.fromManagedAgent(
        installed.copyWith(accountState: AgentAccountState.loggedOut),
      ).status,
      HomeProviderStatus.needsLogin,
    );
    expect(
      HomeProviderSummary.fromManagedAgent(
        installed.copyWith(runtimeState: AgentRuntimeState.error),
      ).status,
      HomeProviderStatus.error,
    );
    expect(
      HomeProviderSummary.fromManagedAgent(
        installed.copyWith(versionState: AgentVersionState.updateAvailable),
      ).status,
      HomeProviderStatus.updateAvailable,
    );
  });
}

List<RecentProjectSummary> _projects(DateTime now, {required int count}) {
  return <RecentProjectSummary>[
    for (var index = 0; index < count; index += 1)
      RecentProjectSummary(
        path: '/workspace/p$index',
        lastOpenedAt: now.subtract(Duration(hours: index)),
      ),
  ];
}

List<AgentThreadSummary> _threads(
  DateTime now, {
  required List<RecentProjectSummary> projects,
  required int count,
}) {
  return <AgentThreadSummary>[
    for (var index = 0; index < count; index += 1)
      AgentThreadSummary(
        id: 'thread-$index',
        providerId: index.isEven ? defaultAgentProviderId : grokAgentProviderId,
        projectPath: projects[index % projects.length].path,
        title: 'Thread $index',
        preview: 'Preview $index',
        createdAt: now.subtract(Duration(days: index + 1)),
        updatedAt: now.subtract(Duration(hours: index + 1)),
        recencyAt: now.subtract(Duration(hours: index + 1)),
        status: AgentThreadRuntimeStatus.idle,
      ),
  ];
}
