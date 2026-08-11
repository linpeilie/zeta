import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent_management/domain/agent_cli_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';

/// Claude Code CLI 管理仓库最小实现（M0）。
///
/// 设置页可见条目用：detect 固定返回 [AgentInstallationState.notInstalled]，
/// 真实四阶段检测在 T29 接入。不读 `~/.claude` 凭证内容（G7）。
class ClaudeCodeAgentManagementRepository
    implements AgentCliManagementRepository {
  ClaudeCodeAgentManagementRepository();

  @override
  String get agentId => AgentDefinition.claudeCode.id;

  @override
  Future<ManagedAgent> detect({
    required AgentProviderConfig providerConfig,
    required bool enabled,
    AgentDetectionProgressCallback? onProgress,
  }) async {
    final partial = ManagedAgent.claudeCode(enabled: enabled).copyWith(
      installationState: AgentInstallationState.detecting,
      accountState: AgentAccountState.unknown,
      versionState: AgentVersionState.unknown,
      configPath: configPath,
    );
    onProgress?.call(
      const AgentDetectionProgress(
        completed: 0,
        total: 1,
        message: '正在检测 Claude Code',
      ),
      partial,
    );

    final result = partial.copyWith(
      installationState: AgentInstallationState.notInstalled,
      accountState: AgentAccountState.unknown,
      runtimeState: enabled
          ? AgentRuntimeState.unavailable
          : AgentRuntimeState.disabled,
      versionState: AgentVersionState.unknown,
      lastDetectedAt: DateTime.now(),
      errorStage: AgentDiagnosticStage.fileDetection,
      errorMessage: 'Claude Code 适配尚未完成检测',
      suggestion: '请先安装 Claude Code CLI，完整检测将在后续版本提供。',
    );
    onProgress?.call(
      const AgentDetectionProgress(
        completed: 1,
        total: 1,
        message: '未完成 Claude Code 检测',
      ),
      result,
    );
    return result;
  }

  @override
  Future<(AgentConnectionTestResult, List<AgentModelInfo>)> testConnection({
    required AgentProviderConfig providerConfig,
  }) async {
    final testedAt = DateTime.now();
    return (
      AgentConnectionTestResult(
        success: false,
        testedAt: testedAt,
        elapsed: Duration.zero,
        cliCallable: false,
        accountValid: false,
        protocolReady: false,
        failureStage: AgentDiagnosticStage.cliStartup,
        message: 'Claude Code 连接测试尚未接入',
      ),
      const <AgentModelInfo>[],
    );
  }

  @override
  Future<AgentProviderConfig> providerConfigForPath({
    required AgentProviderConfig current,
    required String path,
  }) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty || !looksLikeClaudeCodeCliPath(trimmed)) {
      return AgentProviderConfig.defaultClaudeCode.copyWith(
        enabled: current.enabled,
        extra: current.extra,
      );
    }
    final extra = Map<String, Object?>.from(current.extra)
      ..['cliPath'] = trimmed;
    return current.copyWith(
      id: defaultClaudeCodeProviderId,
      displayName: AgentProviderConfig.defaultClaudeCode.displayName,
      kind: AgentProviderKind.claudeCode,
      command: trimmed,
      arguments: const <String>[],
      extra: extra,
    );
  }

  @override
  String get configPath => '.claude/settings.json';

  @override
  Future<AgentConfigurationDocument> readConfiguration() async {
    final now = DateTime.now();
    return AgentConfigurationDocument(
      path: configPath,
      format: 'JSON',
      content: '',
      maskedContent: '',
      exists: false,
      loadedAt: now,
      signature: 'missing',
    );
  }

  @override
  String? validateConfiguration(String content) => null;

  @override
  Future<AgentConfigurationSaveResult> saveConfiguration({
    required AgentConfigurationDocument original,
    required String content,
    bool overwriteExternalChanges = false,
  }) async {
    throw UnsupportedError('Claude Code 配置编辑尚未接入');
  }

  @override
  Future<List<String>> discoverLogPaths() async => const <String>[];

  @override
  Future<List<AgentLogEntry>> readLogs(
    List<String> paths, {
    int maxLines = 1000,
  }) async => const <AgentLogEntry>[];
}

/// 路径 basename 是否像 Claude Code CLI（`claude` / `claude.exe` 等）。
bool looksLikeClaudeCodeCliPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  final base = (slash >= 0 ? normalized.substring(slash + 1) : normalized)
      .toLowerCase();
  return base == 'claude' || base.startsWith('claude.');
}
