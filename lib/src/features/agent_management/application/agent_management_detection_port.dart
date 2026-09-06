import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'agent_management_agent_view.dart';
import 'agent_management_slice/agent_management_slice_state.dart';

/// 逻辑取消不声称可以中止底层 CLI；owner 仍等待真实 I/O 排空。
abstract interface class AgentManagementCancellation {
  bool get isCanceled;
  void throwIfCanceled();
}

final class AgentManagementDetectionCanceled implements Exception {
  const AgentManagementDetectionCanceled();
}

/// app 将已验证贡献的仓储结果投影到安全事件。
abstract interface class AgentManagementDetectionPort {
  Future<void> detect({
    required OperationId operationId,
    required List<String> providerIds,
    required int catalogGeneration,
    required AgentManagementCancellation cancellation,
    required bool Function(AgentManagementDetectionEvent) emit,
  });
}

final agentManagementDefaultDetectionPortProvider =
    Provider<AgentManagementDetectionPort>(
      (ref) => throw StateError('Management detection port was not installed'),
    );

sealed class AgentManagementDetectionEvent {
  const AgentManagementDetectionEvent(this.providerId);
  final String providerId;
}

final class DetectionProviderStarted extends AgentManagementDetectionEvent {
  const DetectionProviderStarted(super.providerId);
}

final class DetectionProviderProgress extends AgentManagementDetectionEvent {
  const DetectionProviderProgress(
    super.providerId,
    this.progress,
    this.partial,
  );
  final AgentDetectionProgress progress;
  final AgentDetectionPartial partial;
}

final class DetectionProviderSucceeded extends AgentManagementDetectionEvent {
  const DetectionProviderSucceeded(
    super.providerId,
    this.details, {
    this.confirmedAt,
  });
  final DateTime? confirmedAt;
  final AgentDetectionDetails details;
}

final class DetectionProviderFailed extends AgentManagementDetectionEvent {
  const DetectionProviderFailed(super.providerId, this.failure);
  final AgentManagementFailure failure;
}

final class DetectionCacheWriteWarning extends AgentManagementDetectionEvent {
  const DetectionCacheWriteWarning(super.providerId);
}

/// 测试和宿主可替换的统一入口；默认实现由 app 装配。
final agentManagementDetectionPortProvider =
    Provider<AgentManagementDetectionPort>(
      (ref) => ref.read(agentManagementDefaultDetectionPortProvider),
    );
