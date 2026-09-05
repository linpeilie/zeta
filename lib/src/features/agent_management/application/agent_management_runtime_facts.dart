import 'package:meta/meta.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';

/// Shell 校验过身份与生命周期的会话事实；opaque key 仅用于内存去重。
@immutable
final class AgentManagementRuntimeFact {
  const AgentManagementRuntimeFact({
    required this.observationKey,
    required this.providerId,
    this.runtimeIdentity,
    this.connectionScope,
    required this.lifecycle,
    this.connectionState,
    this.hasCurrentThreadObservation = false,
    this.connected = false,
    this.activeTurn = false,
    this.waitingOnApproval = false,
    this.waitingOnUserInput = false,
    this.currentError = false,
    this.unavailable = false,
  });

  final Object observationKey;
  final String providerId;
  final AgentProviderRuntimeIdentity? runtimeIdentity;
  final AgentRuntimeScope? connectionScope;
  final AgentConversationRuntimeLifecyclePhase lifecycle;
  final AgentProviderConnectionState? connectionState;
  final bool hasCurrentThreadObservation;
  final bool connected;
  final bool activeTurn;
  final bool waitingOnApproval;
  final bool waitingOnUserInput;
  final bool currentError;
  final bool unavailable;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentManagementRuntimeFact &&
          identical(other.observationKey, observationKey) &&
          other.providerId == providerId &&
          other.runtimeIdentity == runtimeIdentity &&
          other.connectionScope == connectionScope &&
          other.lifecycle == lifecycle &&
          other.connectionState == connectionState &&
          other.hasCurrentThreadObservation == hasCurrentThreadObservation &&
          other.connected == connected &&
          other.activeTurn == activeTurn &&
          other.waitingOnApproval == waitingOnApproval &&
          other.waitingOnUserInput == waitingOnUserInput &&
          other.currentError == currentError &&
          other.unavailable == unavailable;

  @override
  int get hashCode => Object.hash(
    identityHashCode(observationKey),
    providerId,
    runtimeIdentity,
    connectionScope,
    lifecycle,
    connectionState,
    hasCurrentThreadObservation,
    connected,
    activeTurn,
    waitingOnApproval,
    waitingOnUserInput,
    currentError,
    unavailable,
  );
}

/// 一次全量替换的只读事实，不保存会话正文、路径或原始错误。
@immutable
final class AgentManagementRuntimeFacts {
  AgentManagementRuntimeFacts(Iterable<AgentManagementRuntimeFact> bindings)
    : bindings = List.unmodifiable(bindings);

  static final empty = AgentManagementRuntimeFacts(const []);
  final List<AgentManagementRuntimeFact> bindings;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentManagementRuntimeFacts &&
          zetaListEquals(bindings, other.bindings);
  @override
  int get hashCode => Object.hashAll(bindings);
}

/// 借用只读端口。subscribe 仅注册，消费者随后同步读取 current；owner 独占关闭。
abstract interface class AgentManagementRuntimeFactSource {
  AgentManagementRuntimeFacts get current;
  void Function() subscribe(void Function(AgentManagementRuntimeFacts) receive);
}

/// 按精确配置实例 id 聚合的 Workbench session 摘要。
@immutable
final class AgentManagementProviderRuntimeSummary {
  const AgentManagementProviderRuntimeSummary({
    required this.providerId,
    required this.enabled,
    required this.activeTurnCount,
    required this.connectedRuntimeCount,
    required this.startingBindingCount,
    required this.errorBindingCount,
    required this.unavailableBindingCount,
    required this.unobservedTurnRuntimeCount,
    required this.state,
  });

  final String providerId;
  final bool enabled;
  final int activeTurnCount;
  final int connectedRuntimeCount;
  final int startingBindingCount;
  final int errorBindingCount;
  final int unavailableBindingCount;
  final int unobservedTurnRuntimeCount;
  final AgentRuntimeState state;

  bool get hasErrors => errorBindingCount > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentManagementProviderRuntimeSummary &&
          other.providerId == providerId &&
          other.enabled == enabled &&
          other.activeTurnCount == activeTurnCount &&
          other.connectedRuntimeCount == connectedRuntimeCount &&
          other.startingBindingCount == startingBindingCount &&
          other.errorBindingCount == errorBindingCount &&
          other.unavailableBindingCount == unavailableBindingCount &&
          other.unobservedTurnRuntimeCount == unobservedTurnRuntimeCount &&
          other.state == state;

  @override
  int get hashCode => Object.hash(
    providerId,
    enabled,
    activeTurnCount,
    connectedRuntimeCount,
    startingBindingCount,
    errorBindingCount,
    unavailableBindingCount,
    unobservedTurnRuntimeCount,
    state,
  );
}
