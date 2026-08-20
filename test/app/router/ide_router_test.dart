import 'dart:async';

import 'package:agent_conversation_repository/agent_conversation_repository.dart';
import 'package:agent_management_repository/agent_management_repository.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:agent_provider_repository/agent_provider_repository.dart';
import 'package:app_ui/app_ui.dart';
import 'package:desktop_notifications_repository/desktop_notifications_repository.dart';
import 'package:desktop_platform_repository/desktop_platform_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:project_session_repository/project_session_repository.dart';
import 'package:settings_repository/settings_repository.dart';
import 'package:usage_statistics_repository/usage_statistics_repository.dart';
import 'package:workspace_repository/workspace_repository.dart';
import 'package:zeta/agent_chat/agent_chat.dart';
import 'package:zeta/agent_management/agent_management.dart';
import 'package:zeta/app/app.dart';
import 'package:zeta/ide_session/ide_session.dart';
import 'package:zeta/ide_shell/ide_shell.dart';
import 'package:zeta/l10n/l10n.dart';
import 'package:zeta/settings/settings.dart';
import 'package:zeta/usage_statistics/usage_statistics.dart';

class _MockWorkspaceRepository extends Mock implements WorkspaceRepository {}

class _MockProjectSessionRepository extends Mock
    implements ProjectSessionRepository {}

class _MockDesktopPlatformRepository extends Mock
    implements DesktopPlatformRepository {}

class _MockSettingsRepository extends Mock implements SettingsRepository {}

class _MockAgentProviderRepository extends Mock
    implements AgentProviderRepository {}

class _MockAgentConversationRepository extends Mock
    implements AgentConversationRepository {}

class _MockAgentManagementRepository extends Mock
    implements AgentManagementRepository {}

class _MockDesktopNotificationsRepository extends Mock
    implements DesktopNotificationsRepository {}

class _MockUsageStatisticsRepository extends Mock
    implements UsageStatisticsRepository {}

class _MockConversationHandle extends Mock implements ConversationHandle {}

class _MockRuntimePort extends Mock implements AgentRuntimePort {}

class _MockConversationPort extends Mock implements AgentConversationPort {}

class _MockWindowCommands extends Mock implements DesktopWindowCommands {}

class _MockMenuCommands extends Mock implements DesktopMenuCommands {}

void main() {
  const projectPath = '/repo';
  const projectId = 'repo-id';
  const threadId = 'thread-1';
  final createdAt = DateTime.utc(2026, 1, 2);
  final thread = AgentThreadSummary(
    id: threadId,
    providerId: 'codex',
    projectPath: projectPath,
    preview: 'hello',
    createdAt: createdAt,
    updatedAt: createdAt,
    status: AgentThreadRuntimeStatus.idle,
  );
  final snapshot = ProjectSessionSnapshot(
    projectPaths: const <String>[projectPath],
    activeProjectPath: projectPath,
    activeAgentProviderId: 'codex',
    selectedThreadIdsByProject: const <String, String>{
      projectPath: threadId,
    },
    cachedThreadsByProject: <String, List<AgentThreadSummary>>{
      projectPath: <AgentThreadSummary>[thread],
    },
  );
  final file = WorkspaceNode(
    path: '/repo/lib/main.dart',
    name: 'main.dart',
    type: WorkspaceNodeType.file,
  );

  group('typed GoRouter', () {
    late WorkspaceRepository workspace;
    late ProjectSessionRepository sessions;
    late DesktopPlatformRepository desktop;
    late SettingsRepository settings;
    late AgentProviderRepository providers;
    late AgentConversationRepository conversations;
    late AgentManagementRepository management;
    late UsageStatisticsRepository usage;
    late DesktopNotificationsRepository notifications;
    late DesktopWindowCommands window;
    late DesktopMenuCommands menu;
    late StreamController<MenuCommand> commands;

    setUpAll(() {
      registerFallbackValue(ProjectSessionSnapshot());
      registerFallbackValue(ProjectThreadQuery(projectPath: projectPath));
      registerFallbackValue(
        UsageStatisticsQuery(
          startInclusive: DateTime.utc(2026, 8),
          endExclusive: DateTime.utc(2026, 8, 21),
        ),
      );
      registerFallbackValue(
        const ConversationKey.thread(
          providerId: 'codex',
          threadId: threadId,
        ),
      );
      registerFallbackValue(const AgentContext());
    });

    setUp(() {
      workspace = _MockWorkspaceRepository();
      sessions = _MockProjectSessionRepository();
      desktop = _MockDesktopPlatformRepository();
      settings = _MockSettingsRepository();
      providers = _MockAgentProviderRepository();
      conversations = _MockAgentConversationRepository();
      management = _MockAgentManagementRepository();
      usage = _MockUsageStatisticsRepository();
      notifications = _MockDesktopNotificationsRepository();
      window = _MockWindowCommands();
      menu = _MockMenuCommands();
      commands = StreamController<MenuCommand>.broadcast();
      when(() => workspace.projectIdFor(projectPath)).thenReturn(projectId);
      when(() => workspace.resolveProjectPath(any())).thenReturn(null);
      when(
        () => workspace.resolveProjectPath(projectId),
      ).thenReturn(projectPath);
      when(
        () => workspace.loadChildren(
          rootPath: any(named: 'rootPath'),
          directoryPath: any(named: 'directoryPath'),
        ),
      ).thenAnswer((_) async => const <WorkspaceNode>[]);
      when(
        () => workspace.indexChanges,
      ).thenAnswer((_) => const Stream<WorkspaceIndex>.empty());
      when(
        () => workspace.treeChanges,
      ).thenAnswer((_) => const Stream<WorkspaceTreeChange>.empty());
      when(() => workspace.index(any())).thenAnswer(
        (_) async => WorkspaceIndex(
          rootPath: projectPath,
          files: <WorkspaceNode>[file],
          visitedDirectories: 1,
          truncated: false,
          revision: 1,
        ),
      );
      when(() => sessions.snapshotChanges).thenAnswer(
        (_) => const Stream<ProjectSessionSnapshot?>.empty(),
      );
      when(() => sessions.snapshot).thenReturn(snapshot);
      when(() => sessions.restore()).thenAnswer((_) async => snapshot);
      when(() => sessions.save(any())).thenAnswer((_) async {});
      when(() => sessions.threadPage(any())).thenAnswer(
        (_) async => ProjectThreadPage(
          threads: <AgentThreadSummary>[thread],
          nextCursor: null,
        ),
      );
      when(() => desktop.windowCommands).thenReturn(window);
      when(() => desktop.menuCommands).thenReturn(menu);
      when(() => menu.commands).thenAnswer((_) => commands.stream);
      when(() => desktop.pickDirectory()).thenAnswer((_) async => projectPath);
      when(() => settings.ready).thenAnswer((_) async {});
      when(() => settings.settings).thenReturn(SettingsSnapshot.initial);
      when(
        () => settings.settingsChanges,
      ).thenAnswer((_) => const Stream<SettingsSnapshot>.empty());
      when(
        () => settings.fontFamilies(localeName: any(named: 'localeName')),
      ).thenAnswer((_) async => const <SettingsFontFamily>[]);
      when(
        () => settings.fontFamilies(
          localeName: any(named: 'localeName'),
          monospaceOnly: any(named: 'monospaceOnly'),
        ),
      ).thenAnswer((_) async => const <SettingsFontFamily>[]);
      when(() => management.definitions).thenReturn(AgentDefinition.all);
      when(() => management.readConfiguration(any())).thenAnswer((_) async {
        return AgentConfigurationDocument(
          path: '/cfg',
          format: 'toml',
          contents: '',
          maskedContents: '',
          exists: false,
          loadedAt: DateTime.utc(2026, 8, 20),
          signature: 'sig',
        );
      });
      when(
        () => management.discoverLogPaths(any()),
      ).thenAnswer((_) async => const <String>[]);
      when(
        () => management.validateConfiguration(
          format: any(named: 'format'),
          contents: any(named: 'contents'),
        ),
      ).thenReturn(AgentConfigurationValidation.valid);
      when(
        () => usage.report(
          any(),
          isCancelled: any(named: 'isCancelled'),
        ),
      ).thenAnswer(
        (invocation) async => UsageStatisticsReport(
          query: invocation.positionalArguments.first as UsageStatisticsQuery,
          records: const <UsageRecord>[],
          totals: const UsageTotals(
            calls: 0,
            failures: 0,
            inputTokens: 0,
            cachedInputTokens: 0,
            outputTokens: 0,
            reasoningTokens: 0,
            totalTokens: 0,
          ),
          warnings: const <UsageWarning>[],
          refreshedAt: DateTime.utc(2026, 8, 20),
        ),
      );
      final runtime = _MockRuntimePort();
      final bundle = AgentProviderBundle(
        runtime: runtime,
        conversation: _MockConversationPort(),
      );
      registerFallbackValue(bundle);
      when(() => runtime.config).thenReturn(AgentProviderConfig.defaultCodex);
      when(
        () => runtime.capabilities,
      ).thenReturn(AgentProviderCapabilities.unsupported);
      when(() => providers.bundleFor(any())).thenReturn(bundle);
      when(() => providers.configChanges).thenAnswer(
        (_) => const Stream<ProviderConfigSnapshot>.empty(),
      );
      final handle = _MockConversationHandle();
      when(
        () => conversations.openConversation(
          bundle: any(named: 'bundle'),
          key: any(named: 'key'),
          context: any(named: 'context'),
        ),
      ).thenAnswer((_) async => handle);
      when(() => conversations.snapshots(any())).thenAnswer(
        (_) => const Stream<ConversationSnapshot>.empty(),
      );
      when(() => conversations.snapshotOf(any())).thenReturn(null);
      when(handle.release).thenAnswer((_) async {});
      when(
        () => conversations.closeConversation(any()),
      ).thenAnswer((_) async {});
    });

    tearDown(() async {
      await commands.close();
    });

    AppRepositories repos() {
      return AppRepositories(
        workspaceRepository: workspace,
        projectSessionRepository: sessions,
        desktopPlatformRepository: desktop,
        settingsRepository: settings,
        agentProviderRepository: providers,
        agentConversationRepository: conversations,
        agentManagementRepository: management,
        usageStatisticsRepository: usage,
        desktopNotificationsRepository: notifications,
      );
    }

    AppDependencies dependencies() {
      final l10n = lookupAppLocalizations(const Locale('en'));
      return AppDependencies(
        locale: const Locale('en'),
        failureMessages: FailureMessages(l10n),
        desktopNotificationCopyResolver: DesktopNotificationCopyResolver(l10n),
      );
    }

    List<RepositoryProvider<dynamic>> providersForTree() {
      final bundle = repos();
      return <RepositoryProvider<dynamic>>[
        RepositoryProvider<WorkspaceRepository>.value(
          value: bundle.workspaceRepository,
        ),
        RepositoryProvider<ProjectSessionRepository>.value(
          value: bundle.projectSessionRepository,
        ),
        RepositoryProvider<DesktopPlatformRepository>.value(
          value: bundle.desktopPlatformRepository,
        ),
        RepositoryProvider<SettingsRepository>.value(
          value: bundle.settingsRepository,
        ),
        RepositoryProvider<AgentProviderRepository>.value(
          value: bundle.agentProviderRepository,
        ),
        RepositoryProvider<AgentConversationRepository>.value(
          value: bundle.agentConversationRepository,
        ),
        RepositoryProvider<AgentManagementRepository>.value(
          value: bundle.agentManagementRepository,
        ),
        RepositoryProvider<UsageStatisticsRepository>.value(
          value: bundle.usageStatisticsRepository,
        ),
        RepositoryProvider<AppDependencies>.value(value: dependencies()),
      ];
    }

    Future<GoRouter> pumpRouter(
      WidgetTester tester, {
      required String initialLocation,
    }) async {
      final router = createIdeRouter(initialLocation: initialLocation);
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: providersForTree(),
          child: MaterialApp.router(
            theme: AppTheme.light,
            builder: (context, child) {
              return Theme(
                data: AppTheme.light,
                child: child ?? const SizedBox.shrink(),
              );
            },
            localizationsDelegates: const [
              ZetaShadcnLocalizations.delegate,
              ...AppLocalizations.localizationsDelegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return router;
    }

    String locationOf(WidgetTester tester) {
      return GoRouterState.of(
        tester.element(find.byType(IdeShellView)),
      ).uri.path;
    }

    testWidgets('restores a project+thread session into the thread route', (
      tester,
    ) async {
      await tester.pumpWidget(
        App(dependencies: dependencies(), repositories: repos()),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(AgentConversationView), findsOneWidget);
      expect(locationOf(tester), contains('/threads/'));
    });

    testWidgets('restores a missing session to home', (tester) async {
      when(() => sessions.restore()).thenAnswer((_) async => null);
      when(() => sessions.snapshot).thenReturn(null);
      await tester.pumpWidget(
        App(dependencies: dependencies(), repositories: repos()),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(IdeHomePage), findsOneWidget);
      expect(locationOf(tester), '/home');
    });

    testWidgets('redirects an invalid project id to home', (tester) async {
      await pumpRouter(
        tester,
        initialLocation: const ProjectRoute(projectId: 'bad').location,
      );
      expect(find.byType(IdeHomePage), findsOneWidget);
      expect(locationOf(tester), '/home');
    });

    testWidgets('redirects a deleted project to home', (tester) async {
      when(
        () => workspace.loadChildren(
          rootPath: any(named: 'rootPath'),
          directoryPath: any(named: 'directoryPath'),
        ),
      ).thenThrow(
        WorkspaceRepositoryException(
          failure: const WorkspaceRepositoryFailure(
            operation: WorkspaceRepositoryOperation.loadChildren,
            code: WorkspaceRepositoryFailureCode.notFound,
            diagnosticCode: 'missing',
          ),
          cause: 'missing',
          stackTrace: StackTrace.current,
        ),
      );
      await pumpRouter(
        tester,
        initialLocation: const ProjectRoute(projectId: projectId).location,
      );
      expect(find.byType(IdeHomePage), findsOneWidget);
    });

    testWidgets('redirects a thread without a provider to the project', (
      tester,
    ) async {
      when(() => sessions.snapshot).thenReturn(
        ProjectSessionSnapshot(
          projectPaths: const <String>[projectPath],
          activeProjectPath: projectPath,
          selectedThreadIdsByProject: const <String, String>{
            projectPath: threadId,
          },
        ),
      );
      await pumpRouter(
        tester,
        initialLocation: const ThreadRoute(
          projectId: projectId,
          threadId: threadId,
        ).location,
      );
      expect(find.byType(IdeProjectPage), findsOneWidget);
    });

    testWidgets('redirects an unknown thread to the project route', (
      tester,
    ) async {
      when(() => sessions.snapshot).thenReturn(
        ProjectSessionSnapshot(
          projectPaths: const <String>[projectPath],
          activeProjectPath: projectPath,
          activeAgentProviderId: 'codex',
        ),
      );
      await pumpRouter(
        tester,
        initialLocation: const ThreadRoute(
          projectId: projectId,
          threadId: 'missing',
        ).location,
      );
      expect(find.byType(IdeProjectPage), findsOneWidget);
      expect(find.byType(AgentConversationView), findsNothing);
    });

    testWidgets('accepts a thread known only from the cached list', (
      tester,
    ) async {
      when(() => sessions.snapshot).thenReturn(
        ProjectSessionSnapshot(
          projectPaths: const <String>[projectPath],
          activeProjectPath: projectPath,
          activeAgentProviderId: 'codex',
          cachedThreadsByProject: <String, List<AgentThreadSummary>>{
            projectPath: <AgentThreadSummary>[thread],
          },
        ),
      );
      await pumpRouter(
        tester,
        initialLocation: const ThreadRoute(
          projectId: projectId,
          threadId: threadId,
        ).location,
      );
      expect(find.byType(AgentConversationView), findsOneWidget);
    });

    testWidgets('pops a thread back to its project parent', (tester) async {
      final router = await pumpRouter(
        tester,
        initialLocation: const ThreadRoute(
          projectId: projectId,
          threadId: threadId,
        ).location,
      );
      expect(find.byType(AgentConversationView), findsOneWidget);
      router.pop();
      await tester.pump();
      await tester.pump();
      expect(find.byType(IdeProjectPage), findsOneWidget);
    });

    testWidgets('navigates settings, agents, usage, and home from menus', (
      tester,
    ) async {
      await pumpRouter(
        tester,
        initialLocation: const HomeRoute().location,
      );
      await tester.tap(find.byKey(const Key('ide-shell-settings')));
      await tester.pump();
      await tester.pump();
      expect(find.byType(SettingsView), findsWidgets);
      expect(locationOf(tester), '/settings');
      await tester.tap(find.byKey(const Key('ide-shell-agents')));
      await tester.pump();
      await tester.pump();
      expect(find.byType(AgentManagementView), findsWidgets);
      expect(locationOf(tester), '/settings/agents');
      await tester.tap(find.byKey(const Key('ide-shell-usage')));
      await tester.pump();
      await tester.pump();
      expect(find.byType(UsageStatisticsView), findsWidgets);
      expect(locationOf(tester), '/usage-statistics');
      await tester.tap(find.byKey(const Key('ide-shell-home')));
      await tester.pump();
      await tester.pump();
      expect(locationOf(tester), '/home');
    });

    testWidgets('navigates to the project picked by the shell', (
      tester,
    ) async {
      await pumpRouter(
        tester,
        initialLocation: const HomeRoute().location,
      );

      await tester.tap(find.byKey(const Key('ide-home-open-project')));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(locationOf(tester), '/projects/$projectId');
      verify(() => workspace.projectIdFor(projectPath)).called(greaterThan(0));
    });

    testWidgets('opens a known agent route', (tester) async {
      await pumpRouter(
        tester,
        initialLocation: const AgentManagementAgentRoute(
          agentId: 'codex',
        ).location,
      );
      expect(find.byType(AgentManagementView), findsOneWidget);
      expect(locationOf(tester).endsWith('/codex'), isTrue);
    });

    testWidgets('redirects an unknown agent to the agents list', (
      tester,
    ) async {
      await pumpRouter(
        tester,
        initialLocation: const AgentManagementAgentRoute(
          agentId: 'missing-agent',
        ).location,
      );
      expect(locationOf(tester), '/settings/agents');
    });

    test('encodes session restore into typed locations', () {
      expect(
        locationFromSession(
          route: const IdeSessionInitialRoute(),
          workspaceRepository: workspace,
        ),
        const HomeRoute().location,
      );
      expect(
        locationFromSession(
          route: const IdeSessionInitialRoute(
            projectPath: projectPath,
            projectHomeActive: true,
          ),
          workspaceRepository: workspace,
        ),
        const ProjectRoute(projectId: projectId).location,
      );
      expect(
        locationFromSession(
          route: const IdeSessionInitialRoute(
            projectPath: projectPath,
            threadId: threadId,
          ),
          workspaceRepository: workspace,
        ),
        const ThreadRoute(
          projectId: projectId,
          threadId: threadId,
        ).location,
      );
    });
  });
}
