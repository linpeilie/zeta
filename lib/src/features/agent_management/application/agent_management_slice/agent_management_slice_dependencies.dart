import '../agent_management_detection_port.dart';
import '../agent_management_agent_view.dart';
import '../agent_management_detection_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import '../agent_management_runtime_facts.dart';
import 'agent_management_slice_effect.dart';
import 'agent_management_slice_state.dart';

abstract interface class AgentManagementResultSink {
  bool get isClosed;
  AgentManagementSliceState get current; // Runner 原 state.agentsById 的只读查询

  void providerSettingsChanged(AgentProviderSettings settings);
  void runtimeFactsReplaced(AgentManagementRuntimeFacts facts); // WP-1 契约

  void initializationSucceeded(
    OperationId id,
    AgentProviderSettings settings,
    Map<String, AgentDetectionConfirmedRecord> confirmedByProviderId,
  );
  void initializationFailed(
    OperationId id,
    Object error,
    StackTrace stackTrace,
  );

  bool acceptDetectionResult(
    OperationId id,
    int ownerGeneration,
    int catalogGeneration,
    AgentManagementDetectionEvent event,
  );

  void providerEnabledUpdated(
    OperationId id,
    String agentId,
    bool enabled,
    AgentProviderSettings settings,
  );
  void providerEnabledUpdateFailed(
    OperationId id,
    String agentId,
    String message,
  );
  void accountDataEnrichmentUpdated(
    OperationId id,
    String agentId,
    AgentProviderSettings settings,
  );
  void accountDataEnrichmentUpdateFailed(
    OperationId id,
    String agentId,
    String message,
  );

  void connectionTestSucceeded({
    required OperationId operationId,
    required String agentId,
    required AgentManagementConnectionCheckSummary result,
    required List<AgentModelInfo> models,
    required String modelSource,
    required DateTime modelsUpdatedAt,
  });
  void connectionTestFailed(OperationId id, String agentId, String message);
  void configurationLoaded(
    OperationId id,
    String agentId,
    AgentConfigurationDocument document,
  );
  void configurationLoadFailed(OperationId id, String agentId, String message);
  void configurationSaved(
    OperationId id,
    String agentId,
    String originalSignature,
    AgentConfigurationSaveResult result,
  );
  void configurationSaveFailed(
    OperationId id,
    String agentId,
    Object error,
    StackTrace stackTrace,
  );
  void logsLoaded(
    OperationId id,
    String agentId,
    int fileCount,
    List<AgentLogEntry> entries,
  );
  void logsLoadFailed(OperationId id, String agentId, String message);
}

typedef AgentManagementRunnerFactory =
    AgentManagementSliceEffectRunner Function(AgentManagementResultSink sink);

// 同在 application dependencies 文件声明；由 app 组合用于关停，不暴露给 UI。
abstract interface class AgentManagementOwnerLifecycle {
  void stopAcceptingCommandsAndSettleWaiters();
  Future<void> drainExecutions();
}

abstract interface class AgentManagementSliceEffectRunner {
  Future<void> run(AgentManagementSliceEffect effect);
  String? validateConfiguration(String agentId, String content);
}

/// Frozen inputs for one application session; settings/facts arrive through ingress.
final class AgentManagementSliceDependencies {
  const AgentManagementSliceDependencies({
    required this.initialState,
    required this.configurationNotLoadedMessage,
    required this.accountDataEnrichmentEnabledFor,
    this.operationIdGeneratorFactory,
  });
  final AgentManagementSliceState initialState;
  final String configurationNotLoadedMessage;
  final bool Function(AgentProviderConfig) accountDataEnrichmentEnabledFor;
  final OperationIdGenerator Function(String)? operationIdGeneratorFactory;
}

final agentManagementSliceDependenciesProvider =
    Provider<AgentManagementSliceDependencies>(
      (ref) => throw StateError('Management dependencies were not installed'),
    );
final agentManagementRunnerFactoryProvider =
    Provider<AgentManagementRunnerFactory>(
      (ref) => throw StateError('Management runner factory was not installed'),
    );
