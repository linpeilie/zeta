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

/// 注册表建造器。默认表 seal 之后，四种审批语义 handler 不允许再被覆盖（G5）。
final class AgentEventHandlerRegistryBuilder {
  final Map<Type, _HandlerEntry> _entries = <Type, _HandlerEntry>{};
  var _sealed = false;

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
