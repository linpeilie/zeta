import 'package:zeta_agent_core/src/application/agent_conversation_mutation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_reducer_context.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_session_state.dart';
import 'package:zeta_agent_core/src/application/reduction/agent_event_handler.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';

typedef _Invoke =
    AgentConversationReduction Function(
      AgentEvent,
      AgentConversationSessionState,
      AgentConversationReducerContext,
      AgentReducerScratch,
    );

final class _HandlerEntry {
  const _HandlerEntry(this.invoke);

  final _Invoke invoke;
}

/// 按事件 runtimeType 分发的归约注册表。
final class AgentEventHandlerRegistry {
  AgentEventHandlerRegistry._(this._entries);

  final Map<Type, _HandlerEntry> _entries;

  static AgentEventHandlerRegistryBuilder builder() =>
      AgentEventHandlerRegistryBuilder();

  bool hasHandlerFor(AgentEvent event) =>
      _entries.containsKey(event.runtimeType);

  AgentConversationReduction dispatch(
    AgentEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
    AgentReducerScratch scratch,
  ) {
    final entry = _entries[event.runtimeType];
    if (entry == null) {
      throw UnsupportedError(
        'No AgentEventHandler registered for ${event.runtimeType}',
      );
    }
    return entry.invoke(event, state, context, scratch);
  }
}

/// 注册表建造器。默认表 seal 之后，审批类事件 handler 不允许再被覆盖（G5）。
final class AgentEventHandlerRegistryBuilder {
  final Map<Type, _HandlerEntry> _entries = <Type, _HandlerEntry>{};
  var _sealed = false;

  /// seal 之后禁止 Provider 覆盖的事件类型。
  ///
  /// 覆盖 G5 四种审批语义中**有对应 Provider 事件**的三种：权限、提问、
  /// Plan 审批（各含 requested / resolved）。
  ///
  /// 第四种「Plan 执行交接」**不在这里**，因为它没有对应的 [AgentEvent]——
  /// 它是 Zeta 本地概念，由 [AgentTurnCompletedEvent] 的 handler 产出
  /// `AgentAutoStartPlanExecutionEffect` 触发。它的保护在 **effect 层**：
  /// 该 effect 强制 `requireThread: true`，scope 必须带 turnId，执行前由
  /// `DefaultAgentConversationEffectRunner` 重新校验 listener generation /
  /// runtime / epoch（见 `agent_conversation_effect_runner_test.dart` 的
  /// 「runtime 换代后不再自动启动 Plan 执行」）。
  ///
  /// 因此 [AgentTurnCompletedEvent] 是**可覆盖**的：turn 完成有大量正当的
  /// Provider 定制需求。覆盖者仍然绕不过 effect 层的身份校验，但**可以**改变
  /// 是否发射该 effect——覆盖 turn completed handler 的 PR 必须在描述里说明
  /// 对 Plan 执行交接的影响。
  static const Set<Type> _nonOverridable = <Type>{
    AgentPermissionRequestedEvent,
    AgentPermissionResolvedEvent,
    AgentQuestionRequestedEvent,
    AgentQuestionResolvedEvent,
    AgentPlanApprovalRequestedEvent,
    AgentPlanApprovalResolvedEvent,
  };

  /// 注册一个 handler。同一类型重复注册即覆盖。
  void register<E extends AgentEvent>(AgentEventHandler<E> handler) {
    if (_sealed && _nonOverridable.contains(E)) {
      throw StateError('审批语义 handler 不允许被 Provider 覆盖（G5）：$E');
    }
    _entries[E] = _HandlerEntry(
      (event, state, context, scratch) =>
          handler.handle(event as E, state, context, scratch),
    );
  }

  /// 禁止后续覆盖四种审批语义 handler。
  void seal() {
    _sealed = true;
  }

  AgentEventHandlerRegistry build() => AgentEventHandlerRegistry._(
    Map<Type, _HandlerEntry>.unmodifiable(_entries),
  );
}
