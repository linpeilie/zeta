import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_text_catalog.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_text_catalog.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_text_catalog.dart';
import 'package:zeta/src/ui/localization/generated/app_localizations.dart';

/// 把同一份 [AppLocalizations] 拆成各 feature 文本目录的组合对象。
final class ZetaTextCatalogs {
  const ZetaTextCatalogs(this.l10n);

  final AppLocalizations l10n;

  UsageStatisticsTextCatalog get usageStatistics =>
      AppUsageStatisticsTextCatalog(l10n);

  AgentManagementTextCatalog get agentManagement =>
      AppAgentManagementTextCatalog(l10n);

  AgentUiTextCatalog get agentUi => AppAgentUiTextCatalog(l10n);

  DesktopAttentionTextCatalog get desktopAttention =>
      AppDesktopAttentionTextCatalog(l10n);
}

final class AppUsageStatisticsTextCatalog
    implements UsageStatisticsTextCatalog {
  const AppUsageStatisticsTextCatalog(this._l10n);

  final AppLocalizations _l10n;

  @override
  String timeRangeLabel(UsageTimeRangePreset preset) => switch (preset) {
    UsageTimeRangePreset.today => _l10n.usageTimeRangeToday,
    UsageTimeRangePreset.last7Days => _l10n.usageTimeRangeLast7Days,
    UsageTimeRangePreset.last30Days => _l10n.usageTimeRangeLast30Days,
    UsageTimeRangePreset.last90Days => _l10n.usageTimeRangeLast90Days,
    UsageTimeRangePreset.thisMonth => _l10n.usageTimeRangeThisMonth,
    UsageTimeRangePreset.previousMonth => _l10n.usageTimeRangePreviousMonth,
    UsageTimeRangePreset.custom => _l10n.usageTimeRangeCustom,
  };

  @override
  String taskStatusLabel(UsageTaskStatus status) => switch (status) {
    UsageTaskStatus.running => _l10n.usageTaskStatusRunning,
    UsageTaskStatus.completed => _l10n.usageTaskStatusCompleted,
    UsageTaskStatus.interrupted => _l10n.usageTaskStatusInterrupted,
    UsageTaskStatus.failed => _l10n.usageTaskStatusFailed,
    UsageTaskStatus.unknown => _l10n.usageTaskStatusUnknown,
  };

  @override
  String errorCategoryLabel(UsageErrorCategory category) => switch (category) {
    UsageErrorCategory.account => _l10n.usageErrorCategoryAccount,
    UsageErrorCategory.cli => _l10n.usageErrorCategoryCli,
    UsageErrorCategory.network => _l10n.usageErrorCategoryNetwork,
    UsageErrorCategory.timeout => _l10n.usageErrorCategoryTimeout,
    UsageErrorCategory.cancelled => _l10n.usageErrorCategoryCancelled,
    UsageErrorCategory.other => _l10n.usageErrorCategoryOther,
  };

  @override
  String errorNextAction(UsageErrorCategory category) => switch (category) {
    UsageErrorCategory.account => _l10n.usageErrorNextActionAccount,
    UsageErrorCategory.cli => _l10n.usageErrorNextActionCli,
    UsageErrorCategory.network => _l10n.usageErrorNextActionNetwork,
    UsageErrorCategory.timeout => _l10n.usageErrorNextActionTimeout,
    UsageErrorCategory.cancelled => _l10n.usageErrorNextActionCancelled,
    UsageErrorCategory.other => _l10n.usageErrorNextActionOther,
  };

  @override
  String trendMetricLabel(UsageTrendMetric metric) => switch (metric) {
    UsageTrendMetric.calls => _l10n.usageTrendMetricCalls,
    UsageTrendMetric.successRate => _l10n.usageTrendMetricSuccessRate,
    UsageTrendMetric.totalTokens => _l10n.usageTrendMetricTotalTokens,
    UsageTrendMetric.averageResponse => _l10n.usageTrendMetricAverageResponse,
    UsageTrendMetric.averageDuration => _l10n.usageTrendMetricAverageDuration,
  };

  @override
  String rankSortLabel(UsageRankSort sort) => switch (sort) {
    UsageRankSort.calls => _l10n.usageRankSortCalls,
    UsageRankSort.totalTokens => _l10n.usageRankSortTotalTokens,
    UsageRankSort.failures => _l10n.usageRankSortFailures,
    UsageRankSort.averageDuration => _l10n.usageRankSortAverageDuration,
  };

  @override
  String get unknownProjectName => _l10n.usageUnknownProject;

  @override
  String loadFailed(Object error) => _l10n.usageLoadFailed('$error');

  @override
  String get quotaUnreadable => _l10n.usageQuotaUnreadable;

  @override
  String get agentTemporarilyUnavailable =>
      _l10n.usageAgentTemporarilyUnavailable;

  @override
  String get tokenHistoryUnavailable => _l10n.usageTokenHistoryUnavailable;

  @override
  String get tokenSourceMismatch => _l10n.usageTokenSourceMismatch;

  @override
  String get noTokenHistory => _l10n.usageNoTokenHistory;

  @override
  String get todayTokensUnreadable => _l10n.usageTodayTokensUnreadable;

  @override
  String get indexWriteFailed => _l10n.usageIndexWriteFailed;

  @override
  String indexReadRescanned(String providerName) =>
      _l10n.usageIndexReadRescanned(providerName);

  @override
  String get agentDisabledOrUnavailable =>
      _l10n.usageAgentDisabledOrUnavailable;

  @override
  String get agentUsageTemporarilyUnavailable =>
      _l10n.usageAgentUsageTemporarilyUnavailable;
}

final class AppAgentManagementTextCatalog
    implements AgentManagementTextCatalog {
  const AppAgentManagementTextCatalog(this._l10n);

  final AppLocalizations _l10n;

  @override
  String locating(String name) => _l10n.mgmtLocating(name);

  @override
  String locatingClaudeCodeCli() => _l10n.mgmtLocatingClaudeCodeCli;

  @override
  String notFound(String name) => _l10n.mgmtNotFound(name);

  @override
  String notFoundClaudeCodeCli() => _l10n.mgmtNotFoundClaudeCodeCli;

  @override
  String installAndAddToPath(String name) =>
      _l10n.mgmtInstallAndAddToPath(name);

  @override
  String installClaudeCodeAndAddToPath() =>
      _l10n.mgmtInstallClaudeCodeAndAddToPath;

  @override
  String found(String name) => _l10n.mgmtFound(name);

  @override
  String confirmExecutableThenRedetect() =>
      _l10n.mgmtConfirmExecutableThenRedetect;

  @override
  String confirmClaudeVersionCommand() => _l10n.mgmtConfirmClaudeVersionCommand;

  @override
  String versionDetected() => _l10n.mgmtVersionDetected;

  @override
  String claudeVersionDetected() => _l10n.mgmtClaudeVersionDetected;

  @override
  String accountDetected() => _l10n.mgmtAccountDetected;

  @override
  String claudeAuthDetected() => _l10n.mgmtClaudeAuthDetected;

  @override
  String configStatusRead() => _l10n.mgmtConfigStatusRead;

  @override
  String logsLocated(String name) => _l10n.mgmtLogsLocated(name);

  @override
  String latestVersionChecked() => _l10n.mgmtLatestVersionChecked;

  @override
  String handshakeComplete() => _l10n.mgmtHandshakeComplete;

  @override
  String detectionComplete(String name) => _l10n.mgmtDetectionComplete(name);

  @override
  String retestAfterCheckingConfig(String name) =>
      _l10n.mgmtRetestAfterCheckingConfig(name);

  @override
  String retestAfterCheckingGrokAuth() => _l10n.mgmtRetestAfterCheckingGrokAuth;

  @override
  String confirmClaudeAuthStatusJson() => _l10n.mgmtConfirmClaudeAuthStatusJson;

  @override
  String noClaudeLoginEvidenceSuggestion() =>
      _l10n.mgmtNoClaudeLoginEvidenceSuggestion;

  @override
  String cannotIdentifyVersion(String name) =>
      _l10n.mgmtCannotIdentifyVersion(name);

  @override
  String latestVersionCheckFailed() => _l10n.mgmtLatestVersionCheckFailed;

  @override
  String cannotParseVersionCheck() => _l10n.mgmtCannotParseVersionCheck;

  @override
  String versionServiceUnknownFormat() => _l10n.mgmtVersionServiceUnknownFormat;

  @override
  String versionServiceMissingVersion() =>
      _l10n.mgmtVersionServiceMissingVersion;

  @override
  String cannotGetLatestVersion(String name) =>
      _l10n.mgmtCannotGetLatestVersion(name);

  @override
  String accountLoggedIn() => _l10n.mgmtAccountLoggedIn;

  @override
  String runCodexLogin() => _l10n.mgmtRunCodexLogin;

  @override
  String runGrokLogin() => _l10n.mgmtRunGrokLogin;

  @override
  String rerunGrokLogin() => _l10n.mgmtRerunGrokLogin;

  @override
  String runCodexLoginStatus() => _l10n.mgmtRunCodexLoginStatus;

  @override
  String fixConfigTomlThenRedetect() => _l10n.mgmtFixConfigTomlThenRedetect;

  @override
  String codexConfigUnparseable() => _l10n.mgmtCodexConfigUnparseable;

  @override
  String cannotDetectAccount() => _l10n.mgmtCannotDetectAccount;

  @override
  String accountCheckFailed() => _l10n.mgmtAccountCheckFailed;

  @override
  String confirmCliRuns(String name) => _l10n.mgmtConfirmCliRuns(name);

  @override
  String cannotParseGrokLoginCache() => _l10n.mgmtCannotParseGrokLoginCache;

  @override
  String noClaudeLoginEvidenceLabel() => _l10n.mgmtNoClaudeLoginEvidenceLabel;

  @override
  String cannotCheckClaudeAuth() => _l10n.mgmtCannotCheckClaudeAuth;

  @override
  String cannotStartClaudeInitialize() => _l10n.mgmtCannotStartClaudeInitialize;

  @override
  String claudeAuthViaApiKey() => _l10n.mgmtClaudeAuthViaApiKey;

  @override
  String claudeAuthViaApiKeyHelper() => _l10n.mgmtClaudeAuthViaApiKeyHelper;

  @override
  String claudeAuthViaOauthToken() => _l10n.mgmtClaudeAuthViaOauthToken;

  @override
  String claudeAuthPathDetected() => _l10n.mgmtClaudeAuthPathDetected;

  @override
  String thirdPartyApiProviderConfigured() =>
      _l10n.mgmtThirdPartyApiProviderConfigured;

  @override
  String configuredProvider(String provider) =>
      _l10n.mgmtConfiguredProvider(provider);

  @override
  String pathNotRegularFile() => _l10n.mgmtPathNotRegularFile;

  @override
  String refuseSymlinkConfig() => _l10n.mgmtRefuseSymlinkConfig;

  @override
  String configExternallyModified() => _l10n.mgmtConfigExternallyModified;

  @override
  String compatibilitySummary(AgentRuntimeCompatibilityStatus status) =>
      switch (status) {
        AgentRuntimeCompatibilityStatus.supported => _l10n.mgmtCompatSupported,
        AgentRuntimeCompatibilityStatus.supportedWithLimitedCapabilities =>
          _l10n.mgmtCompatLimited,
        AgentRuntimeCompatibilityStatus.newerUntested =>
          _l10n.mgmtCompatNewerUntested,
        AgentRuntimeCompatibilityStatus.olderUnsupported =>
          _l10n.mgmtCompatOlderUnsupported,
        AgentRuntimeCompatibilityStatus.protocolMismatch =>
          _l10n.mgmtCompatProtocolMismatch,
      };

  @override
  String cannotToggleEnabled({
    required bool enabled,
    required String displayName,
    required Object error,
  }) => enabled
      ? _l10n.mgmtCannotEnable(displayName, '$error')
      : _l10n.mgmtCannotDisable(displayName, '$error');

  @override
  String accountDataEnrichmentSaveFailed(Object error) =>
      _l10n.mgmtAccountDataEnrichmentSaveFailed('$error');

  @override
  String connectionTestFailed(Object error) =>
      _l10n.mgmtConnectionTestFailed('$error');

  @override
  String configurationReadFailed(Object error) =>
      _l10n.mgmtConfigurationReadFailed('$error');

  @override
  String configurationNotLoaded() => _l10n.mgmtConfigurationNotLoaded;

  @override
  String logsReadFailed(Object error) => _l10n.mgmtLogsReadFailed('$error');
}

final class AppAgentUiTextCatalog implements AgentUiTextCatalog {
  const AppAgentUiTextCatalog(this._l10n);

  final AppLocalizations _l10n;

  @override
  String get thinkingToolTitle => _l10n.agentToolThink;

  @override
  String toolKindLabel(AgentToolKind kind) {
    return switch (kind) {
      AgentToolKind.read => _l10n.agentToolRead,
      AgentToolKind.edit => _l10n.agentToolEdit,
      AgentToolKind.delete => _l10n.agentToolDelete,
      AgentToolKind.move => _l10n.agentToolMove,
      AgentToolKind.search => _l10n.agentToolSearch,
      AgentToolKind.execute => _l10n.agentToolExecute,
      AgentToolKind.think => _l10n.agentToolThink,
      AgentToolKind.fetch => _l10n.agentToolFetch,
      AgentToolKind.other => _l10n.agentToolOther,
    };
  }

  @override
  String? activitySegmentLabel(AgentTurnActivitySnapshot activity) {
    return switch (activity.phase) {
      AgentTurnActivityPhase.starting => _l10n.agentStarting,
      AgentTurnActivityPhase.thinking => _l10n.agentThinking,
      AgentTurnActivityPhase.responding => _l10n.agentResponding,
      AgentTurnActivityPhase.toolRunning => () {
        final label = activity.label?.trim();
        if (label == null || label.isEmpty) {
          return _l10n.agentRunning;
        }
        final short = label.length > 28 ? '${label.substring(0, 28)}…' : label;
        return _l10n.agentRunningPrefix(short);
      }(),
      AgentTurnActivityPhase.idle => null,
    };
  }

  @override
  String get planReadyTitle => _l10n.agentPlanReady;

  @override
  String get modelReroutedTitle => _l10n.agentModelRerouted;

  @override
  String modelReroutedNotice(String toModel) =>
      _l10n.agentModelReroutedTo(toModel);

  @override
  String get deprecationNoticeTitle => _l10n.agentDeprecationNotice;

  @override
  String get deprecationUpgradeHint => _l10n.agentDeprecationUpgradeHint;

  @override
  String get rerouteReasonHighRisk => _l10n.agentRerouteReasonHighRisk;

  @override
  String rerouteReasonUnknown(String reason) =>
      _l10n.agentRerouteReasonUnknown(reason);

  @override
  String get turnFailedPrefix => _l10n.agentTurnFailedPrefix;

  @override
  String get unknownProviderError => _l10n.agentUnknownProviderError;

  @override
  String get serverWillRetry => _l10n.agentServerWillRetry;

  @override
  String? errorGuidance(String code) {
    return switch (code) {
      'serverOverloaded' => _l10n.agentErrorGuidanceServerOverloaded,
      'usageLimitExceeded' => _l10n.agentErrorGuidanceUsageLimit,
      'sessionBudgetExceeded' => _l10n.agentErrorGuidanceSessionBudget,
      'unauthorized' => _l10n.agentErrorGuidanceUnauthorized,
      'internalServerError' => _l10n.agentErrorGuidanceInternalServer,
      'httpConnectionFailed' ||
      'responseStreamConnectionFailed' ||
      'responseStreamDisconnected' => _l10n.agentErrorGuidanceNetwork,
      'responseTooManyFailedAttempts' =>
        _l10n.agentErrorGuidanceTooManyAttempts,
      _ => null,
    };
  }

  @override
  String get webSearchTitle => _l10n.agentWebSearch;

  @override
  String get viewImageTitle => _l10n.agentViewImage;

  @override
  String get generateImageTitle => _l10n.agentGenerateImage;

  @override
  String get collaboratePrefix => _l10n.agentCollaboratePrefix;

  @override
  String get toolCallFallbackTitle => _l10n.agentToolCallFallback;

  @override
  String get reviewModeEnteredTitle => _l10n.agentReviewModeEntered;

  @override
  String get reviewModeExitedTitle => _l10n.agentReviewModeExited;

  @override
  String get contextCompactedTitle => _l10n.agentContextCompacted;

  @override
  String get contextCompactedDescription =>
      _l10n.agentContextCompactedDescription;

  @override
  String get hookPromptTitle => _l10n.agentHookPrompt;

  @override
  String get waitingTitle => _l10n.agentWaiting;

  @override
  String sleepMinutes(String minutes) => _l10n.agentSleepMinutes(minutes);

  @override
  String sleepMinutesSeconds(String minutes, String seconds) =>
      _l10n.agentSleepMinutesSeconds(minutes, seconds);

  @override
  String sleepSeconds(String seconds) => _l10n.agentSleepSeconds(seconds);

  @override
  String get subAgentActivityTitle => _l10n.agentSubAgentActivity;

  @override
  String get subAgentStarted => _l10n.agentSubAgentStarted;

  @override
  String get subAgentInteracted => _l10n.agentSubAgentInteracted;

  @override
  String get subAgentInterrupted => _l10n.agentSubAgentInterrupted;

  @override
  String get subAgentUpdated => _l10n.agentSubAgentUpdated;

  @override
  String get userCancelled => _l10n.agentUserCancelled;

  @override
  String get permissionAskDescription => _l10n.agentPermissionAskDescription;

  @override
  String get permissionAcceptEditsDescription =>
      _l10n.agentPermissionAcceptEditsDescription;

  @override
  String get permissionPlanDescription => _l10n.agentPermissionPlanDescription;

  @override
  String get permissionBypassDescription =>
      _l10n.agentPermissionBypassDescription;

  @override
  String get planQuotaLabel => _l10n.agentPlanQuota;

  @override
  String get onDemandQuotaLabel => _l10n.agentOnDemandQuota;

  @override
  String get primaryQuotaLabel => _l10n.agentPrimaryQuota;

  @override
  String get extraQuotaLabel => _l10n.agentExtraQuota;

  @override
  String get waitingApproval => _l10n.agentWaitingApproval;

  @override
  String get waitingInput => _l10n.agentWaitingInput;

  @override
  String get systemError => _l10n.agentSystemError;

  @override
  String get loadingConversationModes => _l10n.agentLoadingModesStatus;

  @override
  String get modeNotSelectableNow => _l10n.agentModeNotSelectableNow;

  @override
  String get modelCatalogRefreshFailed => _l10n.agentModelCatalogRefreshFailed;

  @override
  String get modelListRefreshFailed => _l10n.agentModelListRefreshFailed;

  @override
  String get cannotSwitchPermissionDuringTurn =>
      _l10n.agentCannotSwitchPermissionDuringTurn;

  @override
  String providerReady(String name) => _l10n.agentProviderReady(name);

  @override
  String get couldNotLoadProviders => _l10n.agentCouldNotLoadProviders;

  @override
  String get agentIsWorking => _l10n.agentIsWorking;

  @override
  String get loadingHistory => _l10n.agentLoadingHistory;

  @override
  String get creatingBranch => _l10n.agentCreatingBranch;

  @override
  String get couldNotUpdateSessionOption =>
      _l10n.agentCouldNotUpdateSessionOption;

  @override
  String get providerOperationFailed => _l10n.agentProviderOperationFailed;

  @override
  String get modeLoadFailed => _l10n.agentModeLoadFailed;

  @override
  String fastIncompatible(String effort) => _l10n.agentFastIncompatible(effort);

  @override
  String fastDisableAndSwitch(String effort) =>
      _l10n.agentFastDisableAndSwitch(effort);

  @override
  String fastSwitchAndEnable(String effort) =>
      _l10n.agentFastSwitchAndEnable(effort);

  @override
  String get modelSaveFailed => _l10n.agentModelSaveFailed;

  @override
  String modelUnavailableSwitched(String previous, String current) =>
      _l10n.agentModelUnavailableSwitched(previous, current);

  @override
  String get permNextSession => _l10n.agentPermNextSession;

  @override
  String get permCurrentTurn => _l10n.agentPermCurrentTurn;

  @override
  String get permUnsupported => _l10n.agentPermUnsupported;

  @override
  String get permNextSend => _l10n.agentPermNextSend;

  @override
  String get permSavedButPersistFailed => _l10n.agentPermSavedButPersistFailed;

  @override
  String get permAppliedButPersistFailed =>
      _l10n.agentPermAppliedButPersistFailed;

  @override
  String get permRuntimeStale => _l10n.agentPermRuntimeStale;

  @override
  String get permSwitchFailed => _l10n.agentPermSwitchFailed;

  @override
  String get providerDefaultPermission => _l10n.agentProviderDefaultPermission;

  @override
  String threadDisabled(String name) => _l10n.agentThreadDisabled(name);
}

final class AppDesktopAttentionTextCatalog
    implements DesktopAttentionTextCatalog {
  const AppDesktopAttentionTextCatalog(this._l10n);

  final AppLocalizations _l10n;

  @override
  String titleFor(AgentAttentionKind kind) {
    return switch (kind) {
      AgentAttentionKind.turnCompleted => _l10n.desktopAttentionTurnCompleted,
      AgentAttentionKind.turnFailed => _l10n.desktopAttentionTurnFailed,
      AgentAttentionKind.turnInterrupted =>
        _l10n.desktopAttentionTurnInterrupted,
      AgentAttentionKind.permissionRequired =>
        _l10n.desktopAttentionPermissionRequired,
      AgentAttentionKind.questionRequired =>
        _l10n.desktopAttentionQuestionRequired,
      AgentAttentionKind.planApprovalRequired =>
        _l10n.desktopAttentionPlanApprovalRequired,
      AgentAttentionKind.planExecutionRequired =>
        _l10n.desktopAttentionPlanExecutionRequired,
    };
  }

  @override
  String get currentProjectName => _l10n.desktopAttentionCurrentProject;

  @override
  String sessionBody(String projectName) =>
      _l10n.desktopAttentionSessionBody(projectName);

  @override
  String get linuxAction => _l10n.desktopAttentionLinuxAction;
}
