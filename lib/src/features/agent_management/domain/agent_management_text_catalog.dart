import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// Zeta 产生的 Agent 管理文案。不暴露 ARB key、Locale 或 Provider raw payload。
abstract interface class AgentManagementTextCatalog {
  String locating(String name);

  String locatingClaudeCodeCli();

  String notFound(String name);

  String notFoundClaudeCodeCli();

  String installAndAddToPath(String name);

  String installClaudeCodeAndAddToPath();

  String found(String name);

  String confirmExecutableThenRedetect();

  String confirmClaudeVersionCommand();

  String versionDetected();

  String claudeVersionDetected();

  String accountDetected();

  String claudeAuthDetected();

  String configStatusRead();

  String logsLocated(String name);

  String latestVersionChecked();

  String handshakeComplete();

  String detectionComplete(String name);

  String retestAfterCheckingConfig(String name);

  String retestAfterCheckingGrokAuth();

  String confirmClaudeAuthStatusJson();

  String noClaudeLoginEvidenceSuggestion();

  String cannotIdentifyVersion(String name);

  String latestVersionCheckFailed();

  String cannotParseVersionCheck();

  String versionServiceUnknownFormat();

  String versionServiceMissingVersion();

  String cannotGetLatestVersion(String name);

  String accountLoggedIn();

  String runCodexLogin();

  String runGrokLogin();

  String rerunGrokLogin();

  String runCodexLoginStatus();

  String fixConfigTomlThenRedetect();

  String codexConfigUnparseable();

  String cannotDetectAccount();

  String accountCheckFailed();

  String confirmCliRuns(String name);

  String cannotParseGrokLoginCache();

  String noClaudeLoginEvidenceLabel();

  String cannotCheckClaudeAuth();

  String cannotStartClaudeInitialize();

  String claudeAuthViaApiKey();

  String claudeAuthViaApiKeyHelper();

  String claudeAuthViaOauthToken();

  String claudeAuthPathDetected();

  String thirdPartyApiProviderConfigured();

  String configuredProvider(String provider);

  String pathNotRegularFile();

  String refuseSymlinkConfig();

  String configExternallyModified();

  String compatibilitySummary(AgentRuntimeCompatibilityStatus status);

  String cannotToggleEnabled({
    required bool enabled,
    required String displayName,
    required Object error,
  });

  String accountDataEnrichmentSaveFailed(Object error);

  String connectionTestFailed(Object error);

  String configurationReadFailed(Object error);

  String configurationNotLoaded();

  String logsReadFailed(Object error);
}
