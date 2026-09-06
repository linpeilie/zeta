import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'agent_management_agent_view.dart';
import 'agent_management_slice/agent_management_slice_state.dart';

/// 工作台探测阶段；失败不会把已确认安装事实改成未安装。
enum ManagementDetectionPhase {
  neverRequested,
  initializing,
  running,
  succeeded,
  partialFailure,
  failed,
  canceled,
}

enum ProviderDetectionOutcome { pending, succeeded, failed, canceled }

enum DetectionFreshness {
  noConfirmedData,
  restoredCache,
  confirmedThisRun,
  stale,
}

enum DetectionRunStatus { succeeded, partialFailure, failed, canceled, closed }

/// 所有调用者共用的非异常终态，不保存原始错误。
final class AgentManagementDetectionRunResult {
  const AgentManagementDetectionRunResult._(this.status, [this.failure]);
  const AgentManagementDetectionRunResult.failed(AgentManagementFailure failure)
    : this._(DetectionRunStatus.failed, failure);
  static const succeeded = AgentManagementDetectionRunResult._(
    DetectionRunStatus.succeeded,
  );
  static const partialFailure = AgentManagementDetectionRunResult._(
    DetectionRunStatus.partialFailure,
  );
  static const canceled = AgentManagementDetectionRunResult._(
    DetectionRunStatus.canceled,
  );
  static const closed = AgentManagementDetectionRunResult._(
    DetectionRunStatus.closed,
  );
  final DetectionRunStatus status;
  final AgentManagementFailure? failure;
}

final class AgentDetectionConfirmedRecord {
  const AgentDetectionConfirmedRecord({
    required this.details,
    this.confirmedAt,
    required this.freshness,
  });
  final AgentDetectionDetails details;
  final DateTime? confirmedAt;
  final DetectionFreshness freshness;
  AgentDetectionConfirmedRecord stale() => AgentDetectionConfirmedRecord(
    details: details,
    confirmedAt: confirmedAt,
    freshness: DetectionFreshness.stale,
  );
}

/// 唯一探测账本；partial 与 confirmed 严格分离。
final class AgentManagementDetectionState {
  AgentManagementDetectionState({
    this.phase = ManagementDetectionPhase.neverRequested,
    this.operationId,
    Map<String, AgentDetectionConfirmedRecord> confirmedByProviderId = const {},
    Map<String, AgentDetectionPartial> pendingPartialByProviderId = const {},
    Map<String, AgentDetectionProgress> progressByProviderId = const {},
    Map<String, ProviderDetectionOutcome> outcomesByProviderId = const {},
    Map<String, AgentManagementFailure> failuresByProviderId = const {},
    Set<String> cacheWriteWarningProviderIds = const {},
    this.automaticAttemptConsumed = false,
    this.lastResult,
  }) : confirmedByProviderId = Map.unmodifiable(confirmedByProviderId),
       pendingPartialByProviderId = Map.unmodifiable(
         pendingPartialByProviderId,
       ),
       progressByProviderId = Map.unmodifiable(progressByProviderId),
       outcomesByProviderId = Map.unmodifiable(outcomesByProviderId),
       failuresByProviderId = Map.unmodifiable(failuresByProviderId),
       cacheWriteWarningProviderIds = Set.unmodifiable(
         cacheWriteWarningProviderIds,
       );
  final ManagementDetectionPhase phase;
  final OperationId? operationId;
  final Map<String, AgentDetectionConfirmedRecord> confirmedByProviderId;
  final Map<String, AgentDetectionPartial> pendingPartialByProviderId;
  final Map<String, AgentDetectionProgress> progressByProviderId;
  final Map<String, ProviderDetectionOutcome> outcomesByProviderId;
  final Map<String, AgentManagementFailure> failuresByProviderId;
  final Set<String> cacheWriteWarningProviderIds;
  final bool automaticAttemptConsumed;
  final AgentManagementDetectionRunResult? lastResult;
  bool get isLoading =>
      phase == ManagementDetectionPhase.initializing ||
      phase == ManagementDetectionPhase.running;
  AgentManagementDetectionState copyWith({
    ManagementDetectionPhase? phase,
    OperationId? operationId,
    Map<String, AgentDetectionConfirmedRecord>? confirmedByProviderId,
    Map<String, AgentDetectionPartial>? pendingPartialByProviderId,
    Map<String, AgentDetectionProgress>? progressByProviderId,
    Map<String, ProviderDetectionOutcome>? outcomesByProviderId,
    Map<String, AgentManagementFailure>? failuresByProviderId,
    Set<String>? cacheWriteWarningProviderIds,
    bool? automaticAttemptConsumed,
    AgentManagementDetectionRunResult? lastResult,
  }) => AgentManagementDetectionState(
    phase: phase ?? this.phase,
    operationId: operationId ?? this.operationId,
    confirmedByProviderId: confirmedByProviderId ?? this.confirmedByProviderId,
    pendingPartialByProviderId:
        pendingPartialByProviderId ?? this.pendingPartialByProviderId,
    progressByProviderId: progressByProviderId ?? this.progressByProviderId,
    outcomesByProviderId: outcomesByProviderId ?? this.outcomesByProviderId,
    failuresByProviderId: failuresByProviderId ?? this.failuresByProviderId,
    cacheWriteWarningProviderIds:
        cacheWriteWarningProviderIds ?? this.cacheWriteWarningProviderIds,
    automaticAttemptConsumed:
        automaticAttemptConsumed ?? this.automaticAttemptConsumed,
    lastResult: lastResult ?? this.lastResult,
  );
}
