import 'agent_management_repository_config.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_detection_state.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_detection_port.dart';
import 'agent_management_detection_projection.dart';
import 'agent_management_details_catalog.dart';
import 'dart:async';

import 'package:zeta_agent_core/zeta_agent_core.dart';

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
    required AgentManagementDetectionPort detectionPort,
    required AppAgentManagementDetailsCatalog detailsCatalog,
    DateTime Function()? now,
  }) : this._(
         repositories,
         definitions,
         providerSettings,
         sink,
         textCatalog,
         detectionPort,
         detailsCatalog,
         now ?? DateTime.now,
       );

  AgentManagementSliceRunnerAdapter._(
    Map<String, AgentCliManagementRepository> repositories,
    Map<String, AgentDefinition> definitions,
    this._providerSettings,
    this._sink,
    this._textCatalog,
    this._detectionPort,
    this._detailsCatalog,
    this._now,
  ) : _definitions = Map.unmodifiable(definitions),
      _repositories = Map<String, AgentCliManagementRepository>.unmodifiable(
        repositories,
      );

  final Map<String, AgentDefinition> _definitions;
  late final _config = AgentManagementRepositoryConfig(_definitions);
  final Map<String, AgentCliManagementRepository> _repositories;
  final AgentProviderSettingsPort _providerSettings;
  final AgentManagementResultSink _sink;
  final AgentManagementTextCatalog _textCatalog;
  final DateTime Function() _now;
  final AgentManagementDetectionPort _detectionPort;
  final AppAgentManagementDetailsCatalog _detailsCatalog;

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
      await _providerSettings.loadSettings();
      // loadSettings 复用首轮 Future；当前设置可能早已被用户修改。
      final settings = _providerSettings.settings;
      final agents = <String, AgentDetectionConfirmedRecord>{};
      for (final entry in _repositories.entries) {
        final cached = _restoreCachedAgent(
          agentId: entry.key,
          config: _config.configFor(settings, entry.value),
          repository: entry.value,
        );
        if (cached.installed) {
          agents[entry.key] = AgentDetectionConfirmedRecord(
            details: managementDetectionDetails(cached),
            confirmedAt: cached.lastDetectedAt,
            freshness: DetectionFreshness.restoredCache,
          );
        }
      }
      _sink.initializationSucceeded(effect.operationId, settings, agents);
    } catch (error, stackTrace) {
      _sink.initializationFailed(effect.operationId, error, stackTrace);
    }
  }

  Future<void> _detect(DetectAgentsEffect effect) => _detectionPort.detect(
    operationId: effect.operationId,
    providerIds: effect.providerIds,
    catalogGeneration: effect.catalogGeneration,
    cancellation: effect.cancellation,
    emit: (event) => _sink.acceptDetectionResult(
      effect.operationId,
      effect.ownerGeneration,
      effect.catalogGeneration,
      event,
    ),
  );

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
    final key = _config
        .descriptor(repository)
        ?.managementCapabilities
        .accountDataEnrichmentExtraKey;
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
      final current = _config.configFor(_providerSettings.settings, repository);
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
        providerConfig: _config.configFor(
          _providerSettings.settings,
          repository,
        ),
      );
      if (_sink.isClosed) return;
      final handle = _detailsCatalog.stage(
        diagnostic: result.$1.rawErrorSummary,
      );
      final summary = managementConnectionSummary(result.$1, handle: handle);
      try {
        _sink.connectionTestSucceeded(
          operationId: effect.operationId,
          agentId: effect.agentId,
          result: summary,
          models: result.$2,
          modelSource:
              _config.descriptor(repository)?.connectionModelSourceLabel ??
              repository.agentId,
          modelsUpdatedAt: _now(),
        );
        if (identical(
              _sink
                  .current
                  .confirmedConnectionChecksByProviderId[effect.agentId]
                  ?.result,
              summary,
            ) &&
            !_sink.isClosed) {
          _detailsCatalog.confirm(
            effect.agentId,
            AgentManagementDetailsKind.explicitConnectionCheck,
            handle,
          );
        } else {
          _detailsCatalog.discard(handle);
        }
      } catch (_) {
        _detailsCatalog.discard(handle);
        rethrow;
      }
    } catch (error) {
      _sink.connectionTestFailed(
        effect.operationId,
        effect.agentId,
        _textCatalog.connectionTestFailed(''),
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
      _sink.logsLoaded(effect.operationId, effect.agentId, paths.length, logs);
    } catch (error) {
      _sink.logsLoadFailed(
        effect.operationId,
        effect.agentId,
        _textCatalog.logsReadFailed(error),
      );
    }
  }

  ManagedAgent _restoreCachedAgent({
    required String agentId,
    required AgentProviderConfig config,
    required AgentCliManagementRepository repository,
  }) {
    final sanitized = _config.sanitize(config, repository);
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
        rawPath != null && _config.acceptsExecutablePath(repository, rawPath)
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

  AgentCliManagementRepository _repository(String agentId) {
    final repository = _repositories[agentId];
    if (repository == null) {
      throw UnsupportedError(
        'Agent $agentId does not provide CLI management capabilities',
      );
    }
    return repository;
  }
}
