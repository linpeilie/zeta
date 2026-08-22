import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:toml/toml.dart';

import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/data/cli_command_locator.dart';
import 'package:zeta/src/features/agent/data/grok_cli_locator.dart';

import 'package:zeta/src/features/agent_management/data/cli_process_runner.dart';
import 'package:zeta/src/features/agent_management/data/codex_agent_management_repository.dart'
    show isNewerVersion, maskSensitiveConfiguration, redactLogLine;
import 'package:zeta/src/features/agent_management/domain/agent_cli_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_text_catalog.dart';
import 'package:zeta/src/features/agent_management/domain/fallback_agent_management_text_catalog.dart';

/// 可注入的 CLI 执行函数（测试可替换）。
typedef GrokCliProcessRun =
    Future<CliProcessResult> Function(
      ResolvedCliCommand command,
      List<String> arguments, {
      Duration timeout,
      Map<String, String>? environment,
    });

/// Grok CLI 的检测、配置与日志数据仓库。
class GrokAgentManagementRepository implements AgentCliManagementRepository {
  GrokAgentManagementRepository({
    required this.runtimeRegistry,
    GrokCliProcessRun? processRunner,
    GrokCliLocator? locator,
    DateTime Function()? now,
    String Function()? grokHomeProvider,
    this.modelCatalogRepository,
    AgentManagementTextCatalog? textCatalog,
  }) : _processRunner =
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
       _locator = locator ?? const GrokCliLocator(),
       _now = now ?? DateTime.now,
       _grokHomeProvider = grokHomeProvider ?? _defaultGrokHome,
       _textCatalog = textCatalog ?? const FallbackAgentManagementTextCatalog();

  /// 检测 / 连接测试中 initialize 与模型目录加载的固定上限。
  static const Duration _probeTimeout = Duration(seconds: 60);

  final GrokCliProcessRun _processRunner;
  final GrokCliLocator _locator;
  final DateTime Function() _now;
  final String Function() _grokHomeProvider;
  final AgentModelCatalogRepository? modelCatalogRepository;
  final AgentProviderRuntimeRegistry runtimeRegistry;
  final AgentManagementTextCatalog _textCatalog;

  @override
  String get agentId => AgentDefinition.grok.id;

  @override
  Future<ManagedAgent> detect({
    required AgentProviderConfig providerConfig,
    required bool enabled,
    AgentDetectionProgressCallback? onProgress,
  }) async {
    const total = 8;
    var current = ManagedAgent.grok(enabled: enabled).copyWith(
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

    publish(0, _textCatalog.locating('Grok'));
    final resolved = await _locator.locate(providerConfig);
    if (resolved == null) {
      final configInfo = await _configurationInfo();
      current = current.copyWith(
        installationState: AgentInstallationState.notInstalled,
        accountState: AgentAccountState.unknown,
        runtimeState: AgentRuntimeState.unavailable,
        versionState: AgentVersionState.unknown,
        configExists: configInfo.exists,
        configModifiedAt: configInfo.modifiedAt,
        logPaths: await discoverLogPaths(),
        lastDetectedAt: _now(),
        errorStage: AgentDiagnosticStage.fileDetection,
        errorMessage: _textCatalog.notFound('Grok'),
        suggestion: _textCatalog.installAndAddToPath('Grok'),
      );
      publish(total, _textCatalog.notFound('Grok'));
      return current;
    }

    current = current.copyWith(
      installationState: AgentInstallationState.installed,
      executablePath: resolved.displayPath,
      runtimeState: enabled
          ? AgentRuntimeState.notRunning
          : AgentRuntimeState.disabled,
      errorStage: null,
      errorMessage: null,
      errorDetails: null,
      suggestion: null,
    );
    publish(1, _textCatalog.found('Grok'));

    final version = await _readVersion(resolved);
    current = current.copyWith(
      currentVersion: version.version,
      errorStage: version.error == null
          ? current.errorStage
          : AgentDiagnosticStage.versionDetection,
      errorMessage: version.error ?? current.errorMessage,
      errorDetails: version.details ?? current.errorDetails,
      suggestion: version.error == null
          ? current.suggestion
          : _textCatalog.confirmExecutableThenRedetect(),
    );
    publish(2, _textCatalog.versionDetected());

    final latest = await _latestVersion(resolved);
    final versionState = _resolveVersionState(
      currentVersion: version.version,
      latest: latest,
    );
    current = current.copyWith(
      latestVersion: latest.version,
      versionState: versionState,
      errorStage: latest.error == null
          ? current.errorStage
          : (current.errorStage ?? AgentDiagnosticStage.versionDetection),
      errorMessage: latest.error == null
          ? current.errorMessage
          : (current.errorMessage ?? latest.error),
      errorDetails: latest.error == null
          ? current.errorDetails
          : (current.errorDetails ?? latest.details),
      suggestion: latest.error == null
          ? current.suggestion
          : (current.suggestion ?? _textCatalog.grokLatestVersionNetworkHint()),
    );
    publish(3, _textCatalog.latestVersionChecked());

    final account = await _readAccountStatus();
    current = current.copyWith(
      accountState: account.state,
      accountLabel: account.label,
      errorStage: account.error == null
          ? current.errorStage
          : account.failureStage,
      errorMessage: account.error ?? current.errorMessage,
      errorDetails: account.details ?? current.errorDetails,
      suggestion: account.error == null
          ? current.suggestion
          : account.suggestion,
    );
    publish(4, _textCatalog.accountDetected());

    final configInfo = await _configurationInfo();
    current = current.copyWith(
      configExists: configInfo.exists,
      configModifiedAt: configInfo.modifiedAt,
    );
    publish(5, _textCatalog.configStatusRead());

    final logs = await discoverLogPaths();
    current = current.copyWith(logPaths: logs);
    publish(6, _textCatalog.logsLocated('Grok'));

    final effectiveConfig = _providerConfig(providerConfig, resolved);
    final probe = await _probeProvider(
      effectiveConfig,
      accountState: current.accountState,
      forceModelRefresh: false,
    );
    current = current.copyWith(
      models: probe.models,
      modelsUpdatedAt: probe.models.isEmpty ? null : _now(),
      modelSource: probe.models.isEmpty ? null : 'Grok ACP',
      runtimeState: !enabled
          ? AgentRuntimeState.disabled
          : probe.success
          ? AgentRuntimeState.idle
          : AgentRuntimeState.error,
      errorStage: probe.success ? current.errorStage : probe.failureStage,
      errorMessage: probe.success ? current.errorMessage : probe.message,
      errorDetails: probe.success ? current.errorDetails : probe.details,
      suggestion: probe.success
          ? current.suggestion
          : _textCatalog.retestAfterCheckingGrokAuth(),
    );
    publish(7, _textCatalog.handshakeComplete());

    current = current.copyWith(lastDetectedAt: _now());
    publish(total, _textCatalog.detectionComplete('Grok'));
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
      return (
        AgentConnectionTestResult(
          success: false,
          testedAt: startedAt,
          elapsed: stopwatch.elapsed,
          cliCallable: false,
          accountValid: false,
          protocolReady: false,
          failureStage: AgentDiagnosticStage.fileDetection,
          message: _textCatalog.notFound('Grok'),
        ),
        const <AgentModelInfo>[],
      );
    }

    final account = await _readAccountStatus();
    final effective = _providerConfig(providerConfig, resolved);
    final probe = await _probeProvider(
      effective,
      accountState: account.state,
      forceModelRefresh: true,
    );
    stopwatch.stop();
    return (
      AgentConnectionTestResult(
        success: probe.success,
        testedAt: startedAt,
        elapsed: stopwatch.elapsed,
        cliCallable: true,
        accountValid: account.state == AgentAccountState.loggedIn,
        protocolReady: probe.success,
        failureStage: probe.success ? null : probe.failureStage,
        message: probe.success ? _textCatalog.grokAcpOk() : probe.message,
        rawErrorSummary: probe.details,
      ),
      probe.models,
    );
  }

  @override
  Future<AgentProviderConfig> providerConfigForPath({
    required AgentProviderConfig current,
    required String path,
  }) async {
    final resolved = await _locator.resolvePath(path);
    if (resolved == null) {
      throw FileSystemException(_textCatalog.pathNotRegularFile(), path);
    }
    return _providerConfig(current, resolved);
  }

  @override
  String get configPath => _join(_grokHomeProvider(), 'config.toml');

  @override
  Future<AgentConfigurationDocument> readConfiguration() async {
    final file = File(configPath);
    final exists = await file.exists();
    final content = exists ? await file.readAsString() : '';
    final stat = exists ? await file.stat() : null;
    return AgentConfigurationDocument(
      path: configPath,
      format: 'TOML',
      content: content,
      maskedContent: maskSensitiveConfiguration(content),
      exists: exists,
      loadedAt: _now(),
      modifiedAt: stat?.modified,
      signature: _signature(content, stat),
    );
  }

  @override
  String? validateConfiguration(String content) {
    try {
      TomlDocument.parse(content);
      return null;
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
    final validationError = validateConfiguration(content);
    if (validationError != null) {
      throw AgentConfigurationValidationException(validationError);
    }

    final file = File(original.path);
    final existingType = await FileSystemEntity.type(
      original.path,
      followLinks: false,
    );
    if (existingType == FileSystemEntityType.link) {
      throw FileSystemException(
        _textCatalog.refuseSymlinkConfig(),
        original.path,
      );
    }

    if (await file.exists()) {
      final currentContent = await file.readAsString();
      final currentStat = await file.stat();
      if (!overwriteExternalChanges &&
          _signature(currentContent, currentStat) != original.signature) {
        throw AgentConfigurationConflictException(
          _textCatalog.configExternallyModified(),
        );
      }
    }

    final parent = file.parent;
    await parent.create(recursive: true);
    final stamp = _now().microsecondsSinceEpoch;
    final temp = File(_join(parent.path, '.config.toml.zeta-$stamp.tmp'));
    String? backupPath;
    File? displacedOriginal;
    try {
      await temp.writeAsString(content, flush: true);
      final written = await temp.readAsString();
      final tempError = validateConfiguration(written);
      if (tempError != null) {
        throw AgentConfigurationValidationException(tempError);
      }

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
    final root = _grokHomeProvider();
    final paths = <String>[];
    final logsDir = Directory(_join(root, 'logs'));
    if (await logsDir.exists()) {
      await for (final entity in logsDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) {
          continue;
        }
        final lower = entity.path.toLowerCase();
        if (lower.endsWith('.jsonl') ||
            lower.endsWith('.log') ||
            lower.endsWith('.txt')) {
          paths.add(entity.path);
        }
      }
    }
    paths.sort();
    return List<String>.unmodifiable(paths);
  }

  @override
  Future<List<AgentLogEntry>> readLogs(
    List<String> paths, {
    int maxLines = 1000,
  }) async {
    final entries = <AgentLogEntry>[];
    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) {
        continue;
      }
      final stat = await file.stat();
      final start = stat.size > 512 * 1024 ? stat.size - 512 * 1024 : 0;
      final text = await file
          .openRead(start)
          .transform(const Utf8Decoder(allowMalformed: true))
          .join();
      final lines = const LineSplitter().convert(text);
      final visible = start > 0 && lines.isNotEmpty ? lines.skip(1) : lines;
      var index = 0;
      for (final line in visible) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        entries.add(
          AgentLogEntry(
            id: '$path:${start + index++}',
            sourcePath: path,
            message: redactLogLine(trimmed),
            level: _logLevel(trimmed),
            timestamp: _timestamp(trimmed),
          ),
        );
      }
    }
    entries.sort((left, right) {
      final leftTime = left.timestamp;
      final rightTime = right.timestamp;
      if (leftTime == null && rightTime == null) {
        return left.id.compareTo(right.id);
      }
      if (leftTime == null) {
        return -1;
      }
      if (rightTime == null) {
        return 1;
      }
      return leftTime.compareTo(rightTime);
    });
    if (entries.length <= maxLines) {
      return List<AgentLogEntry>.unmodifiable(entries);
    }
    return List<AgentLogEntry>.unmodifiable(
      entries.sublist(entries.length - maxLines),
    );
  }

  AgentProviderConfig _providerConfig(
    AgentProviderConfig current,
    ResolvedCliCommand resolved,
  ) {
    final extra = Map<String, Object?>.of(current.extra)
      ..remove('timeoutSeconds')
      ..['cliPath'] = resolved.displayPath;
    return current.copyWith(
      id: AgentDefinition.grok.id,
      displayName: AgentDefinition.grok.displayName,
      kind: AgentProviderKind.acp,
      // 保留真实 CLI 路径与纯协议参数；进程启动器会按平台包装 cmd/PowerShell。
      command: resolved.displayPath,
      arguments: const <String>['agent', 'stdio'],
      extra: extra,
    );
  }

  Future<_VersionRead> _readVersion(ResolvedCliCommand command) async {
    try {
      final result = await _processRunner(command, const <String>[
        '--version',
      ], timeout: const Duration(seconds: 10));
      final output = result.combinedOutput;
      // 典型输出：grok 0.2.99 (b1b49ccb71)
      final match = RegExp(
        r'\bgrok\s+(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)\b',
        caseSensitive: false,
      ).firstMatch(output);
      final fallback = RegExp(
        r'\b(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)\b',
      ).firstMatch(output);
      final version = match?.group(1) ?? fallback?.group(1);
      if (!result.succeeded || version == null) {
        return _VersionRead(
          error: _textCatalog.cannotIdentifyVersion('Grok'),
          details: output,
        );
      }
      return _VersionRead(version: version);
    } catch (error) {
      return _VersionRead(
        error: _textCatalog.versionDetectFailed('Grok'),
        details: '$error',
      );
    }
  }

  /// 通过 `grok update --check --json` 查询线上最新版本（不安装）。
  Future<_LatestVersionRead> _latestVersion(ResolvedCliCommand command) async {
    try {
      final result = await _processRunner(command, const <String>[
        'update',
        '--check',
        '--json',
      ], timeout: const Duration(seconds: 20));
      final payload = parseGrokUpdateCheckJson(result.combinedOutput);
      if (payload == null) {
        return _LatestVersionRead(
          error: _textCatalog.cannotParseVersionCheck(),
          details: result.combinedOutput,
        );
      }
      if (payload.error != null && payload.error!.isNotEmpty) {
        return _LatestVersionRead(
          error: _textCatalog.latestVersionCheckFailed(),
          details: payload.error,
        );
      }
      final latest = payload.latestVersion;
      if (latest == null || latest.isEmpty) {
        return _LatestVersionRead(
          error: _textCatalog.versionServiceMissingVersion(),
        );
      }
      return _LatestVersionRead(
        version: latest,
        updateAvailable: payload.updateAvailable,
      );
    } catch (error) {
      return _LatestVersionRead(
        error: _textCatalog.cannotGetLatestVersion('Grok'),
        details: '$error',
      );
    }
  }

  /// 综合本地版本、远端版本与 CLI 的 updateAvailable 标记。
  AgentVersionState _resolveVersionState({
    required String? currentVersion,
    required _LatestVersionRead latest,
  }) {
    if (latest.error != null && latest.version == null) {
      return AgentVersionState.checkFailed;
    }
    final latestVersion = latest.version;
    if (currentVersion == null || latestVersion == null) {
      return currentVersion == null
          ? AgentVersionState.unknown
          : AgentVersionState.current;
    }
    if (latest.updateAvailable == true) {
      return AgentVersionState.updateAvailable;
    }
    if (isNewerVersion(latestVersion, currentVersion)) {
      return AgentVersionState.updateAvailable;
    }
    return AgentVersionState.current;
  }

  /// 通过 `~/.grok/auth.json` 判断登录态（无独立 login status 子命令时的降级）。
  Future<_AccountRead> _readAccountStatus() async {
    try {
      final authFile = File(_join(_grokHomeProvider(), 'auth.json'));
      if (!await authFile.exists()) {
        return _AccountRead(
          state: AgentAccountState.loggedOut,
          error: _textCatalog.notLoggedIn('Grok'),
          suggestion: _textCatalog.runGrokLogin(),
          failureStage: AgentDiagnosticStage.accountAuthentication,
        );
      }
      final raw = await authFile.readAsString();
      if (raw.trim().isEmpty || raw.trim() == '{}') {
        return _AccountRead(
          state: AgentAccountState.loggedOut,
          error: _textCatalog.grokLoginCacheEmpty(),
          suggestion: _textCatalog.runGrokLogin(),
          failureStage: AgentDiagnosticStage.accountAuthentication,
        );
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded.isNotEmpty) {
          return _AccountRead(
            state: AgentAccountState.loggedIn,
            label: _textCatalog.accountLoggedIn(),
          );
        }
      } catch (_) {
        // 非 JSON 但有内容：仍视为可能已登录。
        if (raw.trim().length > 8) {
          return _AccountRead(
            state: AgentAccountState.loggedIn,
            label: _textCatalog.accountLoggedIn(),
          );
        }
      }
      return _AccountRead(
        state: AgentAccountState.unavailable,
        error: _textCatalog.cannotParseGrokLoginCache(),
        suggestion: _textCatalog.rerunGrokLogin(),
        failureStage: AgentDiagnosticStage.accountAuthentication,
      );
    } catch (error) {
      return _AccountRead(
        state: AgentAccountState.unavailable,
        error: _textCatalog.accountCheckFailed(),
        details: '$error',
        suggestion: _textCatalog.confirmCliRuns('Grok'),
        failureStage: AgentDiagnosticStage.accountAuthentication,
      );
    }
  }

  Future<_ProviderProbe> _probeProvider(
    AgentProviderConfig config, {
    required AgentAccountState accountState,
    required bool forceModelRefresh,
  }) async {
    AgentProviderRuntimeLease? lease;
    try {
      // 04-目标态与步骤.md §S7：检测/连接测试是"会话建立前"的一次性探测，
      // 显式绑定全局实例，不依赖 registry 的默认 scope。
      lease = await runtimeRegistry.acquire(
        config,
        scope: AgentProviderRuntimeScopeKey.global,
      );
      final bundle = lease.bundle;
      await bundle.runtime.initialize().timeout(_probeTimeout);
      final modelCatalog = bundle.modelCatalog;
      final models = await _loadModels(
        config: config,
        bundle: bundle,
        hasModelCatalog: modelCatalog != null,
        forceRefresh: forceModelRefresh,
      ).timeout(_probeTimeout);
      return _ProviderProbe(success: true, models: models.models);
    } catch (error) {
      return _ProviderProbe(
        success: false,
        models: const <AgentModelInfo>[],
        failureStage: accountState == AgentAccountState.loggedIn
            ? AgentDiagnosticStage.protocolHandshake
            : AgentDiagnosticStage.accountAuthentication,
        message: _textCatalog.grokAcpFailed(),
        details: '$error',
      );
    } finally {
      if (lease != null) {
        await lease.release();
      }
      // 04-目标态与步骤.md §S8：runtimeRegistry 现在总是外部注入的共享
      // 实例，这里不再有"自建 registry 用完即关"的分支——关闭权归它的
      // 唯一真所有者，不归这次探测。
    }
  }

  Future<AgentModelList> _loadModels({
    required AgentProviderConfig config,
    required AgentProviderBundle bundle,
    required bool hasModelCatalog,
    required bool forceRefresh,
  }) async {
    final modelCatalog = bundle.modelCatalog;
    if (!hasModelCatalog || modelCatalog == null) {
      return const AgentModelList(models: <AgentModelInfo>[]);
    }
    final repository = modelCatalogRepository;
    if (repository == null) {
      return fetchAgentProviderModels(modelCatalog, forceRefresh: forceRefresh);
    }
    final result = await repository.load(
      config: config,
      source: 'Grok ACP',
      forceRefresh: forceRefresh,
      refreshLoader: () =>
          fetchAgentProviderModels(modelCatalog, forceRefresh: true),
    );
    return result.models;
  }

  Future<_ConfigurationInfo> _configurationInfo() async {
    final file = File(configPath);
    if (!await file.exists()) {
      return const _ConfigurationInfo(exists: false);
    }
    final stat = await file.stat();
    return _ConfigurationInfo(exists: true, modifiedAt: stat.modified);
  }
}

String _defaultGrokHome() {
  final envHome = Platform.environment['GROK_HOME']?.trim();
  if (envHome != null && envHome.isNotEmpty) {
    return envHome;
  }
  final home =
      Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
  if (home == null || home.isEmpty) {
    return '.grok';
  }
  return _join(home, '.grok');
}

String _signature(String content, FileStat? stat) {
  var hash = 0x811c9dc5;
  for (final unit in content.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return '${stat?.modified.millisecondsSinceEpoch ?? 0}:${content.length}:$hash';
}

AgentLogLevel _logLevel(String line) {
  final normalized = line.toLowerCase();
  if (normalized.contains('error') || normalized.contains('"level":"error"')) {
    return AgentLogLevel.error;
  }
  if (normalized.contains('warn') || normalized.contains('"level":"warn"')) {
    return AgentLogLevel.warning;
  }
  if (normalized.contains('debug') || normalized.contains('"level":"debug"')) {
    return AgentLogLevel.debug;
  }
  return AgentLogLevel.info;
}

DateTime? _timestamp(String line) {
  final iso = RegExp(
    r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?',
  ).firstMatch(line);
  if (iso != null) {
    return DateTime.tryParse(iso.group(0)!);
  }
  return null;
}

String _join(String parent, String child) {
  if (parent.endsWith(Platform.pathSeparator)) {
    return '$parent$child';
  }
  return '$parent${Platform.pathSeparator}$child';
}

class _VersionRead {
  const _VersionRead({this.version, this.error, this.details});

  final String? version;
  final String? error;
  final String? details;
}

class _LatestVersionRead {
  const _LatestVersionRead({
    this.version,
    this.updateAvailable,
    this.error,
    this.details,
  });

  final String? version;
  final bool? updateAvailable;
  final String? error;
  final String? details;
}

/// `grok update --check --json` 的解析结果。
class GrokUpdateCheckPayload {
  const GrokUpdateCheckPayload({
    this.currentVersion,
    this.latestVersion,
    this.updateAvailable,
    this.error,
    this.raw = const <String, Object?>{},
  });

  final String? currentVersion;
  final String? latestVersion;
  final bool? updateAvailable;
  final String? error;
  final Map<String, Object?> raw;
}

/// 解析 `grok update --check --json` 输出（允许前后夹杂日志行）。
GrokUpdateCheckPayload? parseGrokUpdateCheckJson(String output) {
  final trimmed = output.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final start = trimmed.indexOf('{');
  final end = trimmed.lastIndexOf('}');
  if (start < 0 || end <= start) {
    return null;
  }
  try {
    final decoded = jsonDecode(trimmed.substring(start, end + 1));
    if (decoded is! Map) {
      return null;
    }
    final map = decoded.map(
      (key, value) => MapEntry(key.toString(), value as Object?),
    );
    final errorRaw = map['error'];
    final errorText = errorRaw == null || errorRaw.toString() == 'null'
        ? null
        : errorRaw.toString().trim();
    return GrokUpdateCheckPayload(
      currentVersion: _semverCore(map['currentVersion']?.toString()),
      latestVersion: _semverCore(map['latestVersion']?.toString()),
      updateAvailable: map['updateAvailable'] is bool
          ? map['updateAvailable'] as bool
          : null,
      error: errorText == null || errorText.isEmpty ? null : errorText,
      raw: map,
    );
  } catch (_) {
    return null;
  }
}

/// 提取语义版本核心段（去掉 git hash 等后缀）。
String? _semverCore(String? value) {
  if (value == null) {
    return null;
  }
  final match = RegExp(
    r'(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)',
  ).firstMatch(value.trim());
  return match?.group(1) ?? value.trim();
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

class _ProviderProbe {
  const _ProviderProbe({
    required this.success,
    required this.models,
    this.failureStage,
    this.message,
    this.details,
  });

  final bool success;
  final List<AgentModelInfo> models;
  final AgentDiagnosticStage? failureStage;
  final String? message;
  final String? details;
}

class _ConfigurationInfo {
  const _ConfigurationInfo({required this.exists, this.modifiedAt});

  final bool exists;
  final DateTime? modifiedAt;
}
