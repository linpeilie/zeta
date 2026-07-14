import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:toml/toml.dart';

import 'package:zeta/src/features/agent/data/codex_cli_locator.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/agent_management/data/cli_process_runner.dart';
import 'package:zeta/src/features/agent_management/domain/agent_cli_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';

/// Codex CLI 的检测、配置与日志数据仓库。
class CodexAgentManagementRepository implements AgentCliManagementRepository {
  CodexAgentManagementRepository({
    required this.providerFactory,
    CliProcessRunner? processRunner,
    CodexCliLocator? locator,
    HttpClient Function()? httpClientFactory,
    DateTime Function()? now,
    String Function()? codexHomeProvider,
  }) : _processRunner = processRunner ?? const CliProcessRunner(),
       _locator = locator ?? const CodexCliLocator(),
       _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _now = now ?? DateTime.now,
       _codexHomeProvider = codexHomeProvider ?? _defaultCodexHome;

  final AgentProviderFactory providerFactory;
  final CliProcessRunner _processRunner;
  final CodexCliLocator _locator;
  final HttpClient Function() _httpClientFactory;
  final DateTime Function() _now;
  final String Function() _codexHomeProvider;

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

    publish(0, '正在定位 Codex CLI');
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
        errorMessage: '未找到 Codex CLI',
        suggestion: '请先安装 Codex CLI，或手动选择可执行文件。',
      );
      publish(total, '未找到 Codex CLI');
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
    publish(1, '已找到 Codex CLI');

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
    publish(3, '已检测账号状态');

    final configInfo = await _configurationInfo();
    current = current.copyWith(
      configExists: configInfo.exists,
      configModifiedAt: configInfo.modifiedAt,
    );
    publish(4, '已读取配置文件状态');

    final logs = await discoverLogPaths();
    current = current.copyWith(logPaths: logs);
    publish(5, '已定位 Codex 日志');

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
    publish(6, '已检查最新版本');

    final effectiveConfig = _providerConfig(
      providerConfig,
      resolved,
      timeoutSeconds: current.timeoutSeconds,
    );
    final probe = await _probeProvider(
      effectiveConfig,
      accountState: current.accountState,
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
          : '请检查 Codex 配置和账号状态后重新测试连接。',
    );
    publish(7, '已完成协议握手');

    current = current.copyWith(lastDetectedAt: _now());
    publish(total, 'Codex 检测完成');
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
          message: '未找到 Codex CLI 可执行文件。',
        ),
        const <AgentModelInfo>[],
      );
    }

    final account = await _readAccountStatus(resolved);
    final effectiveConfig = _providerConfig(
      providerConfig,
      resolved,
      timeoutSeconds: _timeoutSeconds(providerConfig),
    );
    final probe = await _probeProvider(
      effectiveConfig,
      accountState: account.state,
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
      ),
      probe.models,
    );
  }

  /// 将用户选择的 CLI 文件转换为 provider 可持久化配置。
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

  /// 更新只影响管理层的超时配置。
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
    ResolvedCliCommand command, {
    required int timeoutSeconds,
  }) {
    return current.copyWith(
      id: AgentDefinition.codex.id,
      displayName: AgentDefinition.codex.displayName,
      kind: AgentProviderKind.codexAppServer,
      command: command.executable,
      arguments: command.argumentsFor(const <String>['app-server']),
      extra: <String, Object?>{
        ...current.extra,
        'cliPath': command.displayPath,
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
      final result = await _processRunner.run(command, const <String>[
        '--version',
      ], timeout: const Duration(seconds: 10));
      final output = result.combinedOutput;
      final match = RegExp(
        r'\b(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)\b',
      ).firstMatch(output);
      if (!result.succeeded || match == null) {
        return _VersionRead(error: '无法识别 Codex CLI 版本。', details: output);
      }
      return _VersionRead(version: match.group(1));
    } catch (error) {
      return _VersionRead(error: 'Codex CLI 版本检测失败。', details: '$error');
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
        return const _AccountRead(
          state: AgentAccountState.loggedIn,
          label: '账号已登录',
        );
      }
      if (normalized.contains('not logged') ||
          normalized.contains('login required')) {
        return const _AccountRead(
          state: AgentAccountState.loggedOut,
          error: 'Codex CLI 尚未登录。',
          suggestion: '请在终端运行 codex login 后重新检测。',
          failureStage: AgentDiagnosticStage.accountAuthentication,
        );
      }
      final configFailure =
          normalized.contains('config.toml') ||
          normalized.contains('configuration') ||
          normalized.contains('unknown variant');
      return _AccountRead(
        state: AgentAccountState.unavailable,
        error: configFailure ? 'Codex 配置文件无法解析。' : '无法检测账号状态。',
        details: output,
        suggestion: configFailure
            ? '请修复 config.toml 中提示的字段后重新检测。'
            : '请在终端运行 codex login status 查看详细信息。',
        failureStage: configFailure
            ? AgentDiagnosticStage.configurationRead
            : AgentDiagnosticStage.accountAuthentication,
      );
    } catch (error) {
      return _AccountRead(
        state: AgentAccountState.unavailable,
        error: '账号状态检测失败。',
        details: '$error',
        suggestion: '请确认 Codex CLI 可以在终端中正常运行。',
        failureStage: AgentDiagnosticStage.accountAuthentication,
      );
    }
  }

  Future<_ProviderProbe> _probeProvider(
    AgentProviderConfig config, {
    required AgentAccountState accountState,
  }) async {
    AgentProvider? provider;
    try {
      provider = providerFactory.create(config);
      await provider.initialize().timeout(
        Duration(seconds: _timeoutSeconds(config)),
      );
      final models = await provider.listModels().timeout(
        Duration(seconds: _timeoutSeconds(config)),
      );
      return _ProviderProbe(success: true, models: models.models);
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
      await provider?.dispose();
    }
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
          error: '最新版本检查失败。',
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
      return const _LatestVersionRead(error: '版本服务返回了未知格式。');
    } catch (error) {
      return _LatestVersionRead(error: '无法获取 Codex 最新版本。', details: '$error');
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
  var result = line
      .replaceAll(
        RegExp(r'bearer\s+[A-Za-z0-9._~+/-]+=*', caseSensitive: false),
        'Bearer ••••••',
      )
      .replaceAll(RegExp(r'\bsk-[A-Za-z0-9_-]{12,}\b'), 'sk-••••••')
      .replaceAllMapped(
        RegExp(
          r'(api[_-]?key|token|secret|password|authorization)(\s*[:=]\s*)[^\s,;]+',
          caseSensitive: false,
        ),
        (match) => '${match.group(1)}${match.group(2)}••••••',
      );
  final home =
      Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
  if (home != null && home.isNotEmpty) {
    result = result.replaceAll(home, '~');
  }
  return result;
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
