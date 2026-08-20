import 'package:agent_conversation_repository/agent_conversation_repository.dart';
import 'package:agent_management_repository/agent_management_repository.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:desktop_notifications_repository/desktop_notifications_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_session_repository/project_session_repository.dart';
import 'package:settings_repository/settings_repository.dart';
import 'package:usage_statistics_repository/usage_statistics_repository.dart';
import 'package:workspace_repository/workspace_repository.dart';
import 'package:zeta/l10n/l10n.dart';

void main() {
  Future<FailureMessages> load(String languageCode) async {
    final l10n = await AppLocalizations.delegate.load(Locale(languageCode));
    return FailureMessages(l10n);
  }

  test('maps every cross-layer code in English and Chinese', () async {
    for (final languageCode in const ['en', 'zh']) {
      final messages = await load(languageCode);
      final resolved = <String>[
        for (final code in AgentProviderStatusCode.values)
          messages.agentProviderStatus(code, providerName: 'Codex'),
        for (final code in AgentProviderFailureCode.values)
          messages.agentProviderFailure(code, providerName: 'Codex'),
        for (final code in AgentConversationFailureCode.values)
          messages.agentConversationFailure(code),
        for (final code in AgentManagementRepositoryFailureCode.values)
          messages.agentManagementFailure(code),
        for (final code in SettingsRepositoryFailureCode.values)
          messages.settingsFailure(code),
        for (final code in ProjectSessionRepositoryFailureCode.values)
          messages.projectSessionFailure(code),
        for (final code in ProjectThreadProviderFailureCode.values)
          messages.projectThreadProviderFailure(code),
        for (final code in WorkspaceRepositoryFailureCode.values)
          messages.workspaceFailure(code),
        for (final code in UsageWarningCode.values)
          messages.usageWarning(
            code,
            providerName: 'Codex',
            count: 2,
          ),
        for (final code in AgentPermissionWarningCode.values)
          messages.agentPermissionWarning(code),
        for (final operation in DesktopNotificationOperation.values)
          messages.desktopNotificationFailure(operation),
        for (final code in AgentPermissionOptionCopyCode.values)
          messages.agentPermissionOption(code),
        for (final code in AgentQuestionTitleCode.values)
          messages.agentQuestionTitle(code),
        for (final code in AgentPlanApprovalTitleCode.values)
          messages.agentPlanApprovalTitle(code),
        for (final code in AgentPermissionRequestDescriptionCode.values)
          messages.agentPermissionRequestDescription(
            code,
            providerName: 'Codex',
            toolName: 'Bash',
          ),
        for (final code in AgentUsageWindowLabelCode.values)
          messages.agentUsageWindowLabel(
            code,
            windowDuration: const Duration(hours: 5),
          ),
        for (final code in AgentUsageLimitNameCode.values)
          messages.agentUsageLimitName(code),
        for (final code in AgentHistoryEventTitleCode.values)
          messages.agentHistoryEventTitle(code),
        for (final code in AgentHistoryEventDescriptionCode.values)
          messages.agentHistoryEventDescription(code),
        messages.agentSleepDuration(const Duration(minutes: 2)),
        messages.agentSleepDuration(const Duration(minutes: 1, seconds: 5)),
        messages.agentSleepDuration(const Duration(seconds: 12)),
        messages.agentUsageWindowDuration(const Duration(days: 7)),
        messages.agentUsageWindowDuration(const Duration(days: 14)),
        messages.agentUsageWindowDuration(const Duration(days: 1)),
        messages.agentUsageWindowDuration(const Duration(days: 2)),
        messages.agentUsageWindowDuration(const Duration(hours: 3)),
        messages.agentUsageWindowDuration(
          const Duration(hours: 1, minutes: 30),
        ),
        messages.agentUsageWindowDuration(const Duration(minutes: 5)),
        messages.agentUsageWindowDuration(Duration.zero),
      ];

      expect(resolved, everyElement(isNotEmpty));
    }
  });

  test('never exposes diagnostic values as localized failure copy', () async {
    final en = await load('en');
    final zh = await load('zh');

    expect(
      en.agentProviderFailure(
        AgentProviderFailureCode.timeout,
        providerName: 'Codex',
      ),
      'Codex request timed out. Please try again.',
    );
    expect(
      zh.agentProviderFailure(
        AgentProviderFailureCode.timeout,
        providerName: 'Codex',
      ),
      'Codex request timed out. Please try again.',
    );
    expect(
      zh.agentProviderStatus(
        AgentProviderStatusCode.failure,
        providerName: 'Codex',
      ),
      '失败',
    );
    expect(
      en.usageWarning(
        UsageWarningCode.unreadableSources,
        providerName: 'Codex',
      ),
      contains('1 Codex'),
    );
  });
}
