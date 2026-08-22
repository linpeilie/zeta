import 'dart:async';
import 'dart:io';

import 'package:zeta/src/features/agent/data/claude_code_cli_locator.dart';
import 'package:zeta/src/features/agent/data/cli_command_locator.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_cli_metadata_probe.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent_management/data/claude_code_auth_status_probe.dart';
import 'package:zeta/src/features/agent_management/data/cli_process_runner.dart';
import 'package:zeta/src/features/agent_management/domain/agent_cli_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_text_catalog.dart';
import 'package:zeta/src/features/agent_management/domain/fallback_agent_management_text_catalog.dart';

/// Claude Code 版本命令执行入口；认证证据由独立 probe 负责。
typedef ClaudeCodeCliProcessRun =
    Future<CliProcessResult> Function(
      ResolvedCliCommand command,
      List<String> arguments, {
      Duration timeout,
      Map<String, String>? environment,
    });

/// 用户显式点击“测试连接”后才允许调用的无 Prompt initialize 入口。
typedef ClaudeCodeConnectionProbe =
    Future<void> Function(
      AgentProviderConfig providerConfig, {
      required Duration timeout,
    });

/// stat/list 所需的最小 metadata，刻意不提供读取文件内容的 API。
final class ClaudeCodeFileMetadata {
  const ClaudeCodeFileMetadata({
    required this.exists,
    this.isFile = false,
    this.modifiedAt,
  });

  const ClaudeCodeFileMetadata.missing()
    : exists = false,
      isFile = false,
      modifiedAt = null;

  final bool exists;
  final bool isFile;
  final DateTime? modifiedAt;
}

/// Claude detect 的文件系统窄接口：账号阶段只能 stat，日志阶段只能列路径。
abstract interface class ClaudeCodeMetadataFileSystem {
  Future<ClaudeCodeFileMetadata> stat(String path);

  Future<List<String>> listLogFiles(String directoryPath);
}

/// `dart:io` metadata 实现，不读取凭证或日志正文。
final class IoClaudeCodeMetadataFileSystem
    implements ClaudeCodeMetadataFileSystem {
  const IoClaudeCodeMetadataFileSystem();

  @override
  Future<ClaudeCodeFileMetadata> stat(String path) async {
    final result = await FileStat.stat(path);
    if (result.type == FileSystemEntityType.notFound) {
      return const ClaudeCodeFileMetadata.missing();
    }
    return ClaudeCodeFileMetadata(
      exists: true,
      isFile: result.type == FileSystemEntityType.file,
      modifiedAt: result.modified,
    );
  }

  @override
  Future<List<String>> listLogFiles(String directoryPath) async {
    final paths = <String>[];
    try {
      await for (final entity in Directory(
        directoryPath,
      ).list(followLinks: false)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.log')) {
          paths.add(entity.path);
        }
      }
    } on FileSystemException {
      return const <String>[];
    }
    paths.sort();
    return List<String>.unmodifiable(paths);
  }
}

/// Claude Code CLI 的检测、连接测试与日志路径仓库。
///
/// 自动 [detect] 只执行 `--version`、`auth status --json` 与日志路径枚举，不启动
/// stream-json peer；只有用户显式调用 [testConnection] 才验证 CLI 实际可用性。
/// 认证证据与 CLI 可用性是两个独立结果。
class ClaudeCodeAgentManagementRepository
    implements AgentCliManagementRepository {
  ClaudeCodeAgentManagementRepository({
    ClaudeCodeCliProcessRun? processRunner,
    ClaudeCodeAuthStatusLoader? authStatusLoader,
    ClaudeCodeConnectionProbe? connectionProbe,
    ClaudeCodeCliLocator? locator,
    ClaudeCodeMetadataFileSystem? fileSystem,
    DateTime Function()? now,
    String Function()? claudeHomeProvider,
    AgentManagementTextCatalog? textCatalog,
  }) : _processRunner =
           processRunner ??
           ((command, arguments, {timeout = _versionTimeout, environment}) {
             return const CliProcessRunner().run(
               command,
               arguments,
               timeout: timeout,
               environment: environment,
             );
           }),
       _connectionProbe =
           connectionProbe ??
           ((providerConfig, {required timeout}) async {
             await ClaudeCodeCliMetadataProbe(
               config: providerConfig,
               timeout: timeout,
               locator: locator,
             ).probe();
           }),
       _authStatusLoader =
           authStatusLoader ??
           ClaudeCodeAuthStatusProbe(locator: locator).probe,
       _locator = locator ?? const ClaudeCodeCliLocator(),
       _fileSystem = fileSystem ?? const IoClaudeCodeMetadataFileSystem(),
       _now = now ?? DateTime.now,
       _claudeHomeProvider = claudeHomeProvider ?? _defaultClaudeHome,
       _textCatalog = textCatalog ?? const FallbackAgentManagementTextCatalog();

  final AgentManagementTextCatalog _textCatalog;

  static const Duration _versionTimeout = Duration(seconds: 10);
  static const Duration _connectionTimeout = Duration(seconds: 20);

  final ClaudeCodeCliProcessRun _processRunner;
  final ClaudeCodeConnectionProbe _connectionProbe;
  final ClaudeCodeAuthStatusLoader _authStatusLoader;
  final ClaudeCodeCliLocator _locator;
  final ClaudeCodeMetadataFileSystem _fileSystem;
  final DateTime Function() _now;
  final String Function() _claudeHomeProvider;

  @override
  String get agentId => AgentDefinition.claudeCode.id;

  @override
  Future<ManagedAgent> detect({
    required AgentProviderConfig providerConfig,
    required bool enabled,
    AgentDetectionProgressCallback? onProgress,
  }) async {
    const total = 3;
    var current = ManagedAgent.claudeCode(enabled: enabled).copyWith(
      installationState: AgentInstallationState.detecting,
      accountState: AgentAccountState.checking,
      versionState: AgentVersionState.checking,
      configPath: configPath,
    );

    void publish(int completed, String message) {
      onProgress?.call(
        AgentDetectionProgress(
          completed: completed,
          total: total,
          message: message,
        ),
        current,
      );
    }

    publish(0, _textCatalog.locatingClaudeCodeCli());
    final version = await _readVersion(providerConfig);
    if (!version.cliCallable) {
      current = current.copyWith(
        installationState: AgentInstallationState.notInstalled,
        accountState: AgentAccountState.unknown,
        runtimeState: enabled
            ? AgentRuntimeState.unavailable
            : AgentRuntimeState.disabled,
        versionState: AgentVersionState.unknown,
        logPaths: await discoverLogPaths(),
        lastDetectedAt: _now(),
        errorStage: AgentDiagnosticStage.fileDetection,
        errorMessage: _textCatalog.notFoundClaudeCodeCli(),
        suggestion: _textCatalog.installClaudeCodeAndAddToPath(),
      );
      publish(total, _textCatalog.notFound('Claude Code'));
      return current;
    }

    current = current.copyWith(
      installationState: AgentInstallationState.installed,
      executablePath: version.displayPath,
      currentVersion: version.version,
      versionState: version.version == null
          ? AgentVersionState.checkFailed
          : AgentVersionState.current,
      runtimeState: enabled
          ? AgentRuntimeState.notRunning
          : AgentRuntimeState.disabled,
      errorStage: version.error == null
          ? null
          : AgentDiagnosticStage.versionDetection,
      errorMessage: version.error,
      suggestion: version.error == null
          ? null
          : _textCatalog.confirmClaudeVersionCommand(),
    );
    publish(1, _textCatalog.claudeVersionDetected());

    final account = await _readAccountStatus(providerConfig);
    current = current.copyWith(
      accountState: account.state,
      accountLabel: account.label,
      errorStage: account.error == null
          ? current.errorStage
          : AgentDiagnosticStage.accountAuthentication,
      errorMessage: account.error ?? current.errorMessage,
      suggestion: account.state == AgentAccountState.loggedOut
          ? _textCatalog.noClaudeLoginEvidenceSuggestion()
          : account.error == null
          ? current.suggestion
          : _textCatalog.confirmClaudeAuthStatusJson(),
    );
    publish(2, _textCatalog.claudeAuthDetected());

    final config = await _fileSystem.stat(configPath);
    final logs = await discoverLogPaths();
    current = current.copyWith(
      configExists: config.exists && config.isFile,
      configModifiedAt: config.modifiedAt,
      logPaths: logs,
      lastDetectedAt: _now(),
    );
    publish(total, _textCatalog.detectionComplete('Claude Code'));
    return current;
  }

  @override
  Future<(AgentConnectionTestResult, List<AgentModelInfo>)> testConnection({
    required AgentProviderConfig providerConfig,
  }) async {
    final testedAt = _now();
    final stopwatch = Stopwatch()..start();
    final version = await _readVersion(providerConfig);
    if (!version.cliCallable) {
      stopwatch.stop();
      return (
        AgentConnectionTestResult(
          success: false,
          testedAt: testedAt,
          elapsed: stopwatch.elapsed,
          cliCallable: false,
          accountValid: false,
          protocolReady: false,
          failureStage: AgentDiagnosticStage.fileDetection,
          message: _textCatalog.notFoundClaudeCodeCli(),
        ),
        const <AgentModelInfo>[],
      );
    }

    try {
      await _connectionProbe(providerConfig, timeout: _connectionTimeout);
      stopwatch.stop();
      return (
        AgentConnectionTestResult(
          success: true,
          testedAt: testedAt,
          elapsed: stopwatch.elapsed,
          cliCallable: true,
          accountValid: true,
          protocolReady: true,
          message: _textCatalog.claudeInitializeSuccess(),
          protocolVersion: 'stream-json',
          agentName: 'Claude Code',
          agentVersion: version.version,
          capabilitySummary: const <String>['stream-json initialize'],
        ),
        const <AgentModelInfo>[],
      );
    } on ClaudeCodeCliMetadataProbeException catch (error) {
      stopwatch.stop();
      return (
        AgentConnectionTestResult(
          success: false,
          testedAt: testedAt,
          elapsed: stopwatch.elapsed,
          cliCallable: true,
          accountValid: false,
          protocolReady: false,
          failureStage: AgentDiagnosticStage.protocolHandshake,
          message: _metadataProbeFailureMessage(error.failure, _textCatalog),
          agentVersion: version.version,
        ),
        const <AgentModelInfo>[],
      );
    } on TimeoutException {
      stopwatch.stop();
      return (
        AgentConnectionTestResult(
          success: false,
          testedAt: testedAt,
          elapsed: stopwatch.elapsed,
          cliCallable: true,
          accountValid: false,
          protocolReady: false,
          failureStage: AgentDiagnosticStage.protocolHandshake,
          message: _textCatalog.claudeInitializeTimeout(),
          agentVersion: version.version,
        ),
        const <AgentModelInfo>[],
      );
    } catch (_) {
      stopwatch.stop();
      return (
        AgentConnectionTestResult(
          success: false,
          testedAt: testedAt,
          elapsed: stopwatch.elapsed,
          cliCallable: true,
          accountValid: false,
          protocolReady: false,
          failureStage: AgentDiagnosticStage.protocolHandshake,
          message: _textCatalog.claudeInitializeFailed(),
          agentVersion: version.version,
        ),
        const <AgentModelInfo>[],
      );
    }
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
  String get configPath => _join(_claudeHomeProvider(), 'settings.json');

  @override
  Future<AgentConfigurationDocument> readConfiguration() async {
    final metadata = await _fileSystem.stat(configPath);
    final now = _now();
    return AgentConfigurationDocument(
      path: configPath,
      format: 'JSON',
      content: '',
      maskedContent: '',
      exists: metadata.exists && metadata.isFile,
      loadedAt: now,
      modifiedAt: metadata.modifiedAt,
      signature: metadata.exists
          ? 'metadata:${metadata.modifiedAt?.microsecondsSinceEpoch ?? 0}'
          : 'missing',
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
  Future<List<String>> discoverLogPaths() {
    return _fileSystem.listLogFiles(_join(_claudeHomeProvider(), 'logs'));
  }

  @override
  Future<List<AgentLogEntry>> readLogs(
    List<String> paths, {
    int maxLines = 1000,
  }) async => const <AgentLogEntry>[];

  Future<_ClaudeCodeVersionRead> _readVersion(
    AgentProviderConfig providerConfig,
  ) async {
    final command = await _locator.locate(providerConfig);
    final displayPath = _preferredClaudeCodePath(providerConfig);
    if (command == null) {
      return _ClaudeCodeVersionRead(
        cliCallable: false,
        displayPath: displayPath,
      );
    }
    try {
      final result = await _processRunner(
        command,
        const <String>['--version'],
        timeout: _versionTimeout,
        environment: providerConfig.environment,
      );
      if (!result.succeeded) {
        return _ClaudeCodeVersionRead(
          cliCallable: true,
          displayPath: command.displayPath,
          error: _textCatalog.versionDetectFailed('Claude Code'),
        );
      }
      final match = RegExp(
        r'\b(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)\b',
      ).firstMatch(result.combinedOutput);
      if (match == null) {
        return _ClaudeCodeVersionRead(
          cliCallable: true,
          displayPath: command.displayPath,
          error: _textCatalog.cannotIdentifyVersion('Claude Code'),
        );
      }
      return _ClaudeCodeVersionRead(
        cliCallable: true,
        displayPath: command.displayPath,
        version: match.group(1),
      );
    } on ProcessException {
      return _ClaudeCodeVersionRead(
        cliCallable: false,
        displayPath: command.displayPath,
      );
    } on FileSystemException {
      return _ClaudeCodeVersionRead(
        cliCallable: false,
        displayPath: command.displayPath,
      );
    } catch (_) {
      return _ClaudeCodeVersionRead(
        cliCallable: true,
        displayPath: command.displayPath,
        error: _textCatalog.versionDetectFailed('Claude Code'),
      );
    }
  }

  Future<_ClaudeCodeAccountRead> _readAccountStatus(
    AgentProviderConfig providerConfig,
  ) async {
    try {
      final status = await _authStatusLoader(providerConfig);
      if (status != null) {
        return _mapAuthStatus(status, _textCatalog);
      }
    } catch (_) {
      // 统一折叠为不可用，不依据凭据文件名猜测账号状态。
    }
    return _ClaudeCodeAccountRead(
      state: AgentAccountState.unavailable,
      label: _textCatalog.claudeLoginEvidenceUnavailable(),
      error: _textCatalog.cannotCheckClaudeAuth(),
    );
  }
}

String _metadataProbeFailureMessage(
  ClaudeCodeCliMetadataProbeFailure failure,
  AgentManagementTextCatalog catalog,
) {
  return switch (failure) {
    ClaudeCodeCliMetadataProbeFailure.processUnavailable =>
      catalog.cannotStartClaudeInitialize(),
    ClaudeCodeCliMetadataProbeFailure.timeout =>
      catalog.claudeInitializeTimeout(),
    ClaudeCodeCliMetadataProbeFailure.processExited =>
      catalog.claudeInitializeProcessExited(),
    ClaudeCodeCliMetadataProbeFailure.errorResponse =>
      catalog.claudeInitializeRejected(),
    ClaudeCodeCliMetadataProbeFailure.invalidResponse =>
      catalog.claudeInitializeInvalidResponse(),
    ClaudeCodeCliMetadataProbeFailure.invalidStream =>
      catalog.claudeInitializeInvalidStream(),
    ClaudeCodeCliMetadataProbeFailure.transportFailure =>
      catalog.claudeInitializeCommunicationFailed(),
  };
}

_ClaudeCodeAccountRead _mapAuthStatus(
  ClaudeCodeAuthStatusSnapshot status,
  AgentManagementTextCatalog catalog,
) {
  if (!status.loggedIn) {
    return _ClaudeCodeAccountRead(
      state: AgentAccountState.loggedOut,
      label: catalog.noClaudeLoginEvidenceLabel(),
    );
  }

  final authMethod = status.authMethod?.trim().toLowerCase();
  final label = switch (authMethod) {
    'claude.ai' => _claudeAiAccountLabel(status.subscriptionType, catalog),
    'api_key' => catalog.claudeAuthViaApiKey(),
    'api_key_helper' => catalog.claudeAuthViaApiKeyHelper(),
    'oauth_token' => catalog.claudeAuthViaOauthToken(),
    'third_party' => _thirdPartyAccountLabel(status.apiProvider, catalog),
    _ => catalog.claudeAuthPathDetected(),
  };
  return _ClaudeCodeAccountRead(
    state: AgentAccountState.loggedIn,
    label: label,
  );
}

String _claudeAiAccountLabel(
  String? subscriptionType,
  AgentManagementTextCatalog catalog,
) {
  final plan = switch (subscriptionType?.trim().toLowerCase()) {
    'pro' || 'claude pro' => 'Claude Pro',
    'max' || 'claude max' => 'Claude Max',
    'team' || 'claude team' => 'Claude Team',
    'enterprise' || 'claude enterprise' => 'Claude Enterprise',
    _ => null,
  };
  return plan == null
      ? catalog.claudeAiLoggedIn()
      : catalog.claudeAiLoggedInAs(plan);
}

String _thirdPartyAccountLabel(
  String? apiProvider,
  AgentManagementTextCatalog catalog,
) {
  final provider = switch (apiProvider?.trim().toLowerCase()) {
    'bedrock' => 'Amazon Bedrock',
    'vertex' => 'Google Vertex AI',
    'foundry' => 'Microsoft Foundry',
    'gemini' => 'Gemini',
    'grok' => 'Grok',
    'openai' => 'OpenAI',
    _ => null,
  };
  return provider == null
      ? catalog.thirdPartyApiProviderConfigured()
      : catalog.configuredProvider(provider);
}

String _preferredClaudeCodePath(AgentProviderConfig config) {
  final configuredPath = config.extra['cliPath'];
  return configuredPath is String && configuredPath.trim().isNotEmpty
      ? configuredPath.trim()
      : config.command.trim().isEmpty
      ? AgentProviderConfig.defaultClaudeCode.command
      : config.command.trim();
}

String _defaultClaudeHome() {
  final environment = Platform.environment;
  final home = environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
  if (home == null || home.trim().isEmpty) {
    return '.claude';
  }
  return _join(home, '.claude');
}

String _join(String parent, String child) {
  if (parent.endsWith(Platform.pathSeparator)) {
    return '$parent$child';
  }
  return '$parent${Platform.pathSeparator}$child';
}

final class _ClaudeCodeVersionRead {
  const _ClaudeCodeVersionRead({
    required this.cliCallable,
    required this.displayPath,
    this.version,
    this.error,
  });

  final bool cliCallable;
  final String displayPath;
  final String? version;
  final String? error;
}

final class _ClaudeCodeAccountRead {
  const _ClaudeCodeAccountRead({required this.state, this.label, this.error});

  final AgentAccountState state;
  final String? label;
  final String? error;
}
