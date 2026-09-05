import 'package:meta/meta.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 当前会话的无正文运行观测；与 ThreadSnapshot 共用安全发布边界。
@immutable
final class AgentConversationRuntimeObservation {
  const AgentConversationRuntimeObservation({
    required this.bindingKey,
    this.runtimeIdentity,
    this.connectionScope,
    required this.attemptEpoch,
    required this.lifecycle,
    required this.connectionState,
    this.isTurnRunning = false,
    this.waitingOnApproval = false,
    this.waitingOnUserInput = false,
  });

  final AgentConversationBindingKey bindingKey;
  final AgentProviderRuntimeIdentity? runtimeIdentity;
  final AgentRuntimeScope? connectionScope;
  final int attemptEpoch;
  final AgentConversationRuntimeLifecyclePhase lifecycle;
  final AgentProviderConnectionState connectionState;
  final bool isTurnRunning;
  final bool waitingOnApproval;
  final bool waitingOnUserInput;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentConversationRuntimeObservation &&
          other.bindingKey == bindingKey &&
          other.runtimeIdentity == runtimeIdentity &&
          other.connectionScope == connectionScope &&
          other.attemptEpoch == attemptEpoch &&
          other.lifecycle == lifecycle &&
          other.connectionState == connectionState &&
          other.isTurnRunning == isTurnRunning &&
          other.waitingOnApproval == waitingOnApproval &&
          other.waitingOnUserInput == waitingOnUserInput;

  @override
  int get hashCode => Object.hash(
    bindingKey,
    runtimeIdentity,
    connectionScope,
    attemptEpoch,
    lifecycle,
    connectionState,
    isTurnRunning,
    waitingOnApproval,
    waitingOnUserInput,
  );
}
