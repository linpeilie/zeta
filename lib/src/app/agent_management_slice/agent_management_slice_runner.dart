import 'dart:async';

import 'package:zeta_agent_core/zeta_agent_core.dart';
// WP-C 过渡白名单：WP-D 迁入插件或通过贡献能力消除。
import 'package:zeta_agent_provider_claude_code/zeta_agent_provider_claude_code.dart';
import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_effect.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_store.dart';
import 'package:zeta/src/features/agent_management/data/codex_agent_management_repository.dart'
    show isNewerVersion;
import 'package:zeta/src/features/agent_management/domain/agent_cli_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_text_catalog.dart';

typedef AgentManagementRuntimeSnapshot = ({
  String activeAgentId,
  AgentRuntimeState runtimeState,
});

typedef AgentManagementRuntimeSnapshotProvider =
    AgentManagementRuntimeSnapshot Function();

/// Agent management MVI 的 app 组合层 effect runner。
///
/// repository、Provider settings 写入与 runtime ingress 都停留在这一层；store
/// 只接收 typed result intent，不保存原始异常对象。
final class AgentManagementSliceRunnerAdapter
    implements AgentManagementSliceEffectRunner {
  AgentManagementSliceRunnerAdapter({
    required Map<String, AgentCliManagementRepository> repositories,
    required AgentProviderSettingsPort providerSettings,
    required AgentManagementSliceStore store,
    required AgentManagementTextCatalog textCatalog,
    required AgentManagementRuntimeSnapshotProvider runtimeSnapshotProvider,
    DateTime Function()? now,
  }) : this._(
         repositories,
         providerSettings,
         store,
         textCatalog,
         runtimeSnapshotProvider,
         now ?? DateTime.now,
       );

  AgentManagementSliceRunnerAdapter._(
    Map<String, AgentCliManagementRepository> repositories,
    this._providerSettings,
    this._store,
    this._textCatalog,
    this._runtimeSnapshotProvider,
    this._now,
  ) : _repositories = Map<String, AgentCliManagementRepository>.unmodifiable(
        repositories,
      );

  final Map<String, AgentCliManagementRepository> _repositories;
  final AgentProviderSettingsPort _providerSettings;
  final AgentManagementSliceStore _store;
  final AgentManagementTextCatalog _textCatalog;
  final AgentManagementRuntimeSnapshotProvider _runtimeSnapshotProvider;
  final DateTime Function() _now;

  @override
  void run(AgentManagementSliceEffect effect) {
    switch (effect) {
      case ManagementInitializeEffect():
        unawaited(_initialize(effect));
      case DetectAgentsEffect():
        unawaited(_detect(effect));
      case UpdateProviderEnabledEffect():
        unawaited(_updateProviderEnabled(effect));
      case UpdateAccountDataEnrichmentEffect():
        unawaited(_updateAccountDataEnrichment(effect));
      case TestAgentConnectionEffect():
        unawaited(_testConnection(effect));
      case LoadAgentConfigurationEffect():
        unawaited(_loadConfiguration(effect));
      case SaveAgentConfigurationEffect():
        unawaited(_saveConfiguration(effect));
      case LoadAgentLogsEffect():
        unawaited(_loadLogs(effect));
    }
  }

  @override
  String? validateConfiguration(String agentId, String content) {
    return _repository(agentId).validateConfiguration(content);
  }

  Future<void> _initialize(ManagementInitializeEffect effect) async {
    try {
      final settings = await _providerSettings.loadSettings();
      final agents = <String, ManagedAgent>{};
      for (final entry in _repositories.entries) {
        agents[entry.key] = _restoreCachedAgent(
          agentId: entry.key,
          config: _configForAgent(settings, entry.value),
          repository: entry.value,
        );
      }
      _store.initializationSucceeded(effect.operationId, settings, agents);
    } catch (error, stackTrace) {
      _store.initializationFailed(effect.operationId, error, stackTrace);
    }
  }

  Future<void> _detect(DetectAgentsEffect effect) async {
    try {
      final ids = _repositories.keys.toList(growable: false);
      var index = 0;
      for (final id in ids) {
        index += 1;
        final repository = _repository(id);
        _store.detectionStarted(effect.operationId, id);
        final config = _configForAgent(_providerSettings.settings, repository);
        final detected = await repository.detect(
          providerConfig: config,
          enabled: config.enabled,
          onProgress: (progress, partial) {
            final mappedProgress = AgentDetectionProgress(
              completed: progress.completed,
              total: progress.total,
              message: _textCatalog.detectionProgress(
                index: '$index',
                total: '${ids.length}',
                name: partial.definition.displayName,
                message: progress.message,
              ),
            );
            _store.detectionProgressReported(
              effect.operationId,
              id,
              mappedProgress,
              partial.copyWith(
                runtimeState: _runtimeState(
                  id,
                  partial.enabled,
                  partial.runtimeState,
                ),
              ),
            );
          },
        );
        final mapped = detected.copyWith(
          runtimeState: _runtimeState(
            id,
            detected.enabled,
            detected.runtimeState,
          ),
        );
        _store.agentDetected(effect.operationId, id, mapped);
        await _persistDetectionSummary(id, config, mapped);
      }
      _store.detectionCompleted(effect.operationId);
    } catch (error) {
      _store.detectionFailed(
        effect.operationId,
        _textCatalog.detectionIncomplete(error),
      );
    }
  }

  Future<void> _updateProviderEnabled(
    UpdateProviderEnabledEffect effect,
  ) async {
    final repository = _repository(effect.agentId);
    try {
      await _providerSettings.setProviderEnabled(
        effect.agentId,
        effect.enabled,
      );
      _store.providerEnabledUpdated(
        effect.operationId,
        effect.agentId,
        effect.enabled,
        _providerSettings.settings,
      );
    } catch (error) {
      _store.providerEnabledUpdateFailed(
        effect.operationId,
        effect.agentId,
        _textCatalog.cannotToggleEnabled(
          enabled: effect.enabled,
          displayName:
              AgentDefinition.byId(effect.agentId)?.displayName ??
              repository.agentId,
          error: error,
        ),
      );
    }
  }

  Future<void> _updateAccountDataEnrichment(
    UpdateAccountDataEnrichmentEffect effect,
  ) async {
    final repository = _repository(effect.agentId);
    if (!(_descriptor(
          repository,
        )?.managementCapabilities.supportsAccountDataEnrichment ??
        false)) {
      _store.accountDataEnrichmentUpdateFailed(
        effect.operationId,
        effect.agentId,
        _textCatalog.accountDataEnrichmentSaveFailed(
          UnsupportedError(
            'Agent ${effect.agentId} does not support account data enrichment',
          ),
        ),
      );
      return;
    }
    try {
      final current = _configForAgent(_providerSettings.settings, repository);
      final extra = Map<String, Object?>.from(current.extra);
      if (effect.enabled) {
        extra.remove(claudeCodeAccountDataEnrichmentKey);
      } else {
        extra[claudeCodeAccountDataEnrichmentKey] = false;
      }
      await _providerSettings.updateProviderConfig(
        current.copyWith(extra: extra),
      );
      _store.accountDataEnrichmentUpdated(
        effect.operationId,
        effect.agentId,
        _providerSettings.settings,
      );
    } catch (error) {
      _store.accountDataEnrichmentUpdateFailed(
        effect.operationId,
        effect.agentId,
        _textCatalog.accountDataEnrichmentSaveFailed(error),
      );
    }
  }

  Future<void> _testConnection(TestAgentConnectionEffect effect) async {
    final repository = _repository(effect.agentId);
    try {
      final result = await repository.testConnection(
        providerConfig: _configForAgent(_providerSettings.settings, repository),
      );
      _store.connectionTestSucceeded(
        operationId: effect.operationId,
        agentId: effect.agentId,
        result: result.$1,
        models: result.$2,
        modelSource:
            _descriptor(repository)?.connectionModelSourceLabel ??
            repository.agentId,
        modelsUpdatedAt: _now(),
      );
    } catch (error) {
      _store.connectionTestFailed(
        effect.operationId,
        effect.agentId,
        _textCatalog.connectionTestFailed(error),
      );
    }
  }

  Future<void> _loadConfiguration(LoadAgentConfigurationEffect effect) async {
    try {
      final document = await _repository(effect.agentId).readConfiguration();
      _store.configurationLoaded(effect.operationId, effect.agentId, document);
    } catch (error) {
      _store.configurationLoadFailed(
        effect.operationId,
        effect.agentId,
        _textCatalog.configurationReadFailed(error),
      );
    }
  }

  Future<void> _saveConfiguration(SaveAgentConfigurationEffect effect) async {
    try {
      final result = await _repository(effect.agentId).saveConfiguration(
        original: effect.original,
        content: effect.content,
        overwriteExternalChanges: effect.overwriteExternalChanges,
      );
      _store.configurationSaved(
        effect.operationId,
        effect.agentId,
        effect.original.signature,
        result,
      );
    } catch (error, stackTrace) {
      _store.configurationSaveFailed(
        effect.operationId,
        effect.agentId,
        error,
        stackTrace,
      );
    }
  }

  Future<void> _loadLogs(LoadAgentLogsEffect effect) async {
    try {
      final repository = _repository(effect.agentId);
      final paths = await repository.discoverLogPaths();
      final logs = await repository.readLogs(paths);
      _store.logsLoaded(effect.operationId, effect.agentId, paths, logs);
    } catch (error) {
      _store.logsLoadFailed(
        effect.operationId,
        effect.agentId,
        _textCatalog.logsReadFailed(error),
      );
    }
  }

  Future<void> _persistDetectionSummary(
    String agentId,
    AgentProviderConfig previous,
    ManagedAgent detected,
  ) async {
    final repository = _repository(agentId);
    var updated = _sanitizeProviderConfig(previous, repository);
    final path = detected.executablePath;
    if (path != null && _acceptsExecutablePath(repository, path)) {
      updated = await repository.providerConfigForPath(
        current: updated,
        path: path,
      );
    }
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
        if (path != null && _acceptsExecutablePath(repository, path))
          'cliPath': path,
      },
    );
    final commandChanged =
        updated.command != previous.command ||
        !zetaListEquals(updated.arguments, previous.arguments);
    await _providerSettings.updateProviderConfig(
      updated,
      restartProvider:
          commandChanged && _providerSettings.activeProviderId == agentId,
    );
  }

  ManagedAgent _restoreCachedAgent({
    required String agentId,
    required AgentProviderConfig config,
    required AgentCliManagementRepository repository,
  }) {
    final sanitized = _sanitizeProviderConfig(config, repository);
    final extra = sanitized.extra;
    final accountName = extra['detectedAccountState'];
    final accountState = AgentAccountState.values.firstWhere(
      (state) => state.name == accountName,
      orElse: () => AgentAccountState.unknown,
    );
    final rawPath = extra['cliPath'] is String
        ? extra['cliPath'] as String
        : null;
    final executablePath =
        rawPath != null && _acceptsExecutablePath(repository, rawPath)
        ? rawPath
        : null;
    final currentVersion = executablePath == null
        ? null
        : extra['detectedCurrentVersion'] is String
        ? extra['detectedCurrentVersion'] as String
        : null;
    final latestVersion = executablePath == null
        ? null
        : extra['detectedLatestVersion'] is String
        ? extra['detectedLatestVersion'] as String
        : null;
    final definition =
        AgentDefinition.byId(agentId) ??
        _store.state.agentsById[agentId]?.definition ??
        AgentDefinition(
          id: agentId,
          displayName: agentId,
          vendor: 'Unknown',
          commandName: agentId,
          protocol: 'unknown',
          transport: 'unknown',
          configFormat: 'unknown',
          defaultConfigRelativePath: '',
          npmPackage: '',
        );
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
          ? currentVersion == null
                ? AgentVersionState.unknown
                : AgentVersionState.current
          : isNewerVersion(latestVersion, currentVersion)
          ? AgentVersionState.updateAvailable
          : AgentVersionState.current,
      accountState: accountState,
      configPath: repository.configPath,
      lastDetectedAt: DateTime.tryParse('${extra['lastDetectedAt'] ?? ''}'),
    );
  }

  AgentProviderConfig _configForAgent(
    AgentProviderSettings settings,
    AgentCliManagementRepository repository,
  ) {
    for (final provider in settings.providers) {
      if (provider.id == repository.agentId) {
        return _sanitizeProviderConfig(provider, repository);
      }
    }
    return _descriptor(repository)?.defaultProviderConfig ??
        defaultCodexAgentProviderConfig.copyWith(
          id: repository.agentId,
          displayName:
              AgentDefinition.byId(repository.agentId)?.displayName ??
              repository.agentId,
        );
  }

  AgentProviderConfig _sanitizeProviderConfig(
    AgentProviderConfig config,
    AgentCliManagementRepository repository,
  ) {
    final descriptor = _descriptor(repository);
    if (descriptor == null) {
      return config.copyWith(id: repository.agentId);
    }
    final defaults = descriptor.defaultProviderConfig;
    final extra = Map<String, Object?>.from(config.extra)
      ..remove('timeoutSeconds');
    final cliPath = extra['cliPath'] is String
        ? extra['cliPath'] as String
        : null;
    final commandIsPath = _looksLikeFilePath(config.command);
    final commandWrong =
        commandIsPath && !descriptor.acceptsExecutablePath(config.command);
    final cliPathWrong =
        cliPath != null && !descriptor.acceptsExecutablePath(cliPath);
    final kindWrong = config.kind != defaults.kind;
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
      id: repository.agentId,
      displayName: defaults.displayName,
      kind: defaults.kind,
      command: needsDefaultCommand ? defaults.command : config.command,
      arguments: kindWrong || needsDefaultCommand
          ? defaults.arguments
          : config.arguments,
      extra: extra,
    );
  }

  AgentRuntimeState _runtimeState(
    String agentId,
    bool enabled,
    AgentRuntimeState fallback,
  ) {
    if (!enabled) {
      return AgentRuntimeState.disabled;
    }
    final snapshot = _runtimeSnapshotProvider();
    if (snapshot.activeAgentId != agentId) {
      return fallback == AgentRuntimeState.disabled
          ? AgentRuntimeState.notRunning
          : fallback;
    }
    final live = snapshot.runtimeState;
    if (live == AgentRuntimeState.notRunning) {
      return fallback == AgentRuntimeState.disabled
          ? AgentRuntimeState.notRunning
          : fallback;
    }
    return live;
  }

  AgentCliManagementRepository _repository(String agentId) {
    final repository = _repositories[agentId];
    if (repository == null) {
      throw UnsupportedError(
        'Agent $agentId does not provide CLI management capabilities',
      );
    }
    return repository;
  }

  AgentCliManagementDescriptor? _descriptor(
    AgentCliManagementRepository repository,
  ) => repository is AgentCliManagementDescriptor
      ? repository as AgentCliManagementDescriptor
      : null;

  bool _acceptsExecutablePath(
    AgentCliManagementRepository repository,
    String path,
  ) => _descriptor(repository)?.acceptsExecutablePath(path) ?? true;
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
