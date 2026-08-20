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
}
