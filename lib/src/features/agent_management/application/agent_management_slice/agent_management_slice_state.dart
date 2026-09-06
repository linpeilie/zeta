import '../agent_management_agent_view.dart';
import '../agent_management_detection_state.dart';
import '../agent_management_runtime_facts.dart';
import 'package:meta/meta.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';

/// Agent 管理异步操作的稳定分类。
enum AgentManagementOperationKind {
  initialize,
  detection,
  providerEnabledUpdate,
  accountDataEnrichmentUpdate,
  connectionTest,
  configurationLoad,
  configurationSave,
  logsLoad,
}

/// pending operation 的 typed key；全局操作的 [agentId] 为 null。
@immutable
final class AgentManagementOperationKey {
  const AgentManagementOperationKey(this.kind, [this.agentId]);

  final AgentManagementOperationKind kind;
  final String? agentId;

  @override
  bool operator ==(Object other) =>
      other is AgentManagementOperationKey &&
      other.kind == kind &&
      other.agentId == agentId;

  @override
  int get hashCode => Object.hash(kind, agentId);
}

/// 可公开给 UI 的稳定失败分类。
enum AgentManagementFailureKind {
  initialization,
  detection,
  providerEnabledUpdate,
  accountDataEnrichmentUpdate,
  connectionTest,
  configurationRead,
  configurationSave,
  logsRead,
}

/// 管理页失败快照不保存原始异常，只保留分类与文本目录投影。
@immutable
final class AgentManagementFailure {
  const AgentManagementFailure({
    required this.kind,
    required this.operationId,
    this.agentId,
    this.message,
  });

  final AgentManagementFailureKind kind;
  final OperationId operationId;
  final String? agentId;
  final String? message;
}

const Object _agentManagementSliceUnset = Object();

/// Agent 管理页面的不可变 application state。
///
/// Provider settings 与 runtime 仅以 typed ingress 快照进入；它们的 owner 仍是
/// Provider settings store 与 runtime registry。配置编辑草稿不进入本对象。
@immutable
final class AgentManagementSliceState {
  AgentManagementSliceState({
    required Map<String, AgentManagementDisplayDefinition>
    definitionsByProviderId,
    AgentManagementDetectionState? detection,
    Map<String, AgentManagementConnectionCheckState>
        confirmedConnectionChecksByProviderId =
        const {},
    Map<String, int> logFileCountsByProviderId = const {},
    this.catalogGeneration = 0,
    required List<String> orderedAgentIds,
    required this.selectedAgentId,
    required Map<String, AgentCliManagementCapabilities> capabilitiesByAgentId,
    this.providerSettings = const AgentProviderSettings(),
    Map<String, AgentConfigurationDocument>? confirmedConfigurationsByAgentId,
    Map<String, List<AgentLogEntry>>? logsByAgentId,
    Map<AgentManagementOperationKey, OperationId>? pendingOperations,
    AgentManagementRuntimeFacts? runtimeFacts,
    Map<String, AgentManagementProviderRuntimeSummary>? runtimeByProviderId,
    this.detectionProgress,
    this.detectingAgentId,
    this.initialized = false,
    this.failure,
  }) : runtimeFacts = runtimeFacts ?? AgentManagementRuntimeFacts.empty,
       runtimeByProviderId = Map.unmodifiable(
         runtimeByProviderId ??
             const <String, AgentManagementProviderRuntimeSummary>{},
       ),
       definitionsByProviderId = Map.unmodifiable(definitionsByProviderId),
       detection = detection ?? AgentManagementDetectionState(),
       confirmedConnectionChecksByProviderId = Map.unmodifiable(
         confirmedConnectionChecksByProviderId,
       ),
       logFileCountsByProviderId = Map.unmodifiable(logFileCountsByProviderId),
       orderedAgentIds = List<String>.unmodifiable(orderedAgentIds),
       capabilitiesByAgentId =
           Map<String, AgentCliManagementCapabilities>.unmodifiable(
             capabilitiesByAgentId,
           ),
       confirmedConfigurationsByAgentId =
           Map<String, AgentConfigurationDocument>.unmodifiable(
             confirmedConfigurationsByAgentId ??
                 const <String, AgentConfigurationDocument>{},
           ),
       logsByAgentId = _freezeLogs(logsByAgentId),
       pendingOperations =
           Map<AgentManagementOperationKey, OperationId>.unmodifiable(
             pendingOperations ??
                 const <AgentManagementOperationKey, OperationId>{},
           );

  factory AgentManagementSliceState.initial({
    required Map<String, AgentManagementDisplayDefinition>
    definitionsByProviderId,
    required List<String> orderedAgentIds,
    required Map<String, AgentCliManagementCapabilities> capabilitiesByAgentId,
    required AgentProviderSettings providerSettings,
  }) {
    return AgentManagementSliceState(
      definitionsByProviderId: definitionsByProviderId,
      orderedAgentIds: orderedAgentIds,
      selectedAgentId: orderedAgentIds.isEmpty
          ? providerSettings.activeProviderId
          : orderedAgentIds.first,
      capabilitiesByAgentId: capabilitiesByAgentId,
      providerSettings: providerSettings,
    );
  }

  final AgentManagementRuntimeFacts runtimeFacts;
  final Map<String, AgentManagementProviderRuntimeSummary> runtimeByProviderId;
  final Map<String, AgentManagementDisplayDefinition> definitionsByProviderId;
  final int catalogGeneration;
  final AgentManagementDetectionState detection;
  final Map<String, AgentManagementConnectionCheckState>
  confirmedConnectionChecksByProviderId;
  final Map<String, int> logFileCountsByProviderId;
  Map<String, AgentManagementAgentView> get agentsById => Map.unmodifiable({
    for (final entry in definitionsByProviderId.entries)
      entry.key: composeManagedAgent(this, entry.key),
  });
  final List<String> orderedAgentIds;
  final String selectedAgentId;
  final Map<String, AgentCliManagementCapabilities> capabilitiesByAgentId;
  final AgentProviderSettings providerSettings;
  final Map<String, AgentConfigurationDocument>
  confirmedConfigurationsByAgentId;
  final Map<String, List<AgentLogEntry>> logsByAgentId;
  final Map<AgentManagementOperationKey, OperationId> pendingOperations;
  final AgentDetectionProgress? detectionProgress;
  final String? detectingAgentId;
  final bool initialized;
  final AgentManagementFailure? failure;

  AgentManagementSliceState copyWith({
    AgentManagementRuntimeFacts? runtimeFacts,
    Map<String, AgentManagementProviderRuntimeSummary>? runtimeByProviderId,
    Map<String, AgentManagementDisplayDefinition>? definitionsByProviderId,
    int? catalogGeneration,
    AgentManagementDetectionState? detection,
    Map<String, AgentManagementConnectionCheckState>?
    confirmedConnectionChecksByProviderId,
    Map<String, int>? logFileCountsByProviderId,
    List<String>? orderedAgentIds,
    String? selectedAgentId,
    Map<String, AgentCliManagementCapabilities>? capabilitiesByAgentId,
    AgentProviderSettings? providerSettings,
    Map<String, AgentConfigurationDocument>? confirmedConfigurationsByAgentId,
    Map<String, List<AgentLogEntry>>? logsByAgentId,
    Map<AgentManagementOperationKey, OperationId>? pendingOperations,
    Object? detectionProgress = _agentManagementSliceUnset,
    Object? detectingAgentId = _agentManagementSliceUnset,
    bool? initialized,
    Object? failure = _agentManagementSliceUnset,
  }) {
    return AgentManagementSliceState(
      runtimeFacts: runtimeFacts ?? this.runtimeFacts,
      runtimeByProviderId: runtimeByProviderId ?? this.runtimeByProviderId,
      definitionsByProviderId:
          definitionsByProviderId ?? this.definitionsByProviderId,
      catalogGeneration: catalogGeneration ?? this.catalogGeneration,
      detection: detection ?? this.detection,
      confirmedConnectionChecksByProviderId:
          confirmedConnectionChecksByProviderId ??
          this.confirmedConnectionChecksByProviderId,
      logFileCountsByProviderId:
          logFileCountsByProviderId ?? this.logFileCountsByProviderId,
      orderedAgentIds: orderedAgentIds ?? this.orderedAgentIds,
      selectedAgentId: selectedAgentId ?? this.selectedAgentId,
      capabilitiesByAgentId:
          capabilitiesByAgentId ?? this.capabilitiesByAgentId,
      providerSettings: providerSettings ?? this.providerSettings,
      confirmedConfigurationsByAgentId:
          confirmedConfigurationsByAgentId ??
          this.confirmedConfigurationsByAgentId,
      logsByAgentId: logsByAgentId ?? this.logsByAgentId,
      pendingOperations: pendingOperations ?? this.pendingOperations,
      detectionProgress:
          identical(detectionProgress, _agentManagementSliceUnset)
          ? this.detectionProgress
          : detectionProgress as AgentDetectionProgress?,
      detectingAgentId: identical(detectingAgentId, _agentManagementSliceUnset)
          ? this.detectingAgentId
          : detectingAgentId as String?,
      initialized: initialized ?? this.initialized,
      failure: identical(failure, _agentManagementSliceUnset)
          ? this.failure
          : failure as AgentManagementFailure?,
    );
  }
}

/// UI 与兼容 port 共用的纯 selector。
abstract final class AgentManagementSliceSelectors {
  static List<AgentManagementAgentView> agents(
    AgentManagementSliceState state,
  ) {
    return List<AgentManagementAgentView>.unmodifiable(
      <AgentManagementAgentView>[
        for (final id in state.orderedAgentIds)
          if (state.agentsById[id] case final AgentManagementAgentView agent)
            agent,
      ],
    );
  }

  static AgentManagementAgentView selectedAgent(
    AgentManagementSliceState state,
  ) {
    final selected = state.agentsById[state.selectedAgentId];
    if (selected != null) {
      return selected;
    }
    for (final id in state.orderedAgentIds) {
      final agent = state.agentsById[id];
      if (agent != null) {
        return agent;
      }
    }
    throw StateError('No managed Agent is available');
  }

  static AgentConfigurationDocument? selectedConfiguration(
    AgentManagementSliceState state,
  ) => state.confirmedConfigurationsByAgentId[state.selectedAgentId];

  static List<AgentLogEntry> selectedLogs(AgentManagementSliceState state) =>
      state.logsByAgentId[state.selectedAgentId] ?? const <AgentLogEntry>[];

  static bool isPending(
    AgentManagementSliceState state,
    AgentManagementOperationKind kind, {
    String? agentId,
  }) => state.pendingOperations.containsKey(
    AgentManagementOperationKey(kind, agentId),
  );

  static bool supportsAccountDataEnrichment(AgentManagementSliceState state) =>
      state
          .capabilitiesByAgentId[state.selectedAgentId]
          ?.supportsAccountDataEnrichment ??
      false;

  static AgentProviderConfig? selectedProviderConfig(
    AgentManagementSliceState state,
  ) => _providerConfig(state, state.selectedAgentId);

  static List<AgentProviderConfig> availableThreadProviders(
    AgentManagementSliceState state,
  ) {
    return List<AgentProviderConfig>.unmodifiable(
      state.providerSettings.providers.where(
        (provider) =>
            provider.enabled && state.agentsById.containsKey(provider.id),
      ),
    );
  }

  static String? visibleOperationError(AgentManagementSliceState state) {
    final failure = state.failure;
    if (failure == null ||
        (failure.agentId != null && failure.agentId != state.selectedAgentId)) {
      return null;
    }
    return failure.message;
  }
}

AgentProviderConfig? _providerConfig(
  AgentManagementSliceState state,
  String providerId,
) {
  for (final provider in state.providerSettings.providers) {
    if (provider.id == providerId) {
      return provider;
    }
  }
  return null;
}

Map<String, List<AgentLogEntry>> _freezeLogs(
  Map<String, List<AgentLogEntry>>? source,
) {
  if (source == null) {
    return const <String, List<AgentLogEntry>>{};
  }
  return Map<String, List<AgentLogEntry>>.unmodifiable(
    <String, List<AgentLogEntry>>{
      for (final entry in source.entries)
        entry.key: List<AgentLogEntry>.unmodifiable(entry.value),
    },
  );
}

/// 所有展示字段从各自真源合成，不写回第二份 Agent 缓存。
AgentManagementAgentView composeManagedAgent(
  AgentManagementSliceState state,
  String id,
) {
  final details =
      state.detection.confirmedByProviderId[id]?.details ??
      AgentDetectionDetails();
  final enabled = _providerConfig(state, id)?.enabled ?? true;
  final document = state.confirmedConfigurationsByAgentId[id];
  return AgentManagementAgentView(
    definition: state.definitionsByProviderId[id]!,
    details: details,
    enabled: enabled,
    runtimeState:
        state.runtimeByProviderId[id]?.state ??
        (enabled ? AgentRuntimeState.notRunning : AgentRuntimeState.disabled),
    connectionCheck: state.confirmedConnectionChecksByProviderId[id],
    confirmedConfigExists: document?.exists,
    confirmedConfigModifiedAt: document?.modifiedAt,
    logFileCount: state.logFileCountsByProviderId[id],
  );
}
