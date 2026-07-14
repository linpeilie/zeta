import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:zeta/src/features/agent/data/codex_cli_locator.dart';
import 'package:zeta/src/features/agent/data/cursor_cli_locator.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/cursor_acp_agent_provider.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/cursor_diagnostics_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent_management/data/cli_process_runner.dart';
import 'package:zeta/src/features/agent_management/data/codex_agent_management_repository.dart'
    show maskSensitiveConfiguration, redactLogLine;
import 'package:zeta/src/features/agent_management/domain/agent_cli_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';

typedef CursorCliProcessRun =
    Future<CliProcessResult> Function(
      ResolvedCliCommand command,
      List<String> arguments, {
      Duration timeout,
      Map<String, String>? environment,
    });

typedef CursorAcpHandshakeProbe =
    Future<void> Function(AgentProviderConfig config, String workspacePath);

/// Cursor CLI 的安装、身份、账号与无计费 ACP 握手检测。
class CursorAgentManagementRepository implements AgentCliManagementRepository {
  CursorAgentManagementRepository({
    CursorCliLocator? locator,
    CursorCliProcessRun? processRunner,
    CursorAcpHandshakeProbe? handshakeProbe,
    DateTime Function()? now,
    String Function()? cursorHomeProvider,
    CursorDiagnosticsStore? diagnosticsStore,
  }) : _locator = locator ?? const CursorCliLocator(),
       _processRunner =
           processRunner ??
           ((
             command,
             arguments, {
             timeout = const Duration(seconds: 30),
             environment,
           }) {
             return const CliProcessRunner().run(
               command,
               arguments,
               timeout: timeout,
               environment: environment,
             );
           }),
       _handshakeProbe =
           handshakeProbe ??
           ((config, workspacePath) => _defaultHandshakeProbe(
             config,
             workspacePath,
             diagnosticsStore ?? CursorDiagnosticsStore.shared,
           )),
       _now = now ?? DateTime.now,
       _cursorHomeProvider = cursorHomeProvider ?? _defaultCursorHome,
       _diagnostics = diagnosticsStore ?? CursorDiagnosticsStore.shared;

  final CursorCliLocator _locator;
  final CursorCliProcessRun _processRunner;
  final CursorAcpHandshakeProbe _handshakeProbe;
  final DateTime Function() _now;
  final String Function() _cursorHomeProvider;
  final CursorDiagnosticsStore _diagnostics;

  @override
  String get agentId => cursorAgentProviderId;

  @override
  Future<ManagedAgent> detect({
    required AgentProviderConfig providerConfig,
    required bool enabled,
    AgentDetectionProgressCallback? onProgress,
  }) async {
    const total = 5;
    var current = ManagedAgent.cursor(enabled: enabled).copyWith(
      installationState: AgentInstallationState.detecting,
      accountState: AgentAccountState.checking,
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

    publish(0, '正在定位并校验 Cursor CLI 身份');
    final resolved = await _locator.locate(providerConfig);
    if (resolved == null) {
      current = current.copyWith(
        installationState: AgentInstallationState.notInstalled,
        accountState: AgentAccountState.unavailable,
        versionState: AgentVersionState.unknown,
        lastDetectedAt: _now(),
        errorStage: AgentDiagnosticStage.fileDetection,
        errorMessage: '未找到通过身份校验且支持 ACP 的 Cursor CLI。',
        suggestion: '请安装 Cursor CLI，或检查 PATH 中的同名 agent 命令冲突。',
      );
      publish(total, 'Cursor CLI 不可用');
      return current;
    }
    current = current.copyWith(
      installationState: AgentInstallationState.installed,
      executablePath: resolved.displayPath,
      currentVersion: resolved.identity.version,
      versionState: resolved.identity.version == null
          ? AgentVersionState.unknown
          : AgentVersionState.current,
    );
    final cachedVersion = providerConfig.extra['detectedCurrentVersion']
        ?.toString();
    final versionChanged =
        cachedVersion != null &&
        resolved.identity.version != null &&
        cachedVersion != resolved.identity.version;
    if (versionChanged) {
      _diagnostics.record(
        source: CursorDiagnosticsStore.runtimeSource,
        message:
            'compatibility warning; CLI version changed from '
            '$cachedVersion to ${resolved.identity.version}; run detection again',
        level: CursorDiagnosticLevel.warning,
      );
    }
    publish(1, 'Cursor CLI 身份已确认');
    publish(2, '版本信息已读取');

    final account = await _readAccountStatus(
      resolved.command,
      environment: providerConfig.environment,
    );
    current = current.copyWith(
      accountState: account.state,
      accountLabel: account.label,
      errorStage: account.failureStage,
      errorMessage: account.error,
      errorDetails: account.details,
      suggestion: account.suggestion,
    );
    publish(3, 'Cursor 账号状态已检查');

    final effective = _providerConfig(
      providerConfig,
      resolved,
      timeoutSeconds: _timeoutSeconds(providerConfig),
    );
    final connection = await _probeConnection(effective);
    current = current.copyWith(
      connectionTest: connection,
      runtimeState: !enabled
          ? AgentRuntimeState.disabled
          : connection.success
          ? AgentRuntimeState.idle
          : AgentRuntimeState.error,
      errorStage: connection.success
          ? current.errorStage
          : connection.failureStage,
      errorMessage: connection.success
          ? current.errorMessage
          : connection.message,
      errorDetails: connection.success
          ? current.errorDetails
          : connection.rawErrorSummary,
      suggestion: connection.success
          ? versionChanged
                ? '检测到 Cursor CLI 版本变化；ACP 能力已重新检测，请复核后继续使用。'
                : _capabilityChangeSuggestion(providerConfig, connection)
          : '请先运行 agent login，并确认 `agent help acp` 可用。',
    );
    publish(4, connection.success ? 'ACP 握手成功' : 'ACP 握手失败');

    final configFile = File(configPath);
    final configExists = await configFile.exists();
    current = current.copyWith(
      configExists: configExists,
      configModifiedAt: configExists
          ? (await configFile.stat()).modified
          : null,
      logPaths: await discoverLogPaths(),
      lastDetectedAt: _now(),
    );
    publish(total, 'Cursor 检测完成');
    return current;
  }

  @override
  Future<(AgentConnectionTestResult, List<AgentModelInfo>)> testConnection({
    required AgentProviderConfig providerConfig,
  }) async {
    final startedAt = _now();
    final stopwatch = Stopwatch()..start();
    final resolved = await _locator.locate(providerConfig);
    if (resolved == null) {
      stopwatch.stop();
      return (
        AgentConnectionTestResult(
          success: false,
          testedAt: startedAt,
          elapsed: stopwatch.elapsed,
          cliCallable: false,
          accountValid: false,
          protocolReady: false,
          failureStage: AgentDiagnosticStage.fileDetection,
          message: '未找到有效的 Cursor CLI，或 agent 命令身份冲突。',
        ),
        const <AgentModelInfo>[],
      );
    }
    final account = await _readAccountStatus(
      resolved.command,
      environment: providerConfig.environment,
    );
    final effective = _providerConfig(
      providerConfig,
      resolved,
      timeoutSeconds: _timeoutSeconds(providerConfig),
    );
    final result = await _probeConnection(effective, startedAt: startedAt);
    stopwatch.stop();
    return (
      AgentConnectionTestResult(
        success: result.success,
        testedAt: startedAt,
        elapsed: stopwatch.elapsed,
        cliCallable: true,
        accountValid: account.state == AgentAccountState.loggedIn,
        protocolReady: result.protocolReady,
        failureStage: result.success
            ? null
            : account.state == AgentAccountState.loggedIn
            ? result.failureStage
            : AgentDiagnosticStage.accountAuthentication,
        message: result.success
            ? 'Cursor ACP 连接正常'
            : account.error ?? result.message,
        rawErrorSummary: result.rawErrorSummary,
        protocolVersion: result.protocolVersion,
        agentName: result.agentName,
        agentVersion: result.agentVersion,
        capabilitySummary: result.capabilitySummary,
        capabilityFingerprint: result.capabilityFingerprint,
        exitReason: result.exitReason,
      ),
      const <AgentModelInfo>[],
    );
  }

  @override
  Future<AgentProviderConfig> providerConfigForPath({
    required AgentProviderConfig current,
    required String path,
    required int timeoutSeconds,
  }) async {
    final resolved = await _locator.resolvePath(path);
    if (resolved == null) {
      throw FileSystemException('所选文件不是支持 ACP 的 Cursor CLI', path);
    }
    return _providerConfig(current, resolved, timeoutSeconds: timeoutSeconds);
  }

  @override
  AgentProviderConfig providerConfigWithTimeout(
    AgentProviderConfig current,
    int timeoutSeconds,
  ) {
    return current.copyWith(
      extra: <String, Object?>{
        ...current.extra,
        'timeoutSeconds': timeoutSeconds,
      },
    );
  }

  @override
  String get configPath => _join(_cursorHomeProvider(), 'cli-config.json');

  @override
  Future<AgentConfigurationDocument> readConfiguration() async {
    final file = File(configPath);
    final exists = await file.exists();
    final content = exists ? await file.readAsString() : '';
    final stat = exists ? await file.stat() : null;
    return AgentConfigurationDocument(
      path: configPath,
      format: 'JSON',
      content: content,
      maskedContent: maskCursorJsonConfiguration(content),
      exists: exists,
      loadedAt: _now(),
      modifiedAt: stat?.modified,
      signature: _signature(content, stat),
    );
  }

  @override
  String? validateConfiguration(String content) {
    if (content.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(content);
      return decoded is Map ? null : 'Cursor 配置根节点必须是 JSON object。';
    } catch (error) {
      return error.toString();
    }
  }

  @override
  Future<AgentConfigurationSaveResult> saveConfiguration({
    required AgentConfigurationDocument original,
    required String content,
    bool overwriteExternalChanges = false,
  }) async {
    final validation = validateConfiguration(content);
    if (validation != null) {
      throw AgentConfigurationValidationException(validation);
    }
    final file = File(original.path);
    if (await FileSystemEntity.type(original.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw FileSystemException('拒绝写入符号链接配置文件', original.path);
    }
    if (await file.exists()) {
      final currentContent = await file.readAsString();
      final currentStat = await file.stat();
      if (!overwriteExternalChanges &&
          _signature(currentContent, currentStat) != original.signature) {
        throw const AgentConfigurationConflictException('配置文件已在外部发生修改。');
      }
    }
    await file.parent.create(recursive: true);
    final stamp = _now().microsecondsSinceEpoch;
    final temp = File(_join(file.parent.path, '.cli-config.zeta-$stamp.tmp'));
    String? backupPath;
    File? displacedOriginal;
    try {
      await temp.writeAsString(content, flush: true);
      if (await file.exists()) {
        backupPath = '${file.path}.zeta-backup-$stamp';
        await file.copy(backupPath);
        displacedOriginal = File('${file.path}.zeta-replace-$stamp');
        await file.rename(displacedOriginal.path);
      }
      try {
        await temp.rename(file.path);
      } catch (_) {
        if (displacedOriginal != null && await displacedOriginal.exists()) {
          await displacedOriginal.rename(file.path);
        }
        rethrow;
      }
      if (displacedOriginal != null && await displacedOriginal.exists()) {
        await displacedOriginal.delete();
      }
    } finally {
      if (await temp.exists()) {
        await temp.delete();
      }
    }
    return AgentConfigurationSaveResult(
      document: await readConfiguration(),
      backupPath: backupPath,
    );
  }

  @override
  Future<List<String>> discoverLogPaths() async {
    return const <String>[CursorDiagnosticsStore.runtimeSource];
  }

  @override
  Future<List<AgentLogEntry>> readLogs(
    List<String> paths, {
    int maxLines = 1000,
  }) async {
    final records = _diagnostics.snapshot.records;
    final limit = maxLines < 0 ? 0 : maxLines;
    final selected = limit == 0
        ? const <CursorDiagnosticRecord>[]
        : records.length <= limit
        ? records
        : records.sublist(records.length - limit);
    return <AgentLogEntry>[
      for (final record in selected)
        AgentLogEntry(
          id: record.id,
          sourcePath: record.source,
          message: record.message,
          level: switch (record.level) {
            CursorDiagnosticLevel.debug => AgentLogLevel.debug,
            CursorDiagnosticLevel.info => AgentLogLevel.info,
            CursorDiagnosticLevel.warning => AgentLogLevel.warning,
            CursorDiagnosticLevel.error => AgentLogLevel.error,
          },
          timestamp: record.timestamp,
        ),
    ];
  }

  AgentProviderConfig _providerConfig(
    AgentProviderConfig current,
    ResolvedCursorCliCommand resolved, {
    required int timeoutSeconds,
  }) {
    return current.copyWith(
      id: cursorAgentProviderId,
      displayName: AgentProviderConfig.defaultCursor.displayName,
      kind: AgentProviderKind.cursorAcp,
      command: resolved.displayPath,
      arguments: const <String>['acp'],
      extra: <String, Object?>{
        ...current.extra,
        'cliPath': resolved.displayPath,
        'timeoutSeconds': timeoutSeconds,
        if (resolved.identity.version != null)
          'detectedCurrentVersion': resolved.identity.version,
      },
    );
  }

  Future<_AccountRead> _readAccountStatus(
    ResolvedCliCommand command, {
    required Map<String, String> environment,
  }) async {
    try {
      var result = await _processRunner(
        command,
        const <String>['status', '--format', 'json'],
        timeout: const Duration(seconds: 12),
        environment: environment,
      );
      if (!result.succeeded) {
        result = await _processRunner(
          command,
          const <String>['status'],
          timeout: const Duration(seconds: 12),
          environment: environment,
        );
      }
      final output = result.combinedOutput;
      final normalized = output.toLowerCase();
      final loggedOut =
          normalized.contains('not authenticated') ||
          normalized.contains('not logged') ||
          normalized.contains('logged out') ||
          normalized.contains('unauthenticated');
      final loggedIn =
          !loggedOut &&
          (result.succeeded ||
              normalized.contains('authenticated') ||
              normalized.contains('logged in'));
      if (loggedIn) {
        return const _AccountRead(
          state: AgentAccountState.loggedIn,
          label: 'Cursor 账号已登录',
        );
      }
      return _AccountRead(
        state: AgentAccountState.loggedOut,
        error: 'Cursor CLI 尚未登录。',
        details: _safeSummary(output),
        suggestion: '请在终端运行 agent login 后重新检测。',
        failureStage: AgentDiagnosticStage.accountAuthentication,
      );
    } catch (error) {
      return _AccountRead(
        state: AgentAccountState.unavailable,
        error: 'Cursor 账号状态检测失败。',
        details: _safeSummary('$error'),
        suggestion: '请确认 Cursor CLI 可在终端正常执行 status。',
        failureStage: AgentDiagnosticStage.accountAuthentication,
      );
    }
  }

  Future<AgentConnectionTestResult> _probeConnection(
    AgentProviderConfig config, {
    DateTime? startedAt,
  }) async {
    final testedAt = startedAt ?? _now();
    final stopwatch = Stopwatch()..start();
    try {
      await _handshakeProbe(
        config,
        Directory.current.absolute.path,
      ).timeout(Duration(seconds: _timeoutSeconds(config)));
      stopwatch.stop();
      final diagnostics = _diagnostics.snapshot;
      final handshake = diagnostics.handshake;
      return AgentConnectionTestResult(
        success: true,
        testedAt: testedAt,
        elapsed: stopwatch.elapsed,
        cliCallable: true,
        accountValid: true,
        protocolReady: true,
        message: 'Cursor ACP 连接正常',
        protocolVersion: handshake?.protocolVersion,
        agentName: handshake?.agentName,
        agentVersion: handshake?.agentVersion,
        capabilitySummary: handshake?.capabilities ?? const <String>[],
        capabilityFingerprint: handshake?.capabilityFingerprint,
        exitReason: diagnostics.exitReason,
      );
    } catch (error) {
      stopwatch.stop();
      return AgentConnectionTestResult(
        success: false,
        testedAt: testedAt,
        elapsed: stopwatch.elapsed,
        cliCallable: true,
        accountValid: false,
        protocolReady: false,
        failureStage: AgentDiagnosticStage.protocolHandshake,
        message: 'Cursor ACP 握手失败。',
        rawErrorSummary: _safeSummary('$error'),
        exitReason: _diagnostics.snapshot.exitReason,
      );
    }
  }

  int _timeoutSeconds(AgentProviderConfig config) {
    final value = config.extra['timeoutSeconds'];
    if (value is int && value >= 5 && value <= 600) {
      return value;
    }
    return 60;
  }
}

Future<void> _defaultHandshakeProbe(
  AgentProviderConfig config,
  String workspacePath,
  CursorDiagnosticsStore diagnosticsStore,
) async {
  final provider = CursorAcpAgentProvider(
    config: config,
    initialWorkspace: workspacePath,
    diagnosticsStore: diagnosticsStore,
  );
  try {
    await provider.initialize();
  } finally {
    await provider.dispose();
  }
}

String _defaultCursorHome() {
  final home =
      Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
  if (home == null || home.isEmpty) {
    return '.cursor';
  }
  return _join(home, '.cursor');
}

String _signature(String content, FileStat? stat) {
  var hash = 0x811c9dc5;
  for (final unit in content.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return '${stat?.modified.millisecondsSinceEpoch ?? 0}:${content.length}:$hash';
}

String _safeSummary(String value) {
  final redacted = redactLogLine(value.replaceAll(RegExp(r'[\r\n]+'), ' '));
  return redacted.length <= 500 ? redacted : redacted.substring(0, 500);
}

String? _capabilityChangeSuggestion(
  AgentProviderConfig config,
  AgentConnectionTestResult connection,
) {
  final previous = config.extra['cursorCapabilityFingerprint']?.toString();
  final current = connection.capabilityFingerprint;
  if (previous == null || current == null || previous == current) {
    return null;
  }
  return 'Cursor ACP 协商能力发生变化；请重新检测并复核可用功能。';
}

/// 对 Cursor JSON 做结构化递归脱敏；损坏 JSON 回退到通用文本遮挡。
String maskCursorJsonConfiguration(String content) {
  if (content.trim().isEmpty) {
    return content;
  }
  try {
    final decoded = jsonDecode(content);
    return const JsonEncoder.withIndent('  ').convert(_maskJsonValue(decoded));
  } catch (_) {
    return maskSensitiveConfiguration(content);
  }
}

Object? _maskJsonValue(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key.toString(): _isSensitiveJsonKey(entry.key.toString())
            ? '••••••'
            : _maskJsonValue(entry.value),
    };
  }
  if (value is List) {
    return <Object?>[for (final item in value) _maskJsonValue(item)];
  }
  return value;
}

bool _isSensitiveJsonKey(String key) {
  final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return normalized.endsWith('apikey') ||
      normalized.endsWith('token') ||
      normalized.endsWith('secret') ||
      normalized.endsWith('password') ||
      normalized.endsWith('privatekey') ||
      normalized == 'authorization' ||
      normalized == 'authorizationheader';
}

String _join(String parent, String child) {
  if (parent.endsWith(Platform.pathSeparator)) {
    return '$parent$child';
  }
  return '$parent${Platform.pathSeparator}$child';
}

class _AccountRead {
  const _AccountRead({
    required this.state,
    this.label,
    this.error,
    this.details,
    this.suggestion,
    this.failureStage,
  });

  final AgentAccountState state;
  final String? label;
  final String? error;
  final String? details;
  final String? suggestion;
  final AgentDiagnosticStage? failureStage;
}
