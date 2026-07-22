import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:toml/toml.dart';

import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/data/codex_cli_locator.dart';
import 'package:zeta/src/features/agent/data/grok_cli_locator.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider_bundle.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/agent_management/data/cli_process_runner.dart';
import 'package:zeta/src/features/agent_management/data/codex_agent_management_repository.dart'
    show isNewerVersion, maskSensitiveConfiguration, redactLogLine;
import 'package:zeta/src/features/agent_management/domain/agent_cli_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';

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
    required this.providerFactory,
    GrokCliProcessRun? processRunner,
    GrokCliLocator? locator,
    DateTime Function()? now,
    String Function()? grokHomeProvider,
    this._modelCatalogRepository,
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
       _grokHomeProvider = grokHomeProvider ?? _defaultGrokHome;

  final AgentProviderFactory providerFactory;
  final GrokCliProcessRun _processRunner;
  final GrokCliLocator _locator;
  final DateTime Function() _now;
  final String Function() _grokHomeProvider;
  final AgentModelCatalogRepository? _modelCatalogRepository;

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
      timeoutSeconds: _timeoutSeconds(providerConfig),
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

    publish(0, '正在定位 Grok');
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
        errorMessage: '未找到 Grok',
        suggestion: '请先安装 Grok，或手动选择可执行文件。',
      );
      publish(total, '未找到 Grok');
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
    publish(1, '已找到 Grok');

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
          : '请确认所选文件可以正常执行，然后重新检测。',
    );
    publish(2, '已检测当前版本');

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
          : (current.suggestion ?? '请检查网络后重新检测，或在终端运行 grok update --check。'),
    );
    publish(3, '已检查最新版本');

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
    publish(4, '已检测账号状态');

    final configInfo = await _configurationInfo();
    current = current.copyWith(
      configExists: configInfo.exists,
      configModifiedAt: configInfo.modifiedAt,
    );
    publish(5, '已读取配置文件状态');

    final logs = await discoverLogPaths();
    current = current.copyWith(logPaths: logs);
    publish(6, '已定位 Grok 日志');

    final effectiveConfig = _providerConfig(
      providerConfig,
      resolved,
      timeoutSeconds: current.timeoutSeconds,
    );
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
          : '请检查 Grok 登录态与配置后重新测试连接。',
    );
    publish(7, '已完成协议握手');

    current = current.copyWith(lastDetectedAt: _now());
    publish(total, 'Grok 检测完成');
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
          message: '未找到 Grok',
        ),
        const <AgentModelInfo>[],
      );
    }

    final account = await _readAccountStatus();
    final effective = _providerConfig(
      providerConfig,
      resolved,
      timeoutSeconds: _timeoutSeconds(providerConfig),
    );
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
        message: probe.success ? 'Grok ACP 连接正常' : probe.message,
        rawErrorSummary: probe.details,
      ),
      probe.models,
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
      throw FileSystemException('所选文件不存在或不是普通文件', path);
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
    ResolvedCliCommand resolved, {
    required int timeoutSeconds,
  }) {
    return current.copyWith(
      id: AgentDefinition.grok.id,
      displayName: AgentDefinition.grok.displayName,
      kind: AgentProviderKind.acp,
      // 保留真实 CLI 路径与纯协议参数；进程启动器会按平台包装 cmd/PowerShell。
      command: resolved.displayPath,
      arguments: const <String>['agent', 'stdio'],
      extra: <String, Object?>{
        ...current.extra,
        'cliPath': resolved.displayPath,
        'timeoutSeconds': timeoutSeconds,
      },
    );
  }

  int _timeoutSeconds(AgentProviderConfig config) {
    final value = config.extra['timeoutSeconds'];
    if (value is int && value >= 5 && value <= 600) {
      return value;
    }
    return 60;
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
        return _VersionRead(error: '无法识别 Grok 版本。', details: output);
      }
      return _VersionRead(version: version);
    } catch (error) {
      return _VersionRead(error: 'Grok 版本检测失败。', details: '$error');
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
          error: '无法解析版本检查结果。',
          details: result.combinedOutput,
        );
      }
      if (payload.error != null && payload.error!.isNotEmpty) {
        return _LatestVersionRead(error: '最新版本检查失败。', details: payload.error);
      }
      final latest = payload.latestVersion;
      if (latest == null || latest.isEmpty) {
        return const _LatestVersionRead(error: '版本服务未返回最新版本号。');
      }
      return _LatestVersionRead(
        version: latest,
        updateAvailable: payload.updateAvailable,
      );
    } catch (error) {
      return _LatestVersionRead(error: '无法获取 Grok 最新版本。', details: '$error');
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
        return const _AccountRead(
          state: AgentAccountState.loggedOut,
          error: 'Grok 尚未登录。',
          suggestion: '请在终端运行 grok login 后重新检测。',
          failureStage: AgentDiagnosticStage.accountAuthentication,
        );
      }
      final raw = await authFile.readAsString();
      if (raw.trim().isEmpty || raw.trim() == '{}') {
        return const _AccountRead(
          state: AgentAccountState.loggedOut,
          error: 'Grok 登录缓存为空。',
          suggestion: '请在终端运行 grok login 后重新检测。',
          failureStage: AgentDiagnosticStage.accountAuthentication,
        );
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded.isNotEmpty) {
          return const _AccountRead(
            state: AgentAccountState.loggedIn,
            label: '账号已登录',
          );
        }
      } catch (_) {
        // 非 JSON 但有内容：仍视为可能已登录。
        if (raw.trim().length > 8) {
          return const _AccountRead(
            state: AgentAccountState.loggedIn,
            label: '账号已登录',
          );
        }
      }
      return const _AccountRead(
        state: AgentAccountState.unavailable,
        error: '无法解析 Grok 登录缓存。',
        suggestion: '请重新运行 grok login。',
        failureStage: AgentDiagnosticStage.accountAuthentication,
      );
    } catch (error) {
      return _AccountRead(
        state: AgentAccountState.unavailable,
        error: '账号状态检测失败。',
        details: '$error',
        suggestion: '请确认 Grok 可以在终端中正常运行。',
        failureStage: AgentDiagnosticStage.accountAuthentication,
      );
    }
  }

  Future<_ProviderProbe> _probeProvider(
    AgentProviderConfig config, {
    required AgentAccountState accountState,
    required bool forceModelRefresh,
  }) async {
    AgentProvider? provider;
    try {
      provider = providerFactory.create(config);
      await provider.initialize().timeout(
        Duration(seconds: _timeoutSeconds(config)),
      );
      final modelCatalog = provider.bundle.modelCatalog;
      final models = await _loadModels(
        config: config,
        provider: provider,
        hasModelCatalog: modelCatalog != null,
        forceRefresh: forceModelRefresh,
      ).timeout(Duration(seconds: _timeoutSeconds(config)));
      return _ProviderProbe(success: true, models: models.models);
    } catch (error) {
      return _ProviderProbe(
        success: false,
        models: const <AgentModelInfo>[],
        failureStage: accountState == AgentAccountState.loggedIn
            ? AgentDiagnosticStage.protocolHandshake
            : AgentDiagnosticStage.accountAuthentication,
        message: 'Grok ACP 连接失败。',
        details: '$error',
      );
    } finally {
      await provider?.dispose();
    }
  }

  Future<AgentModelList> _loadModels({
    required AgentProviderConfig config,
    required AgentProvider provider,
    required bool hasModelCatalog,
    required bool forceRefresh,
  }) async {
    if (!hasModelCatalog) {
      return const AgentModelList(models: <AgentModelInfo>[]);
    }
    final repository = _modelCatalogRepository;
    if (repository == null) {
      return fetchAgentProviderModels(provider, forceRefresh: forceRefresh);
    }
    final result = await repository.load(
      config: config,
      source: 'Grok ACP',
      forceRefresh: forceRefresh,
      refreshLoader: () =>
          fetchAgentProviderModels(provider, forceRefresh: true),
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
