import 'package:agent_conversation_repository/agent_conversation_repository.dart';
import 'package:agent_management_repository/agent_management_repository.dart';
import 'package:agent_provider_repository/agent_provider_repository.dart';
import 'package:desktop_platform_repository/desktop_platform_repository.dart';
import 'package:project_session_repository/project_session_repository.dart';
import 'package:settings_repository/settings_repository.dart';
import 'package:usage_statistics_repository/usage_statistics_repository.dart';
import 'package:workspace_repository/workspace_repository.dart';

final class AppRepositories {
  const AppRepositories({
    required this.workspaceRepository,
    required this.projectSessionRepository,
    required this.desktopPlatformRepository,
    required this.settingsRepository,
    required this.agentProviderRepository,
    required this.agentConversationRepository,
    required this.agentManagementRepository,
    required this.usageStatisticsRepository,
  });

  final WorkspaceRepository workspaceRepository;
  final ProjectSessionRepository projectSessionRepository;
  final DesktopPlatformRepository desktopPlatformRepository;
  final SettingsRepository settingsRepository;
  final AgentProviderRepository agentProviderRepository;
  final AgentConversationRepository agentConversationRepository;
  final AgentManagementRepository agentManagementRepository;
  final UsageStatisticsRepository usageStatisticsRepository;
}
