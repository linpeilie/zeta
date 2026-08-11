import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:zeta/src/features/agent/data/codex_cli_locator.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_process_starter.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/stream_json_peer.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent_management/data/cli_process_runner.dart';
import 'package:zeta/src/features/agent_management/domain/agent_cli_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';

/// Claude Code CLI 命令执行入口；测试可记录 detect 是否只调用 `--version`。
typedef ClaudeCodeCliProcessRun =
    Future<CliProcessResult> Function(
      ResolvedCliCommand command,
      List<String> arguments, {
      Duration timeout,
      Map<String, String>? environment,
    });

/// 用户显式点击“测试连接”后才允许调用的 stream-json 握手入口。
typedef ClaudeCodeConnectionProbe =
    Future<ClaudeCodeConnectionProbeResult> Function(
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

/// 一次显式连接测试的白名单握手摘要。
final class ClaudeCodeConnectionProbeResult {
  const ClaudeCodeConnectionProbeResult({
    required this.success,
    this.message,
    this.cliVersion,
    this.model,
  });

  final bool success;
  final String? message;
  final String? cliVersion;
  final String? model;
}

/// 短连接测试的握手收敛器：只有同一 session 的 init 与 result 才成功。
final class ClaudeCodeConnectionHandshake {
  ClaudeCodeConnectionHandshake({required this.expectedSessionId});

  final String expectedSessionId;
  bool _initialized = false;
  String? _cliVersion;
  String? _model;

  /// 吸收一帧；握手尚未完成时返回 null。
  ClaudeCodeConnectionProbeResult? accept(StreamJsonEvent event) {
    if (event.type == 'system' && event.subtype == 'init') {
      final observedSessionId = _nonEmptyString(event.raw['session_id']);
      if (observedSessionId != expectedSessionId) {
        return const ClaudeCodeConnectionProbeResult(
          success: false,
          message: 'Claude Code 返回了不同的会话标识。',
        );
      }
      _initialized = true;
      _cliVersion = _nonEmptyString(event.raw['claude_code_version']);
      _model = _nonEmptyString(event.raw['model']);
      return null;
    }
    if (event.type != 'result') {
      return null;
    }
    final succeeded = _initialized && event.subtype == 'success';
    return ClaudeCodeConnectionProbeResult(
      success: succeeded,
      message: succeeded
          ? 'Claude Code 连接正常'
          : 'Claude Code 未完成有效的 stream-json 握手。',
      cliVersion: _cliVersion,
      model: _model,
    );
  }
}

/// Claude Code CLI 的检测、连接测试与日志路径仓库。
///
/// 自动 [detect] 只执行 `--version`、stat/mtime 与日志路径枚举，不启动
/// stream-json peer；只有用户显式调用 [testConnection] 才进行最小模型握手。
class ClaudeCodeAgentManagementRepository
    implements AgentCliManagementRepository {
  ClaudeCodeAgentManagementRepository({
    ClaudeCodeCliProcessRun? processRunner,
    ClaudeCodeConnectionProbe? connectionProbe,
    ClaudeCodeMetadataFileSystem? fileSystem,
    DateTime Function()? now,
    String Function()? claudeHomeProvider,
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
       _connectionProbe = connectionProbe ?? _probeClaudeCodeConnection,
       _fileSystem = fileSystem ?? const IoClaudeCodeMetadataFileSystem(),
       _now = now ?? DateTime.now,
       _claudeHomeProvider = claudeHomeProvider ?? _defaultClaudeHome;

  static const Duration _versionTimeout = Duration(seconds: 10);
  static const Duration _connectionTimeout = Duration(seconds: 20);

  final ClaudeCodeCliProcessRun _processRunner;
  final ClaudeCodeConnectionProbe _connectionProbe;
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

    publish(0, '正在检测 Claude Code CLI');
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
        errorMessage: '未找到 Claude Code CLI',
        suggestion: '请先安装 Claude Code，并确认 claude 已加入 PATH。',
      );
      publish(total, '未找到 Claude Code');
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
          : '请确认 Claude Code CLI 可以正常执行 `claude --version`。',
    );
    publish(1, '已检测 Claude Code 版本');

    final account = await _readAccountStatus();
    current = current.copyWith(
      accountState: account.state,
      accountLabel: account.label,
      errorStage: account.error == null
          ? current.errorStage
          : AgentDiagnosticStage.accountAuthentication,
      errorMessage: account.error ?? current.errorMessage,
      suggestion: account.state == AgentAccountState.loggedOut
          ? '请在终端运行 `claude login` 后重新检测。'
          : account.error == null
          ? current.suggestion
          : '请检查 Claude Code 登录状态文件是否可访问。',
    );
    publish(2, '已检测 Claude Code 登录状态');

    final config = await _fileSystem.stat(configPath);
    final logs = await discoverLogPaths();
    current = current.copyWith(
      configExists: config.exists && config.isFile,
      configModifiedAt: config.modifiedAt,
      logPaths: logs,
      lastDetectedAt: _now(),
    );
    publish(total, 'Claude Code 检测完成');
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
          message: '未找到 Claude Code CLI',
        ),
        const <AgentModelInfo>[],
      );
    }

    final account = await _readAccountStatus();
    if (account.state != AgentAccountState.loggedIn) {
      stopwatch.stop();
      return (
        AgentConnectionTestResult(
          success: false,
          testedAt: testedAt,
          elapsed: stopwatch.elapsed,
          cliCallable: true,
          accountValid: false,
          protocolReady: false,
          failureStage: AgentDiagnosticStage.accountAuthentication,
          message: '未检测到 Claude Code 登录状态，请先运行 `claude login`。',
          agentVersion: version.version,
        ),
        const <AgentModelInfo>[],
      );
    }

    try {
      final probe = await _connectionProbe(
        providerConfig,
        timeout: _connectionTimeout,
      );
      stopwatch.stop();
      return (
        AgentConnectionTestResult(
          success: probe.success,
          testedAt: testedAt,
          elapsed: stopwatch.elapsed,
          cliCallable: true,
          accountValid: true,
          protocolReady: probe.success,
          failureStage: probe.success
              ? null
              : AgentDiagnosticStage.protocolHandshake,
          message:
              probe.message ??
              (probe.success ? 'Claude Code 连接正常' : 'Claude Code 握手失败'),
          protocolVersion: 'stream-json',
          agentName: 'Claude Code',
          agentVersion: probe.cliVersion ?? version.version,
          capabilitySummary: const <String>['stream-json', 'session-resume'],
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
          accountValid: true,
          protocolReady: false,
          failureStage: AgentDiagnosticStage.protocolHandshake,
          message: 'Claude Code 连接测试在 20 秒内未完成。',
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
          accountValid: true,
          protocolReady: false,
          failureStage: AgentDiagnosticStage.protocolHandshake,
          message: 'Claude Code 连接测试失败。',
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
    final command = _resolvedCommand(providerConfig);
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
          error: 'Claude Code 版本检测失败。',
        );
      }
      final match = RegExp(
        r'\b(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)\b',
      ).firstMatch(result.combinedOutput);
      if (match == null) {
        return _ClaudeCodeVersionRead(
          cliCallable: true,
          displayPath: command.displayPath,
          error: '无法识别 Claude Code 版本。',
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
        error: 'Claude Code 版本检测失败。',
      );
    }
  }

  Future<_ClaudeCodeAccountRead> _readAccountStatus() async {
    try {
      for (final name in const <String>['.credentials.json', 'oauth.json']) {
        final metadata = await _fileSystem.stat(
          _join(_claudeHomeProvider(), name),
        );
        if (metadata.exists && metadata.isFile) {
          return const _ClaudeCodeAccountRead(
            state: AgentAccountState.loggedIn,
            label: '已检测到 Claude Code 登录状态',
          );
        }
      }
      return const _ClaudeCodeAccountRead(
        state: AgentAccountState.loggedOut,
        label: '未检测到 Claude Code 登录状态',
      );
    } catch (_) {
      return const _ClaudeCodeAccountRead(
        state: AgentAccountState.unavailable,
        error: '无法检查 Claude Code 登录状态。',
      );
    }
  }
}

/// 路径 basename 是否像 Claude Code CLI（`claude` / `claude.exe` 等）。
bool looksLikeClaudeCodeCliPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  final base = (slash >= 0 ? normalized.substring(slash + 1) : normalized)
      .toLowerCase();
  return base == 'claude' || base.startsWith('claude.');
}

ResolvedCliCommand _resolvedCommand(AgentProviderConfig config) {
  final configuredPath = config.extra['cliPath'];
  final preferred = configuredPath is String && configuredPath.trim().isNotEmpty
      ? configuredPath.trim()
      : config.command.trim().isEmpty
      ? AgentProviderConfig.defaultClaudeCode.command
      : config.command.trim();
  if (!Platform.isWindows) {
    return ResolvedCliCommand(displayPath: preferred, executable: preferred);
  }
  final lower = preferred.toLowerCase();
  if (lower.endsWith('.cmd') || lower.endsWith('.bat')) {
    return ResolvedCliCommand(
      displayPath: preferred,
      executable: 'cmd.exe',
      prefixArguments: <String>['/d', '/s', '/c', preferred],
    );
  }
  if (lower.endsWith('.ps1')) {
    return ResolvedCliCommand(
      displayPath: preferred,
      executable: 'powershell.exe',
      prefixArguments: <String>[
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-File',
        preferred,
      ],
    );
  }
  return ResolvedCliCommand(displayPath: preferred, executable: preferred);
}

Future<ClaudeCodeConnectionProbeResult> _probeClaudeCodeConnection(
  AgentProviderConfig providerConfig, {
  required Duration timeout,
}) async {
  final sessionId = _randomSessionId();
  final directory = await Directory.systemTemp.createTemp(
    'zeta-claude-connection-',
  );
  StreamJsonPeer? peer;
  StreamSubscription<StreamJsonEvent>? eventSubscription;
  StreamSubscription<StreamJsonProtocolException>? errorSubscription;
  try {
    final command = await resolveClaudeCodeProcessCommand(
      providerConfig,
      sessionId: sessionId,
      permissionPromptTool: null,
      noSessionPersistence: true,
    );
    peer = StreamJsonPeer(
      command: command.executable,
      arguments: command.arguments,
      workingDirectory: directory.path,
      environment: providerConfig.environment,
    );
    final completion = Completer<ClaudeCodeConnectionProbeResult>();
    final handshake = ClaudeCodeConnectionHandshake(
      expectedSessionId: sessionId,
    );
    eventSubscription = peer.events.listen(
      (event) {
        if (completion.isCompleted) {
          return;
        }
        final result = handshake.accept(event);
        if (result != null) {
          completion.complete(result);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completion.isCompleted) {
          completion.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!completion.isCompleted) {
          completion.complete(
            const ClaudeCodeConnectionProbeResult(
              success: false,
              message: 'Claude Code 进程在握手完成前退出。',
            ),
          );
        }
      },
    );
    errorSubscription = peer.protocolErrors.listen((_) {
      if (!completion.isCompleted) {
        completion.complete(
          const ClaudeCodeConnectionProbeResult(
            success: false,
            message: 'Claude Code 返回了无效的 stream-json 数据。',
          ),
        );
      }
    });
    await peer.start();
    await peer.send(<String, Object?>{
      'type': 'user',
      'session_id': sessionId,
      'parent_tool_use_id': null,
      'message': <String, Object?>{
        'role': 'user',
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': 'Reply with OK only.'},
        ],
      },
    });
    return await completion.future.timeout(timeout);
  } finally {
    await eventSubscription?.cancel();
    await errorSubscription?.cancel();
    await peer?.close();
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } on FileSystemException {
      // 临时探测目录由系统后续清理；不影响连接结果。
    }
  }
}

String _randomSessionId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
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

String? _nonEmptyString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
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
