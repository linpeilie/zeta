import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent_management/data/codex_agent_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/ui/features/ide/view_models/active_agent_provider_controller.dart';

/// Agent 管理页面的应用层协调器。
class AgentManagementController extends ChangeNotifier {
  AgentManagementController({
    required this.repository,
    required this.providerController,
    this.runtimeStateProvider,
    this.runtimeListenable,
  }) : _agent = ManagedAgent.codex(
         enabled: providerController.activeProviderConfig.enabled,
       ) {
    providerController.addListener(_handleProviderSettingsChanged);
    runtimeListenable?.addListener(refreshRuntimeState);
  }

  final CodexAgentManagementRepository repository;
  final ActiveAgentProviderController providerController;
  final AgentRuntimeState Function()? runtimeStateProvider;
  final Listenable? runtimeListenable;

  ManagedAgent _agent;
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

  ManagedAgent get agent => _agent;
  AgentDetectionProgress? get detectionProgress => _detectionProgress;
  AgentConfigurationDocument? get configuration => _configuration;
  List<AgentLogEntry> get logs => List<AgentLogEntry>.unmodifiable(_logs);
  bool get initialized => _initialized;
  bool get detecting => _detecting;
  bool get testing => _testing;
  bool get loadingConfiguration => _loadingConfiguration;
  bool get savingConfiguration => _savingConfiguration;
  bool get loadingLogs => _loadingLogs;
  String? get operationError => _operationError;

  /// 加载持久化 provider 配置和上一次检测摘要。
  Future<void> initialize({bool autoDetect = false}) async {
    if (_initialized) {
      if (autoDetect && !_detecting) {
        unawaited(detect());
      }
      return;
    }
    await providerController.loadSettings();
    _restoreCachedAgent(providerController.activeProviderConfig);
    _initialized = true;
    _notify();
    if (autoDetect) {
      unawaited(detect());
    }
  }

  /// 自动检测 Codex，并逐步更新 UI。
  Future<void> detect() async {
    if (_detecting) {
      return;
    }
    await initialize();
    _detecting = true;
    _operationError = null;
    _notify();
    try {
      final config = providerController.activeProviderConfig;
      final detected = await repository.detect(
        providerConfig: config,
        enabled: config.enabled,
        onProgress: (progress, partial) {
          _detectionProgress = progress;
          _agent = partial.copyWith(
            runtimeState: _runtimeState(partial.enabled, partial.runtimeState),
          );
          _notify();
        },
      );
      _agent = detected.copyWith(
        runtimeState: _runtimeState(detected.enabled, detected.runtimeState),
      );
      await _persistDetectionSummary(config, detected);
    } catch (error) {
      _operationError = 'Agent 检测未能完成：$error';
    } finally {
      _detecting = false;
      _notify();
    }
  }

  /// 启用或禁用 Codex；禁用会终止当前 provider 实例。
  Future<void> setEnabled(bool enabled) async {
    if (_agent.enabled == enabled) {
      return;
    }
    _operationError = null;
    try {
      await providerController.setProviderEnabled(
        AgentDefinition.codex.id,
        enabled,
      );
      _agent = _agent.copyWith(
        enabled: enabled,
        runtimeState: enabled
            ? AgentRuntimeState.notRunning
            : AgentRuntimeState.disabled,
      );
    } catch (error) {
      _operationError = '无法${enabled ? '启用' : '禁用'} Codex：$error';
    }
    _notify();
  }

  /// 保存用户选择的 CLI 文件，并立即重新检测。
  Future<void> setExecutablePath(String path) async {
    final current = providerController.activeProviderConfig;
    final updated = await repository.providerConfigForPath(
      current: current,
      path: path,
      timeoutSeconds: _agent.timeoutSeconds,
    );
    await providerController.updateProviderConfig(
      updated,
      restartProvider: true,
    );
    _agent = _agent.copyWith(executablePath: path);
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
    final updated = repository.providerConfigWithTimeout(
      providerController.activeProviderConfig,
      seconds,
    );
    await providerController.updateProviderConfig(
      updated,
      restartProvider: true,
    );
    _agent = _agent.copyWith(timeoutSeconds: seconds);
    _operationError = null;
    _notify();
    return true;
  }

  /// 执行 initialize + model/list 的无计费连接测试。
  Future<AgentConnectionTestResult?> testConnection() async {
    if (_testing) {
      return null;
    }
    _testing = true;
    _operationError = null;
    _notify();
    try {
      final result = await repository.testConnection(
        providerConfig: providerController.activeProviderConfig,
      );
      _agent = _agent.copyWith(
        connectionTest: result.$1,
        models: result.$2,
        modelsUpdatedAt: result.$2.isEmpty
            ? _agent.modelsUpdatedAt
            : DateTime.now(),
        modelSource: result.$2.isEmpty
            ? _agent.modelSource
            : 'Codex app-server',
        runtimeState: !_agent.enabled
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

  /// 加载 Codex config.toml。
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
      _agent = _agent.copyWith(
        configExists: true,
        configModifiedAt: result.document.modifiedAt,
      );
      return result;
    } finally {
      _savingConfiguration = false;
      _notify();
    }
  }

  /// 刷新 Codex 自身磁盘日志。
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
      _agent = _agent.copyWith(logPaths: paths);
      return logs;
    } catch (error) {
      _operationError = '运行日志读取失败：$error';
      return const <AgentLogEntry>[];
    } finally {
      _loadingLogs = false;
      _notify();
    }
  }

  /// 同步当前对话 provider 的运行状态。
  void refreshRuntimeState() {
    if (_disposed) {
      return;
    }
    final next = _runtimeState(_agent.enabled, _agent.runtimeState);
    if (next == _agent.runtimeState) {
      return;
    }
    _agent = _agent.copyWith(runtimeState: next);
    _notify();
  }

  Future<void> _persistDetectionSummary(
    AgentProviderConfig previous,
    ManagedAgent detected,
  ) async {
    var updated = previous;
    final path = detected.executablePath;
    if (path != null) {
      updated = await repository.providerConfigForPath(
        current: previous,
        path: path,
        timeoutSeconds: detected.timeoutSeconds,
      );
    }
    updated = updated.copyWith(
      extra: <String, Object?>{
        ...updated.extra,
        'detectedCurrentVersion': detected.currentVersion,
        'detectedLatestVersion': detected.latestVersion,
        'detectedAccountState': detected.accountState.name,
        'lastDetectedAt': detected.lastDetectedAt?.toIso8601String(),
      },
    );
    final commandChanged =
        updated.command != previous.command ||
        !listEquals(updated.arguments, previous.arguments);
    await providerController.updateProviderConfig(
      updated,
      restartProvider: commandChanged,
    );
  }

  void _restoreCachedAgent(AgentProviderConfig config) {
    final extra = config.extra;
    final accountName = extra['detectedAccountState'];
    final accountState = AgentAccountState.values.firstWhere(
      (state) => state.name == accountName,
      orElse: () => AgentAccountState.unknown,
    );
    final timeout = extra['timeoutSeconds'];
    final executablePath = extra['cliPath'] is String
        ? extra['cliPath'] as String
        : null;
    final currentVersion = extra['detectedCurrentVersion'] is String
        ? extra['detectedCurrentVersion'] as String
        : null;
    final latestVersion = extra['detectedLatestVersion'] is String
        ? extra['detectedLatestVersion'] as String
        : null;
    _agent = ManagedAgent.codex(enabled: config.enabled).copyWith(
      installationState: executablePath == null
          ? AgentInstallationState.unknown
          : AgentInstallationState.installed,
      executablePath: executablePath,
      currentVersion: extra['detectedCurrentVersion'] is String
          ? currentVersion
          : null,
      latestVersion: latestVersion,
      versionState: currentVersion == null || latestVersion == null
          ? AgentVersionState.unknown
          : isNewerVersion(latestVersion, currentVersion)
          ? AgentVersionState.updateAvailable
          : AgentVersionState.current,
      accountState: accountState,
      configPath: repository.configPath,
      lastDetectedAt: DateTime.tryParse('${extra['lastDetectedAt'] ?? ''}'),
      timeoutSeconds: timeout is int ? timeout : 60,
    );
  }

  AgentRuntimeState _runtimeState(bool enabled, AgentRuntimeState fallback) {
    if (!enabled) {
      return AgentRuntimeState.disabled;
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
    final config = providerController.activeProviderConfig;
    final enabled = config.enabled;
    final timeout = config.extra['timeoutSeconds'];
    final timeoutSeconds = timeout is int ? timeout : 60;
    if (_agent.enabled == enabled && _agent.timeoutSeconds == timeoutSeconds) {
      return;
    }
    _agent = _agent.copyWith(
      enabled: enabled,
      timeoutSeconds: timeoutSeconds,
      runtimeState: enabled
          ? AgentRuntimeState.notRunning
          : AgentRuntimeState.disabled,
    );
    _notify();
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
