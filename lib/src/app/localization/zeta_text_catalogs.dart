import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_text_catalog.dart';
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
