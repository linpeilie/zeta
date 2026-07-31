import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 会话 reducer 的使用场景。
///
/// 每个场景必须持有独立 reducer/context，避免错误去重、弃用提示和本地 identity
/// 状态在 live、history 与 replay 之间串扰。
enum AgentConversationReductionScope { live, history, replay }

/// effect 相对同步 mutation 的执行顺序。
enum AgentConversationEffectTiming { beforeMutation, afterMutation }

/// application effect 执行前需要重新校验的会话身份。
final class AgentConversationEffectScope {
  const AgentConversationEffectScope({
    required this.reductionScope,
    required this.providerId,
    required this.listenerGeneration,
    required this.threadId,
    this.runtimeId,
    this.connectionEpoch,
    this.providerLifecycleState,
    this.turnId,
  });

  final AgentConversationReductionScope reductionScope;
  final String providerId;
  final int listenerGeneration;
  final String? runtimeId;
  final int? connectionEpoch;

  /// 仅用于结构化诊断；detached runtime 的 critical 终态仍允许执行 effect，
  /// 因而不把瞬时 lifecycle 名称作为身份比较键。
  final String? providerLifecycleState;
  final String? threadId;

  /// effect 关联的 turn，供回调与日志使用；turn 完成后当前 turn 已经改变，
  /// 因而它不是 effect 有效性的比较键。
  final String? turnId;

  /// 返回携带指定 turn identity 的新 scope。
  AgentConversationEffectScope forTurn(String? value) {
    return AgentConversationEffectScope(
      reductionScope: reductionScope,
      providerId: providerId,
      listenerGeneration: listenerGeneration,
      runtimeId: runtimeId,
      connectionEpoch: connectionEpoch,
      providerLifecycleState: providerLifecycleState,
      threadId: threadId,
      turnId: value,
    );
  }

  /// 判断 effect 是否仍属于当前 live processor。
  bool matches(
    AgentConversationEffectScope? current, {
    bool requireThread = true,
  }) {
    if (current == null ||
        reductionScope != AgentConversationReductionScope.live ||
        current.reductionScope != AgentConversationReductionScope.live ||
        providerId != current.providerId ||
        listenerGeneration != current.listenerGeneration ||
        runtimeId != current.runtimeId ||
        connectionEpoch != current.connectionEpoch) {
      return false;
    }
    return !requireThread || threadId == current.threadId;
  }
}

/// reducer 产生、由 effect runner 执行的 application 副作用。
sealed class AgentConversationEffect {
  const AgentConversationEffect({
    required this.scope,
    this.requireThread = true,
    this.timing = AgentConversationEffectTiming.afterMutation,
  });

  final AgentConversationEffectScope scope;
  final bool requireThread;
  final AgentConversationEffectTiming timing;
}

/// 当前 turn 完成后通知应用组合层。
final class AgentTurnCompletedEffect extends AgentConversationEffect {
  const AgentTurnCompletedEffect({required super.scope, required this.turnId});

  final String turnId;
}

/// 记录 Provider 主动推送的模型目录。
final class AgentRecordModelCatalogEffect extends AgentConversationEffect {
  const AgentRecordModelCatalogEffect({
    required super.scope,
    required this.config,
    required this.models,
    required this.source,
  }) : super(requireThread: false);

  final AgentProviderConfig config;
  final AgentModelList models;
  final String source;
}

/// 记录已经被 Provider 归一化的错误事件。
///
/// 错误可能不属于当前选中 thread，但只要通过 listener/runtime gate，仍应记录诊断。
final class AgentLogProviderErrorEffect extends AgentConversationEffect {
  const AgentLogProviderErrorEffect({required super.scope, required this.event})
    : super(
        requireThread: false,
        timing: AgentConversationEffectTiming.beforeMutation,
      );

  final AgentErrorEvent event;
}
