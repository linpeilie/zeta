import 'package:agent_conversation_repository/agent_conversation_repository.dart';
import 'package:agent_management_repository/agent_management_repository.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:desktop_notifications_repository/desktop_notifications_repository.dart';
import 'package:project_session_repository/project_session_repository.dart';
import 'package:settings_repository/settings_repository.dart';
import 'package:usage_statistics_repository/usage_statistics_repository.dart';
import 'package:workspace_repository/workspace_repository.dart';
import 'package:zeta/l10n/gen/app_localizations.dart';

/// Exhaustive app-owned mapping from lower-layer codes to localized copy.
///
/// The lower layers retain only stable codes and diagnostic evidence. They do
/// not choose a locale or expose user-visible fallback strings.
final class FailureMessages {
  /// Creates a resolver for one already-frozen localization instance.
  const FailureMessages(this._l10n);

  final AppLocalizations _l10n;

  /// Maps provider lifecycle status without rendering diagnostic details.
  String agentProviderStatus(
    AgentProviderStatusCode code, {
    required String providerName,
  }) => switch (code) {
    AgentProviderStatusCode.idle => _l10n.agentProviderReady(providerName),
    AgentProviderStatusCode.connecting => _l10n.agentStartingProvider(
      providerName,
    ),
    AgentProviderStatusCode.ready => _l10n.agentProviderReady(providerName),
    AgentProviderStatusCode.running => _l10n.agentIsWorking,
    AgentProviderStatusCode.unavailable => _l10n.mgmtRuntimeUnavailable,
    AgentProviderStatusCode.failure => _l10n.agentStatusFailed,
  };

  /// Maps a provider failure category; raw diagnostics remain log-only.
  String agentProviderFailure(
    AgentProviderFailureCode code, {
    required String providerName,
  }) => switch (code) {
    AgentProviderFailureCode.unavailable => _l10n.mgmtRuntimeUnavailable,
    AgentProviderFailureCode.invalidConfiguration =>
      _l10n.agentProviderOperationFailed,
    AgentProviderFailureCode.authenticationRequired =>
      _l10n.homeProviderNeedsLogin,
    AgentProviderFailureCode.permissionDenied => _l10n.agentPermUnsupported,
    AgentProviderFailureCode.rateLimited => _l10n.agentErrorGuidanceUsageLimit,
    AgentProviderFailureCode.timeout => _l10n.agentRequestTimedOut(
      providerName,
    ),
    AgentProviderFailureCode.protocol => _l10n.agentProtocolWarning(
      providerName,
    ),
    AgentProviderFailureCode.processExited => _l10n.agentProcessExited(
      providerName,
    ),
    AgentProviderFailureCode.cancelled => _l10n.agentUserCancelled,
    AgentProviderFailureCode.unknown => _l10n.agentUnknownProviderError,
  };

  /// Maps conversation repository failures.
  String agentConversationFailure(AgentConversationFailureCode code) =>
      switch (code) {
        AgentConversationFailureCode.repositoryClosed => _l10n.agentSystemError,
        AgentConversationFailureCode.invalidIdentity =>
          _l10n.agentUnknownProviderError,
        AgentConversationFailureCode.conversationNotOpen =>
          _l10n.agentCouldNotLoadThreads,
        AgentConversationFailureCode.conversationAlreadyOpening =>
          _l10n.agentLoadingSession,
        AgentConversationFailureCode.operationUnsupported =>
          _l10n.usageUnsupported,
        AgentConversationFailureCode.noActiveTurn => _l10n.agentSystemError,
        AgentConversationFailureCode.pendingRequestNotFound =>
          _l10n.agentSystemError,
        AgentConversationFailureCode.historyReadFailed =>
          _l10n.agentCouldNotLoadThreads,
        AgentConversationFailureCode.providerOperationFailed =>
          _l10n.agentProviderOperationFailed,
      };

  /// Maps Agent management repository failures.
  String agentManagementFailure(
    AgentManagementRepositoryFailureCode code,
  ) => switch (code) {
    AgentManagementRepositoryFailureCode.unknownProvider =>
      _l10n.agentUnknownProviderError,
    AgentManagementRepositoryFailureCode.invalidProviderConfiguration =>
      _l10n.mgmtConfigurationNotLoaded,
    AgentManagementRepositoryFailureCode.providerResponseMismatch =>
      _l10n.mgmtUnknownError,
    AgentManagementRepositoryFailureCode.invalidConfiguration =>
      _l10n.mgmtConfigExternallyModified,
    AgentManagementRepositoryFailureCode.clientFailure =>
      _l10n.mgmtUnknownError,
  };

  /// Maps settings repository failures.
  String settingsFailure(SettingsRepositoryFailureCode code) => switch (code) {
    SettingsRepositoryFailureCode.invalidData => _l10n.agentSystemError,
    SettingsRepositoryFailureCode.invalidInput => _l10n.shadcnInvalidValue,
    SettingsRepositoryFailureCode.externalFailure =>
      _l10n.settingsLanguageSaveFailed,
    SettingsRepositoryFailureCode.closed => _l10n.agentSystemError,
  };

  /// Maps project-session persistence failures.
  String projectSessionFailure(ProjectSessionRepositoryFailureCode code) =>
      switch (code) {
        ProjectSessionRepositoryFailureCode.malformedJson =>
          _l10n.projectCannotLoadSessions,
        ProjectSessionRepositoryFailureCode.invalidRoot =>
          _l10n.projectCannotLoadSessions,
        ProjectSessionRepositoryFailureCode.unsupportedVersion =>
          _l10n.projectCannotLoadSessions,
        ProjectSessionRepositoryFailureCode.invalidField =>
          _l10n.projectCannotLoadSessions,
        ProjectSessionRepositoryFailureCode.invalidInput =>
          _l10n.shadcnInvalidValue,
        ProjectSessionRepositoryFailureCode.externalFailure =>
          _l10n.projectCannotLoadSessions,
        ProjectSessionRepositoryFailureCode.closed => _l10n.agentSystemError,
      };

  /// Maps partial per-provider thread discovery failures.
  String projectThreadProviderFailure(
    ProjectThreadProviderFailureCode code,
  ) => switch (code) {
    ProjectThreadProviderFailureCode.externalFailure =>
      _l10n.projectCannotLoadSessions,
    ProjectThreadProviderFailureCode.invalidData =>
      _l10n.projectCannotLoadSessions,
  };

  /// Maps workspace repository failures.
  String workspaceFailure(WorkspaceRepositoryFailureCode code) =>
      switch (code) {
        WorkspaceRepositoryFailureCode.notFound => _l10n.mgmtPathNotRegularFile,
        WorkspaceRepositoryFailureCode.accessDenied => _l10n.agentSystemError,
        WorkspaceRepositoryFailureCode.notDirectory =>
          _l10n.mgmtPathNotRegularFile,
        WorkspaceRepositoryFailureCode.outsideRoot => _l10n.shadcnInvalidValue,
        WorkspaceRepositoryFailureCode.symbolicLink =>
          _l10n.mgmtRefuseSymlinkConfig,
        WorkspaceRepositoryFailureCode.ioFailure => _l10n.agentSystemError,
        WorkspaceRepositoryFailureCode.cancelled => _l10n.agentUserCancelled,
        WorkspaceRepositoryFailureCode.invalidInput => _l10n.shadcnInvalidValue,
        WorkspaceRepositoryFailureCode.invalidData => _l10n.agentSystemError,
        WorkspaceRepositoryFailureCode.closed => _l10n.agentSystemError,
      };

  /// Maps non-fatal usage report warnings.
  String usageWarning(
    UsageWarningCode code, {
    required String providerName,
    int count = 1,
  }) => switch (code) {
    UsageWarningCode.unreadableSources => _l10n.usageSessionFilesUnreadable(
      '$count',
      providerName,
    ),
    UsageWarningCode.discoveryFailure => _l10n.usageSessionDirIncomplete(
      providerName,
    ),
    UsageWarningCode.cacheReadFailure => _l10n.usageIndexReadRescanned(
      providerName,
    ),
    UsageWarningCode.cacheWriteFailure => _l10n.usageIndexWriteFailed,
    UsageWarningCode.providerFailure => _l10n.usageAgentTemporarilyUnavailable,
  };

  /// Maps a permission-application warning.
  String agentPermissionWarning(AgentPermissionWarningCode code) =>
      switch (code) {
        AgentPermissionWarningCode.appliesNextSession =>
          _l10n.agentPermNextSession,
        AgentPermissionWarningCode.downgradedByRuntime =>
          _l10n.agentPermRuntimeStale,
      };

  /// Maps desktop-notification boundary failures without exposing the cause.
  String desktopNotificationFailure(DesktopNotificationOperation operation) =>
      switch (operation) {
        DesktopNotificationOperation.notify => _l10n.agentSystemError,
        DesktopNotificationOperation.setBadge => _l10n.agentSystemError,
        DesktopNotificationOperation.requestAttention => _l10n.agentSystemError,
      };

  /// Maps app-owned permission option labels.
  String agentPermissionOption(AgentPermissionOptionCopyCode code) =>
      switch (code) {
        AgentPermissionOptionCopyCode.ask => _l10n.agentPermissionAsk,
        AgentPermissionOptionCopyCode.acceptEdits =>
          _l10n.agentPermissionAcceptEdits,
        AgentPermissionOptionCopyCode.plan => _l10n.agentPermissionPlan,
        AgentPermissionOptionCopyCode.bypassPermissions =>
          _l10n.agentPermissionBypass,
        AgentPermissionOptionCopyCode.auto => _l10n.agentPermissionAuto,
        AgentPermissionOptionCopyCode.alwaysApprove =>
          _l10n.agentPermissionAlwaysApprove,
      };

  /// Maps app-owned question request titles.
  String agentQuestionTitle(AgentQuestionTitleCode code) => switch (code) {
    AgentQuestionTitleCode.agentRequestsInput => _l10n.agentRequestsInput,
  };

  /// Maps app-owned plan approval titles.
  String agentPlanApprovalTitle(AgentPlanApprovalTitleCode code) =>
      switch (code) {
        AgentPlanApprovalTitleCode.planApproval => _l10n.agentPlanApprovalTitle,
      };

  /// Maps app-owned permission request descriptions.
  String agentPermissionRequestDescription(
    AgentPermissionRequestDescriptionCode code, {
    required String providerName,
    required String toolName,
  }) => switch (code) {
    AgentPermissionRequestDescriptionCode.providerRequestsTool =>
      _l10n.agentPermissionRequestDescription(providerName, toolName),
  };

  /// Maps app-owned quota-window labels, formatting duration evidence when needed.
  String agentUsageWindowLabel(
    AgentUsageWindowLabelCode code, {
    Duration? windowDuration,
  }) => switch (code) {
    AgentUsageWindowLabelCode.duration => agentUsageWindowDuration(
      windowDuration ?? Duration.zero,
    ),
    AgentUsageWindowLabelCode.fiveHours => _l10n.agentQuotaFiveHours,
    AgentUsageWindowLabelCode.oneWeek => _l10n.agentQuotaOneWeek,
    AgentUsageWindowLabelCode.oneDay => _l10n.agentUsageWindowOneDay,
    AgentUsageWindowLabelCode.sonnetOneWeek => _l10n.agentQuotaSonnetOneWeek,
    AgentUsageWindowLabelCode.opusOneWeek => _l10n.agentQuotaOpusOneWeek,
    AgentUsageWindowLabelCode.planQuota => _l10n.agentPlanQuota,
    AgentUsageWindowLabelCode.onDemandQuota => _l10n.agentOnDemandQuota,
    AgentUsageWindowLabelCode.primaryQuota => _l10n.agentPrimaryQuota,
    AgentUsageWindowLabelCode.extraQuota => _l10n.agentExtraQuota,
  };

  /// Maps app-owned quota heading labels.
  String agentUsageLimitName(AgentUsageLimitNameCode code) => switch (code) {
    AgentUsageLimitNameCode.claudeCodeSubscriptionQuota =>
      _l10n.agentClaudeCodeSubscriptionQuota,
  };

  /// Maps app-owned history event titles.
  String agentHistoryEventTitle(
    AgentHistoryEventTitleCode code,
  ) => switch (code) {
    AgentHistoryEventTitleCode.reviewModeEntered =>
      _l10n.agentReviewModeEntered,
    AgentHistoryEventTitleCode.reviewModeExited => _l10n.agentReviewModeExited,
    AgentHistoryEventTitleCode.contextCompacted => _l10n.agentContextCompacted,
    AgentHistoryEventTitleCode.hookPrompt => _l10n.agentHookPrompt,
    AgentHistoryEventTitleCode.waiting => _l10n.agentWaiting,
    AgentHistoryEventTitleCode.subAgentActivity => _l10n.agentSubAgentActivity,
    AgentHistoryEventTitleCode.toolSearch => _l10n.agentHistoryToolSearch,
    AgentHistoryEventTitleCode.webSearch => _l10n.agentHistoryWebSearch,
    AgentHistoryEventTitleCode.permissionRequest =>
      _l10n.agentPermKindPermissions,
    AgentHistoryEventTitleCode.requestedUserInput => _l10n.agentWaitingInput,
    AgentHistoryEventTitleCode.requestedPermissions =>
      _l10n.agentWaitingApproval,
  };

  /// Maps app-owned history event descriptions.
  String agentHistoryEventDescription(AgentHistoryEventDescriptionCode code) =>
      switch (code) {
        AgentHistoryEventDescriptionCode.contextCompacted =>
          _l10n.agentContextCompactedDescription,
        AgentHistoryEventDescriptionCode.subAgentStarted =>
          _l10n.agentSubAgentStarted,
        AgentHistoryEventDescriptionCode.subAgentInteracted =>
          _l10n.agentSubAgentInteracted,
        AgentHistoryEventDescriptionCode.subAgentInterrupted =>
          _l10n.agentSubAgentInterrupted,
        AgentHistoryEventDescriptionCode.subAgentUpdated =>
          _l10n.agentSubAgentUpdated,
      };

  /// Formats a sleep duration without choosing locale in lower layers.
  String agentSleepDuration(Duration duration) {
    if (duration.inMinutes >= 1) {
      final seconds = duration.inSeconds % 60;
      return seconds == 0
          ? _l10n.agentSleepMinutes('${duration.inMinutes}')
          : _l10n.agentSleepMinutesSeconds(
              '${duration.inMinutes}',
              '$seconds',
            );
    }
    return _l10n.agentSleepSeconds('${duration.inSeconds}');
  }

  /// Formats a quota window duration using the existing ARB helpers.
  String agentUsageWindowDuration(Duration duration) {
    const weekMinutes = 7 * 24 * 60;
    const dayMinutes = 24 * 60;
    final minutes = duration.inMinutes;
    if (minutes > 0 && minutes % weekMinutes == 0) {
      final weeks = minutes ~/ weekMinutes;
      return weeks == 1
          ? _l10n.agentUsageWindowOneWeek
          : _l10n.agentUsageWindowWeeks('$weeks');
    }
    if (minutes > 0 && minutes % dayMinutes == 0) {
      final days = minutes ~/ dayMinutes;
      return days == 1
          ? _l10n.agentUsageWindowOneDay
          : _l10n.agentUsageWindowDays('$days');
    }
    if (minutes > 0 && minutes % 60 == 0) {
      return _l10n.agentUsageWindowHours('${minutes ~/ 60}');
    }
    if (minutes > 60) {
      return _l10n.agentUsageWindowHoursMinutes(
        '${minutes ~/ 60}',
        '${minutes % 60}',
      );
    }
    if (minutes > 0) {
      return _l10n.agentUsageWindowMinutes('$minutes');
    }
    return _l10n.agentUsageWindowMinutes('0');
  }
}
