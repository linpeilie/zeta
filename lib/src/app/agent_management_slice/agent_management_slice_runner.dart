import 'dart:async';

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_effect.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_dependencies.dart';
import 'package:zeta_agent_provider_sdk/zeta_agent_provider_sdk.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';

/// Agent management MVI 的 app 组合层 effect runner。
///
/// repository、Provider settings 写入与 runtime ingress 都停留在这一层；具名 result sink
/// 只接收类型化结果，不保存原始异常对象。
final class AgentManagementSliceRunnerAdapter
    implements AgentManagementSliceEffectRunner {
  AgentManagementSliceRunnerAdapter({
    required Map<String, AgentCliManagementRepository> repositories,
    required Map<String, AgentDefinition> definitions,
    required AgentProviderSettingsPort providerSettings,
    required AgentManagementResultSink sink,
    required AgentManagementTextCatalog textCatalog,
    DateTime Function()? now,
  }) : this._(
         repositories,
         definitions,
         providerSettings,
         sink,
         textCatalog,
         now ?? DateTime.now,
       );

  AgentManagementSliceRunnerAdapter._(
    Map<String, AgentCliManagementRepository> repositories,
    Map<String, AgentDefinition> definitions,
    this._providerSettings,
    this._sink,
    this._textCatalog,
    this._now,
  ) : _definitions = Map.unmodifiable(definitions),
      _repositories = Map<String, AgentCliManagementRepository>.unmodifiable(
        repositories,
      );

  final Map<String, AgentDefinition> _definitions;
  final Map<String, AgentCliManagementRepository> _repositories;
  final AgentProviderSettingsPort _providerSettings;
  final AgentManagementResultSink _sink;
  final AgentManagementTextCatalog _textCatalog;
  final DateTime Function() _now;

  @override
  Future<void> run(AgentManagementSliceEffect effect) {
    if (_sink.isClosed) return Future<void>.value();
    switch (effect) {
      case ManagementInitializeEffect():
        return _initialize(effect);
      case DetectAgentsEffect():
        return _detect(effect);
      case UpdateProviderEnabledEffect():
        return _updateProviderEnabled(effect);
      case UpdateAccountDataEnrichmentEffect():
        return _updateAccountDataEnrichment(effect);
      case TestAgentConnectionEffect():
        return _testConnection(effect);
      case LoadAgentConfigurationEffect():
        return _loadConfiguration(effect);
      case SaveAgentConfigurationEffect():
        return _saveConfiguration(effect);
      case LoadAgentLogsEffect():
        return _loadLogs(effect);
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
      _sink.initializationSucceeded(effect.operationId, settings, agents);
    } catch (error, stackTrace) {
      _sink.initializationFailed(effect.operationId, error, stackTrace);
    }
  }

  Future<void> _detect(DetectAgentsEffect effect) async {
    try {
      final ids = _repositories.keys.toList(growable: false);
      var index = 0;
      for (final id in ids) {
        if (_sink.isClosed) return;
        index += 1;
        final repository = _repository(id);
        _sink.detectionStarted(effect.operationId, id);
        final config = _configForAgent(_providerSettings.settings, repository);
        if (_sink.isClosed) return;
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
            _sink.detectionProgressReported(
              effect.operationId,
              id,
              mappedProgress,
              partial,
            );
          },
        );
        if (_sink.isClosed) return;
        final mapped = detected;
        _sink.agentDetected(effect.operationId, id, mapped);
        if (_sink.isClosed) return;
        await _persistDetectionSummary(id, config, mapped);
      }
      _sink.detectionCompleted(effect.operationId);
    } catch (error) {
      _sink.detectionFailed(
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
      _sink.providerEnabledUpdated(
        effect.operationId,
        effect.agentId,
        effect.enabled,
        _providerSettings.settings,
      );
    } catch (error) {
      _sink.providerEnabledUpdateFailed(
        effect.operationId,
        effect.agentId,
        _textCatalog.cannotToggleEnabled(
          enabled: effect.enabled,
          displayName:
              _definitions[effect.agentId]?.displayName ?? repository.agentId,
          error: error,
        ),
      );
    }
  }

  Future<void> _updateAccountDataEnrichment(
    UpdateAccountDataEnrichmentEffect effect,
  ) async {
    final repository = _repository(effect.agentId);
    final key = _descriptor(
      repository,
    )?.managementCapabilities.accountDataEnrichmentExtraKey;
    if (key == null) {
      _sink.accountDataEnrichmentUpdateFailed(
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
        extra.remove(key);
      } else {
        extra[key] = false;
      }
      await _providerSettings.updateProviderConfig(
        current.copyWith(extra: extra),
      );
      _sink.accountDataEnrichmentUpdated(
        effect.operationId,
        effect.agentId,
        _providerSettings.settings,
      );
    } catch (error) {
      _sink.accountDataEnrichmentUpdateFailed(
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
      _sink.connectionTestSucceeded(
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
      _sink.connectionTestFailed(
        effect.operationId,
        effect.agentId,
        _textCatalog.connectionTestFailed(error),
      );
    }
  }

  Future<void> _loadConfiguration(LoadAgentConfigurationEffect effect) async {
    try {
      final document = await _repository(effect.agentId).readConfiguration();
      _sink.configurationLoaded(effect.operationId, effect.agentId, document);
    } catch (error) {
      _sink.configurationLoadFailed(
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
      _sink.configurationSaved(
        effect.operationId,
        effect.agentId,
        effect.original.signature,
        result,
      );
    } catch (error, stackTrace) {
      _sink.configurationSaveFailed(
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
      if (_sink.isClosed) return;
      final logs = await repository.readLogs(paths);
      _sink.logsLoaded(effect.operationId, effect.agentId, paths, logs);
    } catch (error) {
      _sink.logsLoadFailed(
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
    if (_sink.isClosed) return;
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
        _definitions[agentId] ??
        _sink.current.agentsById[agentId]?.definition ??
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
        AgentProviderConfig(
          kind:
              zetaAgentProviderDefinitionCatalog
                  .definitionForProviderId(repository.agentId)
                  ?.providerType ??
              const AgentProviderTypeId('unknown'),
          command: repository.agentId,
          id: repository.agentId,
          displayName:
              _definitions[repository.agentId]?.displayName ??
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
