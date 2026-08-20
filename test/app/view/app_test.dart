import 'package:agent_conversation_repository/agent_conversation_repository.dart';
import 'package:agent_management_repository/agent_management_repository.dart';
import 'package:agent_provider_repository/agent_provider_repository.dart';
import 'package:desktop_notifications_repository/desktop_notifications_repository.dart';
import 'package:desktop_platform_repository/desktop_platform_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:project_session_repository/project_session_repository.dart';
import 'package:settings_repository/settings_repository.dart';
import 'package:usage_statistics_repository/usage_statistics_repository.dart';
import 'package:workspace_repository/workspace_repository.dart';
import 'package:zeta/app/app.dart';
import 'package:zeta/app/router/routed_app.dart';
import 'package:zeta/l10n/l10n.dart';

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

class _MockUsageStatisticsRepository extends Mock
    implements UsageStatisticsRepository {}

class _MockDesktopNotificationsRepository extends Mock
    implements DesktopNotificationsRepository {}

void main() {
  group('App', () {
    late ProjectSessionRepository sessions;

    setUp(() {
      sessions = _MockProjectSessionRepository();
      when(() => sessions.snapshotChanges).thenAnswer(
        (_) => const Stream<ProjectSessionSnapshot?>.empty(),
      );
      when(sessions.restore).thenAnswer((_) async => null);
    });

    testWidgets('hands the composed repositories to the routed app', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final repositories = AppRepositories(
        workspaceRepository: _MockWorkspaceRepository(),
        projectSessionRepository: sessions,
        desktopPlatformRepository: _MockDesktopPlatformRepository(),
        settingsRepository: _MockSettingsRepository(),
        agentProviderRepository: _MockAgentProviderRepository(),
        agentConversationRepository: _MockAgentConversationRepository(),
        agentManagementRepository: _MockAgentManagementRepository(),
        usageStatisticsRepository: _MockUsageStatisticsRepository(),
        desktopNotificationsRepository: _MockDesktopNotificationsRepository(),
      );

      await tester.pumpWidget(
        App(
          dependencies: AppDependencies(
            locale: const Locale('en'),
            failureMessages: FailureMessages(l10n),
            desktopNotificationCopyResolver: DesktopNotificationCopyResolver(
              l10n,
            ),
            desktopChromeCopyResolver: DesktopChromeCopyResolver(l10n),
          ),
          repositories: repositories,
        ),
      );

      final routed = tester.widget<RoutedApp>(find.byType(RoutedApp));
      expect(routed.repositories, same(repositories));
      expect(routed.dependencies.locale, const Locale('en'));
    });
  });
}
