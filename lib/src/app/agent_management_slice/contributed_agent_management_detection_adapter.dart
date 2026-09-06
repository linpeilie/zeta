import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_detection_port.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_state.dart';
import 'agent_management_detection_projection.dart';
import 'agent_management_details_catalog.dart';

/// 已激活、归属校验后的贡献目录到安全探测事件的唯一适配器。
final class ContributedAgentManagementDetectionAdapter
    implements AgentManagementDetectionPort {
  ContributedAgentManagementDetectionAdapter({
    required Map<String, AgentCliManagementRepository> repositories,
    required Map<String, AgentDefinition> definitions,
    required this.settings,
    required this.details,
    required this.textCatalog,
    required this.configFor,
    this.generation = 0,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       repositories = Map.unmodifiable(repositories),
       definitions = Map.unmodifiable(definitions);
  final Map<String, AgentCliManagementRepository> repositories;
  final Map<String, AgentDefinition> definitions;
  final AgentProviderSettingsPort settings;
  final AppAgentManagementDetailsCatalog details;
  final AgentManagementTextCatalog textCatalog;
  final AgentProviderConfig Function(
    AgentProviderSettings,
    AgentCliManagementRepository,
  )
  configFor;
  final int generation;
  final DateTime Function() _now;

  @override
  Future<void> detect({
    required OperationId operationId,
    required List<String> providerIds,
    required int catalogGeneration,
    required AgentManagementCancellation cancellation,
    required bool Function(AgentManagementDetectionEvent) emit,
  }) async {
    void check() {
      cancellation.throwIfCanceled();
      if (catalogGeneration != generation) {
        throw const AgentManagementDetectionCanceled();
      }
    }

    void publish(AgentManagementDetectionEvent event) {
      check();
      if (!emit(event)) throw const AgentManagementDetectionCanceled();
    }

    check();
    for (final id in providerIds) {
      final repository = repositories[id];
      if (repository == null ||
          repository.agentId != id ||
          definitions[id]?.id != id) {
        throw StateError('Management contribution unavailable');
      }
    }
    for (final id in providerIds) {
      check();
      final repository = repositories[id]!;
      publish(DetectionProviderStarted(id));
      ManagedAgent detected;
      try {
        final config = configFor(settings.settings, repository);
        detected = await repository.detect(
          providerConfig: config,
          enabled: config.enabled,
          onProgress: (progress, partial) {
            // 无取消端口的 repository 可能继续回调；迟到进度直接丢弃。
            if (cancellation.isCanceled) return;
            if (partial.definition.id != id) return;
            emit(
              DetectionProviderProgress(
                id,
                AgentDetectionProgress(
                  completed: progress.completed,
                  total: progress.total,
                  message: textCatalog.detectionProgress(
                    index: '${providerIds.indexOf(id) + 1}',
                    total: '${providerIds.length}',
                    name: definitions[id]!.displayName,
                    message: safeManagementText(progress.message) ?? '',
                  ),
                ),
                managementDetectionPartial(partial),
              ),
            );
          },
        );
        check();
        if (detected.definition.id != id ||
            !identical(detected.definition, definitions[id])) {
          throw StateError('Management definition changed');
        }
      } on AgentManagementDetectionCanceled {
        rethrow;
      } catch (_) {
        publish(
          DetectionProviderFailed(
            id,
            AgentManagementFailure(
              kind: AgentManagementFailureKind.detection,
              operationId: operationId,
              agentId: id,
            ),
          ),
        );
        continue;
      }
      final handle = details.stage(
        executable: detected.executablePath,
        diagnostic:
            detected.errorDetails ?? detected.connectionTest?.rawErrorSummary,
      );
      var accepted = false;
      try {
        check();
        accepted = emit(
          DetectionProviderSucceeded(
            id,
            managementDetectionDetails(detected, handle: handle),
            confirmedAt: _now(),
          ),
        );
        if (!accepted) throw const AgentManagementDetectionCanceled();
        details.confirm(id, AgentManagementDetailsKind.detection, handle);
      } finally {
        if (!accepted) details.discard(handle);
      }
      check();
      try {
        // 仅合并检测白名单；不得把开始检测时的 enabled/arguments/extra 写回。
        final latest =
            settings.settings.providers.where((p) => p.id == id).firstOrNull ??
            configFor(settings.settings, repository);
        final path = detected.executablePath;
        final descriptor = repository is AgentCliManagementDescriptor
            ? repository as AgentCliManagementDescriptor
            : null;
        final acceptedPath =
            path != null && (descriptor?.acceptsExecutablePath(path) ?? true);
        final updated = latest.copyWith(
          extra: {
            for (final e in latest.extra.entries)
              if (e.key != 'cliPath' ||
                  detected.installationState !=
                      AgentInstallationState.notInstalled)
                e.key: e.value,
            'detectedCurrentVersion': detected.currentVersion,
            'detectedLatestVersion': detected.latestVersion,
            'detectedAccountState': detected.accountState.name,
            'lastDetectedAt': detected.lastDetectedAt?.toIso8601String(),
            if (detected.connectionTest?.protocolVersion != null)
              'detectedProtocolVersion':
                  detected.connectionTest!.protocolVersion,
            if (acceptedPath) 'cliPath': path,
          },
        );
        check();
        await settings.updateProviderConfig(updated, restartProvider: false);
        check();
      } on AgentManagementDetectionCanceled {
        rethrow;
      } catch (_) {
        publish(DetectionCacheWriteWarning(id));
      }
    }
  }
}
