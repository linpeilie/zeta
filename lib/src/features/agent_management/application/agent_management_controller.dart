import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:zeta/src/features/agent/data/codex_cli_locator.dart'
    show looksLikeCodexCliPath;
import 'package:zeta/src/features/agent/data/grok_cli_locator.dart'
    show looksLikeGrokCliPath;
import 'package:zeta/src/features/agent/data/cursor_cli_locator.dart'
    show looksLikeCursorCliPath;
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent_management/data/codex_agent_management_repository.dart'
    show isNewerVersion;
import 'package:zeta/src/features/agent_management/domain/agent_cli_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/ui/features/ide/view_models/active_agent_provider_controller.dart';

/// Agent 管理页面的应用层协调器（支持多 Agent CLI）。
class AgentManagementController extends ChangeNotifier {
  AgentManagementController({
    required Map<String, AgentCliManagementRepository> repositories,
    required this.providerController,
    this.runtimeStateProvider,
    this.runtimeListenable,
  }) : _repositories = Map<String, AgentCliManagementRepository>.unmodifiable(
         repositories,
       ),
       _selectedAgentId = repositories.keys.isEmpty
           ? defaultAgentProviderId
           : repositories.keys.first,
       _agents = <String, ManagedAgent>{
         for (final entry in repositories.entries)
           entry.key: ManagedAgent.forDefinition(
             definition:
                 AgentDefinition.byId(entry.key) ??
                 AgentDefinition(
                   id: entry.key,
                   displayName: entry.key,
                   vendor: 'Unknown',
                   commandName: entry.key,
                   protocol: 'unknown',
                   transport: 'unknown',
                   configFormat: 'unknown',
                   defaultConfigRelativePath: '',
                   npmPackage: '',
                 ),
             enabled: providerController.isProviderEnabled(entry.key),
           ),
       } {
    providerController.addListener(_handleProviderSettingsChanged);
    runtimeListenable?.addListener(refreshRuntimeState);
  }

  final Map<String, AgentCliManagementRepository> _repositories;
  final ActiveAgentProviderController providerController;
  final AgentRuntimeState Function()? runtimeStateProvider;
  final Listenable? runtimeListenable;

  final Map<String, ManagedAgent> _agents;
  String _selectedAgentId;
  AgentDetectionProgress? _detectionProgress;
  AgentConfigurationDocument? _configuration;
  List<AgentLogEntry> _logs = const <AgentLogEntry>[];
  bool _initialized = false;
  bool _detecting = false;
  bool _testing = false;
  bool _loadingConfiguration = false;
  bool _savingConfiguration = false;
  bool _loadingLogs = false;
  bool _disposed = false;
  String? _operationError;

  /// 全部受管 Agent 快照（定义顺序优先）。
  List<ManagedAgent> get agents {
    final ordered = <ManagedAgent>[];
    for (final definition in AgentDefinition.all) {
      final agent = _agents[definition.id];
      if (agent != null) {
        ordered.add(agent);
      }
    }
    for (final entry in _agents.entries) {
      if (!ordered.any((agent) => agent.definition.id == entry.key)) {
        ordered.add(entry.value);
      }
    }
    return List<ManagedAgent>.unmodifiable(ordered);
  }

  /// 详情页当前选中的 Agent。
  ManagedAgent get agent =>
      _agents[_selectedAgentId] ??
      ManagedAgent.codex(
        enabled: providerController.isProviderEnabled(defaultAgentProviderId),
      );

  String get selectedAgentId => _selectedAgentId;

  /// 当前选中 Agent 的仓库（配置/日志/检测）。
  AgentCliManagementRepository get repository {
    final selected = _repositories[_selectedAgentId];
    if (selected != null) {
      return selected;
    }
    return _repositories.values.first;
  }

  AgentDetectionProgress? get detectionProgress => _detectionProgress;
  AgentConfigurationDocument? get configuration => _configuration;
  List<AgentLogEntry> get logs => List<AgentLogEntry>.unmodifiable(_logs);
  bool get betaCompatibilityWarningAcknowledged {
    return _configForAgent(
          _selectedAgentId,
        ).extra['betaCompatibilityWarningAcknowledged'] ==
        true;
  }

  bool get initialized => _initialized;
  bool get detecting => _detecting;
  bool get testing => _testing;
  bool get loadingConfiguration => _loadingConfiguration;
  bool get savingConfiguration => _savingConfiguration;
  bool get loadingLogs => _loadingLogs;
  String? get operationError => _operationError;

  /// 配置中已启用、且 Zeta 已实现 CLI 适配的 provider。
  ///
  /// 创建 thread 的选择器只判断产品是否支持该 provider，不执行安装、登录、
  /// 版本、运行态或协议握手检测。真正启动失败时由会话创建流程报告错误。
  List<AgentProviderConfig> get availableThreadProviders {
    final supportedIds = _repositories.keys.toSet();
    return List<AgentProviderConfig>.unmodifiable(
      providerController.settings.providers.where(
        (provider) => provider.enabled && supportedIds.contains(provider.id),
      ),
    );
  }

  /// 加载配置并返回创建新 thread 时可选择的 provider，不触发 Agent 检测。
  Future<List<AgentProviderConfig>> loadAvailableThreadProviders() async {
    await initialize();
    return availableThreadProviders;
  }

  /// 切换详情页选中的 Agent。
  void selectAgent(String agentId) {
    if (!_repositories.containsKey(agentId) || _selectedAgentId == agentId) {
      return;
    }
    _selectedAgentId = agentId;
    _configuration = null;
    _logs = const <AgentLogEntry>[];
    _operationError = null;
    _notify();
  }

  /// 加载持久化 provider 配置和上一次检测摘要。
  Future<void> initialize({bool autoDetect = false}) async {
    if (_initialized) {
      if (autoDetect && !_detecting) {
        unawaited(detect());
      }
      return;
    }
    await providerController.loadSettings();
    for (final entry in _repositories.entries) {
      final config = _configForAgent(entry.key);
      _agents[entry.key] = _restoreCachedAgent(
        agentId: entry.key,
        config: config,
        repository: entry.value,
      );
    }
    _initialized = true;
    _notify();
    if (autoDetect) {
      unawaited(detect());
    }
  }

  /// 自动检测全部已注册 Agent。
  Future<void> detect() async {
    if (_detecting) {
      return;
    }
    await initialize();
    _detecting = true;
    _operationError = null;
    _notify();
    try {
      final ids = _repositories.keys.toList(growable: false);
      var index = 0;
      for (final id in ids) {
        index += 1;
        final repo = _repositories[id]!;
        final config = _configForAgent(id);
        final detected = await repo.detect(
          providerConfig: config,
          enabled: config.enabled,
          onProgress: (progress, partial) {
            // 把单 Agent 进度映射到总进度文案。
            _detectionProgress = AgentDetectionProgress(
              completed: progress.completed,
              total: progress.total,
              message:
                  '[$index/${ids.length}] ${partial.definition.displayName}: ${progress.message}',
            );
            _agents[id] = partial.copyWith(
              runtimeState: _runtimeState(
                id,
                partial.enabled,
                partial.runtimeState,
              ),
            );
            _notify();
          },
        );
        _agents[id] = detected.copyWith(
          runtimeState: _runtimeState(
            id,
            detected.enabled,
            detected.runtimeState,
          ),
        );
        await _persistDetectionSummary(id, config, detected);
      }
      _detectionProgress = null;
    } catch (error) {
      _operationError = 'Agent 检测未能完成：$error';
    } finally {
      _detecting = false;
      _notify();
    }
  }

  /// 启用或禁用当前选中 Agent。
  Future<void> setEnabled(bool enabled) async {
    final current = agent;
    if (current.enabled == enabled) {
      return;
    }
    _operationError = null;
    if (enabled &&
        current.definition.id == cursorAgentProviderId &&
        current.connectionTest?.success != true) {
      _operationError = '启用 Cursor 前必须先完成一次成功的无计费 ACP 连接测试。';
      _notify();
      return;
    }
    try {
      await providerController.setProviderEnabled(
        current.definition.id,
        enabled,
      );
      _agents[current.definition.id] = current.copyWith(
        enabled: enabled,
        runtimeState: enabled
            ? AgentRuntimeState.notRunning
            : AgentRuntimeState.disabled,
      );
    } catch (error) {
      _operationError =
          '无法${enabled ? '启用' : '禁用'} ${current.definition.displayName}：$error';
    }
    _notify();
  }

  /// 记录用户已阅读当前 Beta provider 的一次性兼容性说明。
  Future<void> acknowledgeBetaCompatibilityWarning() async {
    final current = _configForAgent(_selectedAgentId);
    if (current.extra['betaCompatibilityWarningAcknowledged'] == true) {
      return;
    }
    await providerController.updateProviderConfig(
      current.copyWith(
        extra: <String, Object?>{
          ...current.extra,
          'betaCompatibilityWarningAcknowledged': true,
        },
      ),
    );
    _notify();
  }

  /// 保存用户选择的 CLI 文件，并立即重新检测全部。
  Future<void> setExecutablePath(String path) async {
    final id = _selectedAgentId;
    final repo = repository;
    final current = _configForAgent(id);
    final updated = await repo.providerConfigForPath(
      current: current,
      path: path,
      timeoutSeconds: agent.timeoutSeconds,
    );
    await providerController.updateProviderConfig(
      updated,
      restartProvider: true,
    );
    _agents[id] = agent.copyWith(executablePath: path);
    _notify();
    await detect();
  }

  /// 保存 5～600 秒范围内的 Agent 超时设置。
  Future<bool> setTimeoutSeconds(int seconds) async {
    if (seconds < 5 || seconds > 600) {
      _operationError = '超时时间必须介于 5 到 600 秒。';
      _notify();
      return false;
    }
    final id = _selectedAgentId;
    final updated = repository.providerConfigWithTimeout(
      _configForAgent(id),
      seconds,
    );
    await providerController.updateProviderConfig(
      updated,
      restartProvider: true,
    );
    _agents[id] = agent.copyWith(timeoutSeconds: seconds);
    _operationError = null;
    _notify();
    return true;
  }

  /// 执行 initialize + model list 的无计费连接测试。
  Future<AgentConnectionTestResult?> testConnection() async {
    if (_testing) {
      return null;
    }
    _testing = true;
    _operationError = null;
    _notify();
    final id = _selectedAgentId;
    try {
      final result = await repository.testConnection(
        providerConfig: _configForAgent(id),
      );
      final sourceLabel = switch (id) {
        grokAgentProviderId => 'Grok ACP',
        cursorAgentProviderId => 'Cursor ACP',
        _ => 'Codex app-server',
      };
      _agents[id] = agent.copyWith(
        connectionTest: result.$1,
        models: result.$2,
        modelsUpdatedAt: result.$2.isEmpty
            ? agent.modelsUpdatedAt
            : DateTime.now(),
        modelSource: result.$2.isEmpty ? agent.modelSource : sourceLabel,
        runtimeState: !agent.enabled
            ? AgentRuntimeState.disabled
            : result.$1.success
            ? AgentRuntimeState.idle
            : AgentRuntimeState.error,
        errorStage: result.$1.success ? null : result.$1.failureStage,
        errorMessage: result.$1.success ? null : result.$1.message,
        errorDetails: result.$1.success ? null : result.$1.rawErrorSummary,
      );
      return result.$1;
    } catch (error) {
      _operationError = '连接测试失败：$error';
      return null;
    } finally {
      _testing = false;
      _notify();
    }
  }

  /// 加载当前选中 Agent 的配置文件。
  Future<AgentConfigurationDocument?> loadConfiguration() async {
    if (_loadingConfiguration) {
      return _configuration;
    }
    _loadingConfiguration = true;
    _operationError = null;
    _notify();
    try {
      _configuration = await repository.readConfiguration();
      return _configuration;
    } catch (error) {
      _operationError = '配置文件读取失败：$error';
      return null;
    } finally {
      _loadingConfiguration = false;
      _notify();
    }
  }

  String? validateConfiguration(String content) {
    return repository.validateConfiguration(content);
  }

  /// 安全保存配置；外部修改冲突由页面决定是否覆盖。
  Future<AgentConfigurationSaveResult> saveConfiguration(
    String content, {
    bool overwriteExternalChanges = false,
  }) async {
    final original = _configuration;
    if (original == null) {
      throw StateError('配置文件尚未加载');
    }
    _savingConfiguration = true;
    _operationError = null;
    _notify();
    try {
      final result = await repository.saveConfiguration(
        original: original,
        content: content,
        overwriteExternalChanges: overwriteExternalChanges,
      );
      _configuration = result.document;
      _agents[_selectedAgentId] = agent.copyWith(
        configExists: true,
        configModifiedAt: result.document.modifiedAt,
      );
      return result;
    } finally {
      _savingConfiguration = false;
      _notify();
    }
  }

  /// 刷新当前 Agent 磁盘日志。
  Future<List<AgentLogEntry>> loadLogs() async {
    if (_loadingLogs) {
      return logs;
    }
    _loadingLogs = true;
    _operationError = null;
    _notify();
    try {
      final paths = await repository.discoverLogPaths();
      _logs = await repository.readLogs(paths);
      _agents[_selectedAgentId] = agent.copyWith(logPaths: paths);
      return logs;
    } catch (error) {
      _operationError = '运行日志读取失败：$error';
      return const <AgentLogEntry>[];
    } finally {
      _loadingLogs = false;
      _notify();
    }
  }

  /// 同步对话 provider 运行状态到对应 Agent 行。
  void refreshRuntimeState() {
    if (_disposed) {
      return;
    }
    final activeId = providerController.activeProviderId;
    final current = _agents[activeId];
    if (current == null) {
      return;
    }
    final next = _runtimeState(activeId, current.enabled, current.runtimeState);
    if (next == current.runtimeState) {
      return;
    }
    _agents[activeId] = current.copyWith(runtimeState: next);
    _notify();
  }

  Future<void> _persistDetectionSummary(
    String agentId,
    AgentProviderConfig previous,
    ManagedAgent detected,
  ) async {
    final repo = _repositories[agentId];
    if (repo == null) {
      return;
    }
    // 始终以 sanitize 后的配置为基底，避免交叉污染的 cliPath/command 写回。
    var updated = _sanitizeProviderConfig(agentId, previous);
    final path = detected.executablePath;
    if (path != null && _pathBelongsToAgent(agentId, path)) {
      updated = await repo.providerConfigForPath(
        current: updated,
        path: path,
        timeoutSeconds: detected.timeoutSeconds,
      );
    }
    // 强制 id，防止 copyWith 路径把配置写到错误 provider 槽位。
    updated = updated.copyWith(
      id: agentId,
      extra: <String, Object?>{
        ...updated.extra,
        'detectedCurrentVersion': detected.currentVersion,
        'detectedLatestVersion': detected.latestVersion,
        'detectedAccountState': detected.accountState.name,
        'lastDetectedAt': detected.lastDetectedAt?.toIso8601String(),
        if (detected.connectionTest?.protocolVersion != null)
          'detectedProtocolVersion': detected.connectionTest!.protocolVersion,
        if (detected.connectionTest?.capabilityFingerprint != null)
          'cursorCapabilityFingerprint':
              detected.connectionTest!.capabilityFingerprint,
        if (path != null && _pathBelongsToAgent(agentId, path)) 'cliPath': path,
      },
    );
    final commandChanged =
        updated.command != previous.command ||
        !listEquals(updated.arguments, previous.arguments);
    await providerController.updateProviderConfig(
      updated,
      restartProvider:
          commandChanged && providerController.activeProviderId == agentId,
    );
  }

  ManagedAgent _restoreCachedAgent({
    required String agentId,
    required AgentProviderConfig config,
    required AgentCliManagementRepository repository,
  }) {
    final sanitized = _sanitizeProviderConfig(agentId, config);
    final extra = sanitized.extra;
    final accountName = extra['detectedAccountState'];
    final accountState = AgentAccountState.values.firstWhere(
      (state) => state.name == accountName,
      orElse: () => AgentAccountState.unknown,
    );
    final timeout = extra['timeoutSeconds'];
    final rawPath = extra['cliPath'] is String
        ? extra['cliPath'] as String
        : null;
    // 交叉污染的路径不展示、不视为已安装。
    final executablePath =
        rawPath != null && _pathBelongsToAgent(agentId, rawPath)
        ? rawPath
        : null;
    final currentVersion = executablePath == null
        ? null
        : (extra['detectedCurrentVersion'] is String
              ? extra['detectedCurrentVersion'] as String
              : null);
    final latestVersion = executablePath == null
        ? null
        : (extra['detectedLatestVersion'] is String
              ? extra['detectedLatestVersion'] as String
              : null);
    final definition =
        AgentDefinition.byId(agentId) ??
        ManagedAgent.forDefinition(
          definition: AgentDefinition.codex,
          enabled: sanitized.enabled,
        ).definition;

    return ManagedAgent.forDefinition(
      definition: definition,
      enabled: sanitized.enabled,
    ).copyWith(
      installationState: executablePath == null
          ? AgentInstallationState.unknown
          : AgentInstallationState.installed,
      executablePath: executablePath,
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      versionState: currentVersion == null || latestVersion == null
          ? (currentVersion == null
                ? AgentVersionState.unknown
                : AgentVersionState.current)
          : isNewerVersion(latestVersion, currentVersion)
          ? AgentVersionState.updateAvailable
          : AgentVersionState.current,
      accountState: accountState,
      configPath: repository.configPath,
      lastDetectedAt: DateTime.tryParse('${extra['lastDetectedAt'] ?? ''}'),
      timeoutSeconds: timeout is int ? timeout : 60,
    );
  }

  AgentProviderConfig _configForAgent(String agentId) {
    for (final provider in providerController.settings.providers) {
      if (provider.id == agentId) {
        return _sanitizeProviderConfig(agentId, provider);
      }
    }
    if (agentId == grokAgentProviderId) {
      return AgentProviderConfig.defaultGrok;
    }
    if (agentId == cursorAgentProviderId) {
      return AgentProviderConfig.defaultCursor;
    }
    return AgentProviderConfig.defaultCodex;
  }

  /// 纠正跨 provider 污染：错误的 kind / command / cliPath 会回落安全默认值。
  AgentProviderConfig _sanitizeProviderConfig(
    String agentId,
    AgentProviderConfig config,
  ) {
    if (agentId == grokAgentProviderId) {
      return _sanitizeGrokConfig(config);
    }
    if (agentId == defaultAgentProviderId) {
      return _sanitizeCodexConfig(config);
    }
    if (agentId == cursorAgentProviderId) {
      return _sanitizeCursorConfig(config);
    }
    return config.copyWith(id: agentId);
  }

  AgentProviderConfig _sanitizeGrokConfig(AgentProviderConfig config) {
    final extra = Map<String, Object?>.from(config.extra);
    final cliPath = extra['cliPath'] is String
        ? extra['cliPath'] as String
        : null;
    final commandIsPath = _looksLikeFilePath(config.command);
    final commandWrong = commandIsPath && !looksLikeGrokCliPath(config.command);
    final cliPathWrong = cliPath != null && !looksLikeGrokCliPath(cliPath);
    final kindWrong = config.kind != AgentProviderKind.acp;

    if (cliPathWrong) {
      extra.remove('cliPath');
      extra.remove('detectedCurrentVersion');
      extra.remove('detectedLatestVersion');
    }

    final needsDefaultCommand =
        kindWrong ||
        commandWrong ||
        config.command.trim().isEmpty ||
        (cliPathWrong && config.command == cliPath);

    return config.copyWith(
      id: grokAgentProviderId,
      displayName: AgentProviderConfig.defaultGrok.displayName,
      kind: AgentProviderKind.acp,
      command: needsDefaultCommand
          ? AgentProviderConfig.defaultGrok.command
          : config.command,
      arguments: kindWrong || needsDefaultCommand
          ? AgentProviderConfig.defaultGrok.arguments
          : config.arguments,
      extra: extra,
    );
  }

  AgentProviderConfig _sanitizeCodexConfig(AgentProviderConfig config) {
    final extra = Map<String, Object?>.from(config.extra);
    final cliPath = extra['cliPath'] is String
        ? extra['cliPath'] as String
        : null;
    final commandIsPath = _looksLikeFilePath(config.command);
    final commandWrong =
        commandIsPath && !looksLikeCodexCliPath(config.command);
    final cliPathWrong = cliPath != null && !looksLikeCodexCliPath(cliPath);
    final kindWrong = config.kind != AgentProviderKind.codexAppServer;

    if (cliPathWrong) {
      extra.remove('cliPath');
      extra.remove('detectedCurrentVersion');
      extra.remove('detectedLatestVersion');
    }

    final needsDefaultCommand =
        kindWrong ||
        commandWrong ||
        config.command.trim().isEmpty ||
        (cliPathWrong && config.command == cliPath);

    return config.copyWith(
      id: defaultAgentProviderId,
      displayName: AgentProviderConfig.defaultCodex.displayName,
      kind: AgentProviderKind.codexAppServer,
      command: needsDefaultCommand
          ? AgentProviderConfig.defaultCodex.command
          : config.command,
      arguments: kindWrong || needsDefaultCommand
          ? AgentProviderConfig.defaultCodex.arguments
          : config.arguments,
      extra: extra,
    );
  }

  AgentProviderConfig _sanitizeCursorConfig(AgentProviderConfig config) {
    final extra = Map<String, Object?>.from(config.extra);
    final cliPath = extra['cliPath'] is String
        ? extra['cliPath'] as String
        : null;
    final commandIsPath = _looksLikeFilePath(config.command);
    final commandWrong =
        commandIsPath && !looksLikeCursorCliPath(config.command);
    final cliPathWrong = cliPath != null && !looksLikeCursorCliPath(cliPath);
    final kindWrong = config.kind != AgentProviderKind.cursorAcp;

    if (cliPathWrong) {
      extra.remove('cliPath');
      extra.remove('detectedCurrentVersion');
      extra.remove('detectedLatestVersion');
    }
    final needsDefaultCommand =
        kindWrong ||
        commandWrong ||
        config.command.trim().isEmpty ||
        (cliPathWrong && config.command == cliPath);
    return config.copyWith(
      id: cursorAgentProviderId,
      displayName: AgentProviderConfig.defaultCursor.displayName,
      kind: AgentProviderKind.cursorAcp,
      command: needsDefaultCommand
          ? AgentProviderConfig.defaultCursor.command
          : config.command,
      arguments: kindWrong || needsDefaultCommand
          ? AgentProviderConfig.defaultCursor.arguments
          : config.arguments,
      extra: extra,
    );
  }

  bool _pathBelongsToAgent(String agentId, String path) {
    if (agentId == grokAgentProviderId) {
      return looksLikeGrokCliPath(path);
    }
    if (agentId == defaultAgentProviderId) {
      return looksLikeCodexCliPath(path);
    }
    if (agentId == cursorAgentProviderId) {
      return looksLikeCursorCliPath(path);
    }
    return true;
  }

  bool _looksLikeFilePath(String value) {
    return value.contains('/') ||
        value.contains('\\') ||
        value.contains(':') ||
        value.endsWith('.exe') ||
        value.endsWith('.cmd') ||
        value.endsWith('.bat') ||
        value.endsWith('.ps1');
  }

  AgentRuntimeState _runtimeState(
    String agentId,
    bool enabled,
    AgentRuntimeState fallback,
  ) {
    if (!enabled) {
      return AgentRuntimeState.disabled;
    }
    // 仅 active provider 映射 live 运行态。
    if (agentId != providerController.activeProviderId) {
      return fallback == AgentRuntimeState.disabled
          ? AgentRuntimeState.notRunning
          : fallback;
    }
    final live = runtimeStateProvider?.call();
    if (live == null || live == AgentRuntimeState.notRunning) {
      return fallback == AgentRuntimeState.disabled
          ? AgentRuntimeState.notRunning
          : fallback;
    }
    return live;
  }

  void _handleProviderSettingsChanged() {
    if (_disposed) {
      return;
    }
    var changed = false;
    for (final id in _repositories.keys) {
      final config = _configForAgent(id);
      final current = _agents[id];
      if (current == null) {
        continue;
      }
      final timeout = config.extra['timeoutSeconds'];
      final timeoutSeconds = timeout is int ? timeout : 60;
      if (current.enabled == config.enabled &&
          current.timeoutSeconds == timeoutSeconds) {
        continue;
      }
      _agents[id] = current.copyWith(
        enabled: config.enabled,
        timeoutSeconds: timeoutSeconds,
        runtimeState: config.enabled
            ? AgentRuntimeState.notRunning
            : AgentRuntimeState.disabled,
      );
      changed = true;
    }
    if (changed) {
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    providerController.removeListener(_handleProviderSettingsChanged);
    runtimeListenable?.removeListener(refreshRuntimeState);
    super.dispose();
  }
}
