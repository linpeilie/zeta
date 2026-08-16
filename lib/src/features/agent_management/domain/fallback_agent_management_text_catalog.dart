import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_text_catalog.dart';

/// 测试与未注入目录时的简体中文等价文案，与当前 zh ARB 逐字一致。
final class FallbackAgentManagementTextCatalog
    implements AgentManagementTextCatalog {
  const FallbackAgentManagementTextCatalog();

  @override
  String locating(String name) => '正在定位 $name';

  @override
  String locatingClaudeCodeCli() => '正在检测 Claude Code CLI';

  @override
  String notFound(String name) => '未找到 $name';

  @override
  String notFoundClaudeCodeCli() => '未找到 Claude Code CLI';

  @override
  String installAndAddToPath(String name) => '请先安装 $name，并确认可执行文件已加入 PATH。';

  @override
  String installClaudeCodeAndAddToPath() =>
      '请先安装 Claude Code，并确认 claude 已加入 PATH。';

  @override
  String found(String name) => '已找到 $name';

  @override
  String confirmExecutableThenRedetect() => '请确认检测到的可执行文件可以正常执行，然后重新检测。';

  @override
  String confirmClaudeVersionCommand() =>
      '请确认 Claude Code CLI 可以正常执行 `claude --version`。';

  @override
  String versionDetected() => '已检测当前版本';

  @override
  String claudeVersionDetected() => '已检测 Claude Code 版本';

  @override
  String accountDetected() => '已检测账号状态';

  @override
  String claudeAuthDetected() => '已检测 Claude Code 登录状态';

  @override
  String configStatusRead() => '已读取配置文件状态';

  @override
  String logsLocated(String name) => '已定位 $name 日志';

  @override
  String latestVersionChecked() => '已检查最新版本';

  @override
  String handshakeComplete() => '已完成协议握手';

  @override
  String detectionComplete(String name) => '$name 检测完成';

  @override
  String retestAfterCheckingConfig(String name) => '请检查 $name 配置和账号状态后重新测试连接。';

  @override
  String retestAfterCheckingGrokAuth() => '请检查 Grok 登录态与配置后重新测试连接。';

  @override
  String confirmClaudeAuthStatusJson() =>
      '请确认 `claude auth status --json` 可执行；也可运行连接测试确认当前 CLI 认证路径。';

  @override
  String noClaudeLoginEvidenceSuggestion() =>
      '未检测到 Claude.ai 登录证据；如需登录可运行 `claude auth login`，也可直接执行连接测试确认当前 CLI 认证路径。';

  @override
  String cannotIdentifyVersion(String name) => '无法识别 $name 版本。';

  @override
  String latestVersionCheckFailed() => '最新版本检查失败。';

  @override
  String cannotParseVersionCheck() => '无法解析版本检查结果。';

  @override
  String versionServiceUnknownFormat() => '版本服务返回了未知格式。';

  @override
  String versionServiceMissingVersion() => '版本服务未返回最新版本号。';

  @override
  String cannotGetLatestVersion(String name) => '无法获取 $name 最新版本。';

  @override
  String accountLoggedIn() => '账号已登录';

  @override
  String runCodexLogin() => '请在终端运行 codex login 后重新检测。';

  @override
  String runGrokLogin() => '请在终端运行 grok login 后重新检测。';

  @override
  String rerunGrokLogin() => '请重新运行 grok login。';

  @override
  String runCodexLoginStatus() => '请在终端运行 codex login status 查看详细信息。';

  @override
  String fixConfigTomlThenRedetect() => '请修复 config.toml 中提示的字段后重新检测。';

  @override
  String codexConfigUnparseable() => 'Codex 配置文件无法解析。';

  @override
  String cannotDetectAccount() => '无法检测账号状态。';

  @override
  String accountCheckFailed() => '账号状态检测失败。';

  @override
  String confirmCliRuns(String name) => '请确认 $name 可以在终端中正常运行。';

  @override
  String cannotParseGrokLoginCache() => '无法解析 Grok 登录缓存。';

  @override
  String noClaudeLoginEvidenceLabel() => '未检测到 Claude.ai OAuth 或 API key 登录证据';

  @override
  String cannotCheckClaudeAuth() => '无法通过 Claude CLI 检查登录状态。';

  @override
  String cannotStartClaudeInitialize() => '无法启动 Claude Code initialize 探测。';

  @override
  String claudeAuthViaApiKey() => '已通过 Anthropic API key 配置认证';

  @override
  String claudeAuthViaApiKeyHelper() => '已通过 API key helper 配置认证';

  @override
  String claudeAuthViaOauthToken() => '已通过 OAuth token 配置认证';

  @override
  String claudeAuthPathDetected() => '已检测到 Claude Code 认证路径';

  @override
  String thirdPartyApiProviderConfigured() => '已配置第三方 API Provider';

  @override
  String configuredProvider(String provider) => '已配置 $provider';

  @override
  String pathNotRegularFile() => '该路径不存在或不是普通文件';

  @override
  String refuseSymlinkConfig() => '拒绝写入符号链接配置文件';

  @override
  String configExternallyModified() => '配置文件已在外部发生修改。';

  @override
  String compatibilitySummary(AgentRuntimeCompatibilityStatus status) =>
      switch (status) {
        AgentRuntimeCompatibilityStatus.supported => '已验证支持',
        AgentRuntimeCompatibilityStatus.supportedWithLimitedCapabilities =>
          '兼容运行，部分能力关闭',
        AgentRuntimeCompatibilityStatus.newerUntested => '版本较新，尚未完整验证',
        AgentRuntimeCompatibilityStatus.olderUnsupported => '版本过旧，不受支持',
        AgentRuntimeCompatibilityStatus.protocolMismatch => '协议不兼容',
      };

  @override
  String cannotToggleEnabled({
    required bool enabled,
    required String displayName,
    required Object error,
  }) => '无法${enabled ? '启用' : '禁用'} $displayName：$error';

  @override
  String accountDataEnrichmentSaveFailed(Object error) => '额度详情增强设置保存失败：$error';

  @override
  String connectionTestFailed(Object error) => '连接测试失败：$error';

  @override
  String configurationReadFailed(Object error) => '配置文件读取失败：$error';

  @override
  String configurationNotLoaded() => '配置文件尚未加载';

  @override
  String logsReadFailed(Object error) => '运行日志读取失败：$error';
}
