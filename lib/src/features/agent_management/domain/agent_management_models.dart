import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// Agent CLI 的安装检测状态。
enum AgentInstallationState {
  unknown,
  detecting,
  installed,
  notInstalled,
  unavailable,
}

/// Agent CLI 的账号状态。
enum AgentAccountState {
  unknown,
  checking,
  loggedIn,
  loggedOut,
  expired,
  notRequired,
  unavailable,
}

/// Agent CLI 相对当前应用的运行状态。
enum AgentRuntimeState {
  notRunning,
  idle,
  starting,
  running,
  stopping,
  error,
  unavailable,
  disabled,
}

/// 当前版本与线上最新版本的比较状态。
enum AgentVersionState {
  unknown,
  current,
  updateAvailable,
  checking,
  checkFailed,
}

/// 统一的 Agent 诊断阶段。
enum AgentDiagnosticStage {
  fileDetection,
  cliStartup,
  versionDetection,
  accountAuthentication,
  protocolHandshake,
  modelLoading,
  configurationRead,
  testRequest,
  processExit,
}

/// 统一日志级别。
enum AgentLogLevel { debug, info, warning, error }

/// 应用内置的 Agent 支持定义。
class AgentDefinition {
  const AgentDefinition({
    required this.id,
    required this.displayName,
    required this.vendor,
    required this.commandName,
    required this.protocol,
    required this.transport,
    required this.configFormat,
    required this.defaultConfigRelativePath,
    required this.npmPackage,
    this.isBeta = false,
  });

  final String id;
  final String displayName;
  final String vendor;
  final String commandName;
  final String protocol;
  final String transport;
  final String configFormat;
  final String defaultConfigRelativePath;
  final String npmPackage;

  /// 是否需要用户显式启用并确认兼容性风险的预览能力。
  final bool isBeta;

  /// 内置 Codex CLI 定义。
  static const AgentDefinition codex = AgentDefinition(
    id: defaultAgentProviderId,
    displayName: 'Codex',
    vendor: 'OpenAI',
    commandName: 'codex',
    protocol: 'JSON-RPC',
    transport: 'stdin / stdout',
    configFormat: 'TOML',
    defaultConfigRelativePath: '.codex/config.toml',
    npmPackage: '@openai/codex',
  );

  /// 内置 Grok CLI（ACP stdio）定义。
  static const AgentDefinition grok = AgentDefinition(
    id: grokAgentProviderId,
    displayName: 'Grok',
    vendor: 'xAI',
    commandName: 'grok',
    protocol: 'ACP JSON-RPC',
    transport: 'stdin / stdout',
    configFormat: 'TOML',
    defaultConfigRelativePath: '.grok/config.toml',
    npmPackage: '',
  );

  /// 应用当前支持的全部 Agent 定义。
  static const List<AgentDefinition> all = <AgentDefinition>[codex, grok];

  /// 按 id 查找定义；未知 id 返回 null。
  static AgentDefinition? byId(String id) {
    for (final definition in all) {
      if (definition.id == id) {
        return definition;
      }
    }
    return null;
  }
}

/// 最近一次无计费连接测试结果。
class AgentConnectionTestResult {
  const AgentConnectionTestResult({
    required this.success,
    required this.testedAt,
    required this.elapsed,
    required this.cliCallable,
    required this.accountValid,
    required this.protocolReady,
    this.failureStage,
    this.message,
    this.rawErrorSummary,
    this.protocolVersion,
    this.agentName,
    this.agentVersion,
    this.capabilitySummary = const <String>[],
    this.capabilityFingerprint,
    this.compatibilitySummary,
    this.exitReason,
  });

  final bool success;
  final DateTime testedAt;
  final Duration elapsed;
  final bool cliCallable;
  final bool accountValid;
  final bool protocolReady;
  final AgentDiagnosticStage? failureStage;
  final String? message;
  final String? rawErrorSummary;

  /// 握手诊断只保存白名单摘要，不包含原始 payload。
  final String? protocolVersion;
  final String? agentName;
  final String? agentVersion;
  final List<String> capabilitySummary;
  final String? capabilityFingerprint;
  final String? compatibilitySummary;
  final String? exitReason;
}

/// 可编辑配置文件的加载快照。
class AgentConfigurationDocument {
  const AgentConfigurationDocument({
    required this.path,
    required this.format,
    required this.content,
    required this.maskedContent,
    required this.exists,
    required this.loadedAt,
    required this.signature,
    this.modifiedAt,
  });

  final String path;
  final String format;
  final String content;
  final String maskedContent;
  final bool exists;
  final DateTime loadedAt;
  final DateTime? modifiedAt;

  /// 外部修改冲突检测使用的轻量签名，不包含任何凭证明文。
  final String signature;
}

/// 配置保存后的结果。
class AgentConfigurationSaveResult {
  const AgentConfigurationSaveResult({required this.document, this.backupPath});

  final AgentConfigurationDocument document;
  final String? backupPath;
}

/// 从 Agent 自身日志文件解析出的单行日志。
class AgentLogEntry {
  const AgentLogEntry({
    required this.id,
    required this.sourcePath,
    required this.message,
    required this.level,
    required this.timestamp,
  });

  final String id;
  final String sourcePath;
  final String message;
  final AgentLogLevel level;
  final DateTime? timestamp;
}

/// 自动检测过程的非阻塞进度。
class AgentDetectionProgress {
  const AgentDetectionProgress({
    required this.completed,
    required this.total,
    required this.message,
  });

  final int completed;
  final int total;
  final String message;
}

const Object _agentManagementUnset = Object();

/// Agent 管理页面消费的不可变聚合快照。
class ManagedAgent {
  const ManagedAgent({
    required this.definition,
    required this.installationState,
    required this.accountState,
    required this.runtimeState,
    required this.versionState,
    required this.enabled,
    required this.models,
    required this.logPaths,
    required this.timeoutSeconds,
    this.executablePath,
    this.currentVersion,
    this.latestVersion,
    this.accountLabel,
    this.lastDetectedAt,
    this.errorStage,
    this.errorMessage,
    this.errorDetails,
    this.suggestion,
    this.connectionTest,
    this.modelsUpdatedAt,
    this.modelSource,
    this.configPath,
    this.configExists = false,
    this.configModifiedAt,
  });

  factory ManagedAgent.codex({required bool enabled}) {
    return ManagedAgent.forDefinition(
      definition: AgentDefinition.codex,
      enabled: enabled,
    );
  }

  /// Grok CLI 的初始空快照。
  factory ManagedAgent.grok({required bool enabled}) {
    return ManagedAgent.forDefinition(
      definition: AgentDefinition.grok,
      enabled: enabled,
    );
  }

  /// 按定义创建初始空快照。
  factory ManagedAgent.forDefinition({
    required AgentDefinition definition,
    required bool enabled,
  }) {
    return ManagedAgent(
      definition: definition,
      installationState: AgentInstallationState.unknown,
      accountState: AgentAccountState.unknown,
      runtimeState: enabled
          ? AgentRuntimeState.notRunning
          : AgentRuntimeState.disabled,
      versionState: AgentVersionState.unknown,
      enabled: enabled,
      models: const <AgentModelInfo>[],
      logPaths: const <String>[],
      timeoutSeconds: 60,
    );
  }

  final AgentDefinition definition;
  final AgentInstallationState installationState;
  final String? executablePath;
  final String? currentVersion;
  final String? latestVersion;
  final AgentAccountState accountState;
  final String? accountLabel;
  final AgentRuntimeState runtimeState;
  final AgentVersionState versionState;
  final bool enabled;
  final DateTime? lastDetectedAt;
  final AgentDiagnosticStage? errorStage;
  final String? errorMessage;
  final String? errorDetails;
  final String? suggestion;
  final AgentConnectionTestResult? connectionTest;
  final List<AgentModelInfo> models;
  final DateTime? modelsUpdatedAt;
  final String? modelSource;
  final String? configPath;
  final bool configExists;
  final DateTime? configModifiedAt;
  final List<String> logPaths;
  final int timeoutSeconds;

  bool get installed => installationState == AgentInstallationState.installed;

  bool get updateAvailable => versionState == AgentVersionState.updateAvailable;

  bool get needsAttention {
    return installed &&
        (accountState == AgentAccountState.loggedOut ||
            accountState == AgentAccountState.expired ||
            accountState == AgentAccountState.unavailable ||
            runtimeState == AgentRuntimeState.error ||
            runtimeState == AgentRuntimeState.unavailable ||
            errorMessage != null ||
            versionState == AgentVersionState.checkFailed);
  }

  ManagedAgent copyWith({
    AgentInstallationState? installationState,
    Object? executablePath = _agentManagementUnset,
    Object? currentVersion = _agentManagementUnset,
    Object? latestVersion = _agentManagementUnset,
    AgentAccountState? accountState,
    Object? accountLabel = _agentManagementUnset,
    AgentRuntimeState? runtimeState,
    AgentVersionState? versionState,
    bool? enabled,
    Object? lastDetectedAt = _agentManagementUnset,
    Object? errorStage = _agentManagementUnset,
    Object? errorMessage = _agentManagementUnset,
    Object? errorDetails = _agentManagementUnset,
    Object? suggestion = _agentManagementUnset,
    Object? connectionTest = _agentManagementUnset,
    List<AgentModelInfo>? models,
    Object? modelsUpdatedAt = _agentManagementUnset,
    Object? modelSource = _agentManagementUnset,
    Object? configPath = _agentManagementUnset,
    bool? configExists,
    Object? configModifiedAt = _agentManagementUnset,
    List<String>? logPaths,
    int? timeoutSeconds,
  }) {
    return ManagedAgent(
      definition: definition,
      installationState: installationState ?? this.installationState,
      executablePath: identical(executablePath, _agentManagementUnset)
          ? this.executablePath
          : executablePath as String?,
      currentVersion: identical(currentVersion, _agentManagementUnset)
          ? this.currentVersion
          : currentVersion as String?,
      latestVersion: identical(latestVersion, _agentManagementUnset)
          ? this.latestVersion
          : latestVersion as String?,
      accountState: accountState ?? this.accountState,
      accountLabel: identical(accountLabel, _agentManagementUnset)
          ? this.accountLabel
          : accountLabel as String?,
      runtimeState: runtimeState ?? this.runtimeState,
      versionState: versionState ?? this.versionState,
      enabled: enabled ?? this.enabled,
      lastDetectedAt: identical(lastDetectedAt, _agentManagementUnset)
          ? this.lastDetectedAt
          : lastDetectedAt as DateTime?,
      errorStage: identical(errorStage, _agentManagementUnset)
          ? this.errorStage
          : errorStage as AgentDiagnosticStage?,
      errorMessage: identical(errorMessage, _agentManagementUnset)
          ? this.errorMessage
          : errorMessage as String?,
      errorDetails: identical(errorDetails, _agentManagementUnset)
          ? this.errorDetails
          : errorDetails as String?,
      suggestion: identical(suggestion, _agentManagementUnset)
          ? this.suggestion
          : suggestion as String?,
      connectionTest: identical(connectionTest, _agentManagementUnset)
          ? this.connectionTest
          : connectionTest as AgentConnectionTestResult?,
      models: List<AgentModelInfo>.unmodifiable(models ?? this.models),
      modelsUpdatedAt: identical(modelsUpdatedAt, _agentManagementUnset)
          ? this.modelsUpdatedAt
          : modelsUpdatedAt as DateTime?,
      modelSource: identical(modelSource, _agentManagementUnset)
          ? this.modelSource
          : modelSource as String?,
      configPath: identical(configPath, _agentManagementUnset)
          ? this.configPath
          : configPath as String?,
      configExists: configExists ?? this.configExists,
      configModifiedAt: identical(configModifiedAt, _agentManagementUnset)
          ? this.configModifiedAt
          : configModifiedAt as DateTime?,
      logPaths: List<String>.unmodifiable(logPaths ?? this.logPaths),
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
    );
  }
}

/// 配置文件在编辑期间被外部修改。
class AgentConfigurationConflictException implements Exception {
  const AgentConfigurationConflictException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 配置文件校验失败。
class AgentConfigurationValidationException implements Exception {
  const AgentConfigurationValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}
