import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:toml/toml.dart';

import 'package:zeta/src/core/security/sensitive_data_redactor.dart';
import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_registry.dart';
import 'package:zeta/src/features/agent/data/cli_command_locator.dart';
import 'package:zeta/src/features/agent/data/codex_cli_locator.dart'
    show CodexCliLocator;
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider_bundle.dart';
import 'package:zeta/src/features/agent_management/data/cli_process_runner.dart';
import 'package:zeta/src/features/agent_management/domain/agent_cli_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_text_catalog.dart';
import 'package:zeta/src/features/agent_management/domain/fallback_agent_management_text_catalog.dart';

/// Codex CLI 的检测、配置与日志数据仓库。
class CodexAgentManagementRepository implements AgentCliManagementRepository {
  CodexAgentManagementRepository({
    required this.runtimeRegistry,
    CliProcessRunner? processRunner,
    CodexCliLocator? locator,
    HttpClient Function()? httpClientFactory,
    DateTime Function()? now,
    String Function()? codexHomeProvider,
    this.modelCatalogRepository,
    AgentManagementTextCatalog? textCatalog,
  }) : _processRunner = processRunner ?? const CliProcessRunner(),
       _locator = locator ?? const CodexCliLocator(),
       _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _now = now ?? DateTime.now,
       _codexHomeProvider = codexHomeProvider ?? _defaultCodexHome,
       _textCatalog = textCatalog ?? const FallbackAgentManagementTextCatalog();

  /// 检测 / 连接测试中 initialize 与模型目录加载的固定上限。
  static const Duration _probeTimeout = Duration(seconds: 60);

  final CliProcessRunner _processRunner;
  final CodexCliLocator _locator;
  final HttpClient Function() _httpClientFactory;
  final DateTime Function() _now;
  final String Function() _codexHomeProvider;
  final AgentModelCatalogRepository? modelCatalogRepository;
  final AgentProviderRuntimeRegistry runtimeRegistry;
  final AgentManagementTextCatalog _textCatalog;

  @override
  String get agentId => AgentDefinition.codex.id;

  /// 执行完整但不产生模型费用的 Codex 自动检测。
  @override
  Future<ManagedAgent> detect({
    required AgentProviderConfig providerConfig,
    required bool enabled,
    AgentDetectionProgressCallback? onProgress,
  }) async {
    const total = 8;
    var current = ManagedAgent.codex(enabled: enabled).copyWith(
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

    publish(0, _textCatalog.locating('Codex'));
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
        errorMessage: _textCatalog.notFound('Codex'),
        suggestion: _textCatalog.installAndAddToPath('Codex'),
      );
      publish(total, _textCatalog.notFound('Codex'));
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
    publish(1, _textCatalog.found('Codex'));

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

    final account = await _readAccountStatus(resolved);
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
    publish(3, _textCatalog.accountDetected());

    final configInfo = await _configurationInfo();
    current = current.copyWith(
      configExists: configInfo.exists,
      configModifiedAt: configInfo.modifiedAt,
    );
    publish(4, _textCatalog.configStatusRead());

    final logs = await discoverLogPaths();
    current = current.copyWith(logPaths: logs);
    publish(5, _textCatalog.logsLocated('Codex'));

    final latest = await _latestVersion();
    final versionState = switch ((version.version, latest.version)) {
      (final String currentVersion, final String latestVersion) =>
        isNewerVersion(latestVersion, currentVersion)
            ? AgentVersionState.updateAvailable
            : AgentVersionState.current,
      _ when latest.error != null => AgentVersionState.checkFailed,
      _ => AgentVersionState.unknown,
    };
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
    );
    publish(6, _textCatalog.latestVersionChecked());

    final effectiveConfig = _providerConfig(providerConfig, resolved);
    final probe = await _probeProvider(
      effectiveConfig,
      accountState: current.accountState,
      forceModelRefresh: false,
    );
    current = current.copyWith(
      models: probe.models,
      modelsUpdatedAt: probe.models.isEmpty ? null : _now(),
      modelSource: probe.models.isEmpty ? null : 'Codex app-server',
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
          : _textCatalog.retestAfterCheckingConfig('Codex'),
    );
    publish(7, _textCatalog.handshakeComplete());

    current = current.copyWith(lastDetectedAt: _now());
    publish(total, _textCatalog.detectionComplete('Codex'));
    return current;
  }

  /// 使用独立 provider 实例执行 initialize + model/list，不发送模型请求。
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
          message: _textCatalog.notFound('Codex'),
        ),
        const <AgentModelInfo>[],
      );
    }

    final account = await _readAccountStatus(resolved);
    final effectiveConfig = _providerConfig(providerConfig, resolved);
    final probe = await _probeProvider(
      effectiveConfig,
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
        failureStage: probe.failureStage,
        message: probe.message,
        rawErrorSummary: probe.details,
        protocolVersion: probe.runtimeInfo?.protocolVersion,
        agentName: probe.runtimeInfo?.protocolName,
        agentVersion: probe.runtimeInfo?.cliVersion,
        capabilitySummary: _capabilitySummary(probe.capabilities),
        compatibilitySummary: probe.runtimeInfo == null
            ? null
            : _compatibilitySummary(
                probe.runtimeInfo!.compatibilityStatus,
                _textCatalog,
              ),
      ),
      probe.models,
    );
  }

  /// 将用户选择的 CLI 文件转换为 provider 可持久化配置。
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
  String get configPath {
    return _join(_codexHomeProvider(), 'config.toml');
  }

  /// 加载 TOML 配置，并生成脱敏内容与外部修改签名。
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

  /// 校验 TOML；返回 null 表示有效。
  @override
  String? validateConfiguration(String content) {
    try {
      TomlDocument.parse(content);
      return null;
    } catch (error) {
      return error.toString();
    }
  }

  /// 使用临时文件和备份保存配置，失败时保留原文件。
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

  /// 查找 Codex 自身写入磁盘的文本日志。
  @override
  Future<List<String>> discoverLogPaths() async {
    final root = _codexHomeProvider();
    final paths = <String>[];
    final logDirectory = Directory(_join(root, 'log'));
    if (await logDirectory.exists()) {
      await for (final entity in logDirectory.list(followLinks: false)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.log')) {
          paths.add(entity.path);
        }
      }
    }
    final sandboxLog = File(_join(root, 'sandbox.log'));
    if (await sandboxLog.exists()) {
      paths.add(sandboxLog.path);
    }
    paths.sort();
    return List<String>.unmodifiable(paths);
  }

  /// 读取日志尾部并在进入 UI 前脱敏。
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
    ResolvedCliCommand command,
  ) {
    final extra = Map<String, Object?>.of(current.extra)
      ..remove('timeoutSeconds')
      ..['cliPath'] = command.displayPath;
    return current.copyWith(
      id: AgentDefinition.codex.id,
      displayName: AgentDefinition.codex.displayName,
      kind: AgentProviderKind.codexAppServer,
      command: command.executable,
      arguments: command.argumentsFor(const <String>['app-server']),
      extra: extra,
    );
  }

  Future<_VersionRead> _readVersion(ResolvedCliCommand command) async {
    try {
      final result = await _processRunner.run(command, const <String>[
        '--version',
      ], timeout: const Duration(seconds: 10));
      final output = result.combinedOutput;
      final match = RegExp(
        r'\b(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)\b',
      ).firstMatch(output);
      if (!result.succeeded || match == null) {
        return _VersionRead(
          error: _textCatalog.cannotIdentifyVersion('Codex'),
          details: output,
        );
      }
      return _VersionRead(version: match.group(1));
    } catch (error) {
      return _VersionRead(error: 'Codex 版本检测失败。', details: '$error');
    }
  }

  Future<_AccountRead> _readAccountStatus(ResolvedCliCommand command) async {
    try {
      final result = await _processRunner.run(command, const <String>[
        'login',
        'status',
      ], timeout: const Duration(seconds: 15));
      final output = result.combinedOutput;
      final normalized = output.toLowerCase();
      if (result.succeeded &&
          (normalized.contains('logged in') ||
              normalized.contains('authenticated'))) {
        return _AccountRead(
          state: AgentAccountState.loggedIn,
          label: _textCatalog.accountLoggedIn(),
        );
      }
      if (normalized.contains('not logged') ||
          normalized.contains('login required')) {
        return _AccountRead(
          state: AgentAccountState.loggedOut,
          error: 'Codex 尚未登录。',
          suggestion: _textCatalog.runCodexLogin(),
          failureStage: AgentDiagnosticStage.accountAuthentication,
        );
      }
      final configFailure =
          normalized.contains('config.toml') ||
          normalized.contains('configuration') ||
          normalized.contains('unknown variant');
      return _AccountRead(
        state: AgentAccountState.unavailable,
        error: configFailure
            ? _textCatalog.codexConfigUnparseable()
            : _textCatalog.cannotDetectAccount(),
        details: output,
        suggestion: configFailure
            ? _textCatalog.fixConfigTomlThenRedetect()
            : _textCatalog.runCodexLoginStatus(),
        failureStage: configFailure
            ? AgentDiagnosticStage.configurationRead
            : AgentDiagnosticStage.accountAuthentication,
      );
    } catch (error) {
      return _AccountRead(
        state: AgentAccountState.unavailable,
        error: _textCatalog.accountCheckFailed(),
        details: '$error',
        suggestion: _textCatalog.confirmCliRuns('Codex'),
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
      return _ProviderProbe(
        success: true,
        models: models.models,
        runtimeInfo: bundle.runtime.runtimeInfo,
        capabilities: bundle.capabilities,
      );
    } catch (error) {
      return _ProviderProbe(
        success: false,
        models: const <AgentModelInfo>[],
        failureStage: accountState == AgentAccountState.loggedIn
            ? AgentDiagnosticStage.protocolHandshake
            : AgentDiagnosticStage.accountAuthentication,
        message: 'Codex app-server 连接失败。',
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
      source: 'Codex app-server',
      forceRefresh: forceRefresh,
      refreshLoader: () =>
          fetchAgentProviderModels(modelCatalog, forceRefresh: true),
    );
    return result.models;
  }

  Future<_LatestVersionRead> _latestVersion() async {
    final client = _httpClientFactory();
    try {
      final uri = Uri.parse(
        'https://registry.npmjs.org/@openai%2Fcodex/latest',
      );
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 10));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != HttpStatus.ok) {
        return _LatestVersionRead(
          error: _textCatalog.latestVersionCheckFailed(),
          details: 'HTTP ${response.statusCode}',
        );
      }
      final body = await response
          .transform(const Utf8Decoder())
          .join()
          .timeout(const Duration(seconds: 10));
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['version'] is String) {
        return _LatestVersionRead(version: decoded['version'] as String);
      }
      return _LatestVersionRead(
        error: _textCatalog.versionServiceUnknownFormat(),
      );
    } catch (error) {
      return _LatestVersionRead(
        error: _textCatalog.cannotGetLatestVersion('Codex'),
        details: '$error',
      );
    } finally {
      client.close(force: true);
    }
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

/// 比较常规语义化版本；无法解析时保守返回 false。
bool isNewerVersion(String candidate, String current) {
  List<int>? parse(String value) {
    final core = value.split(RegExp(r'[-+]')).first;
    final parts = core.split('.');
    if (parts.length < 3) {
      return null;
    }
    final numbers = parts.take(3).map(int.tryParse).toList();
    if (numbers.any((number) => number == null)) {
      return null;
    }
    return numbers.cast<int>();
  }

  final left = parse(candidate);
  final right = parse(current);
  if (left == null || right == null) {
    return false;
  }
  for (var index = 0; index < 3; index++) {
    if (left[index] != right[index]) {
      return left[index] > right[index];
    }
  }
  return false;
}

/// 默认遮挡常见敏感 TOML 字段的值。
String maskSensitiveConfiguration(String content) {
  final sensitive = RegExp(
    r'^(\s*(?:api[_-]?key|token|secret|password|authorization|access[_-]?token|refresh[_-]?token)\s*=\s*)([^\r\n#]+)',
    caseSensitive: false,
    multiLine: true,
  );
  final tomlMasked = content.replaceAllMapped(
    sensitive,
    (match) => '${match.group(1)}"••••••"',
  );
  final jsonSensitive = RegExp(
    r'("(?:api[_-]?key|token|secret|password|authorization|access[_-]?token|refresh[_-]?token)"\s*:\s*)"[^"]*"',
    caseSensitive: false,
  );
  return tomlMasked.replaceAllMapped(
    jsonSensitive,
    (match) => '${match.group(1)}"••••••"',
  );
}

/// 在日志进入 UI 前遮挡凭证、Authorization 值和用户目录。
String redactLogLine(String line) {
  return redactSensitiveText(line);
}

String _defaultCodexHome() {
  final override = Platform.environment['CODEX_HOME'];
  if (override != null && override.trim().isNotEmpty) {
    return override;
  }
  final home =
      Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
  if (home == null || home.isEmpty) {
    return '.codex';
  }
  return _join(home, '.codex');
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
  if (normalized.contains('error') || normalized.contains('fatal')) {
    return AgentLogLevel.error;
  }
  if (normalized.contains('warn')) {
    return AgentLogLevel.warning;
  }
  if (normalized.contains('debug') || normalized.contains('trace')) {
    return AgentLogLevel.debug;
  }
  return AgentLogLevel.info;
}

DateTime? _timestamp(String line) {
  final match = RegExp(r'(\d{4}-\d{2}-\d{2}[T ][0-9:.+-]+)').firstMatch(line);
  if (match == null) {
    return null;
  }
  return DateTime.tryParse(match.group(1)!.replaceFirst(' ', 'T'));
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
  const _LatestVersionRead({this.version, this.error, this.details});

  final String? version;
  final String? error;
  final String? details;
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
    this.runtimeInfo,
    this.capabilities,
  });

  final bool success;
  final List<AgentModelInfo> models;
  final AgentDiagnosticStage? failureStage;
  final String? message;
  final String? details;
  final AgentRuntimeInfo? runtimeInfo;
  final AgentProviderCapabilities? capabilities;
}

List<String> _capabilitySummary(AgentProviderCapabilities? capabilities) {
  if (capabilities == null) {
    return const <String>[];
  }
  return <String>[
    if (capabilities.canPrompt) 'prompt',
    if (capabilities.canSteerTurn) 'steer',
    if (capabilities.canForkThreadAtTurn) 'fork-at-turn',
  ];
}

String _compatibilitySummary(
  AgentRuntimeCompatibilityStatus status,
  AgentManagementTextCatalog catalog,
) {
  return catalog.compatibilitySummary(status);
}

class _ConfigurationInfo {
  const _ConfigurationInfo({required this.exists, this.modifiedAt});

  final bool exists;
  final DateTime? modifiedAt;
}
