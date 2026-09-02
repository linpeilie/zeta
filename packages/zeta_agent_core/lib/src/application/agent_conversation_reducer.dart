// ignore_for_file: prefer_initializing_formals

import 'package:zeta_agent_core/src/application/agent_conversation_effect.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_mutation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_reducer_context.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_session_state.dart';
import 'package:zeta_agent_core/src/application/reduction/agent_event_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/agent_event_handler_registry.dart';
import 'package:zeta_agent_core/src/application/reduction/default_agent_handlers.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/session_state_support.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';
import 'package:zeta_agent_core/src/domain/fallback_agent_ui_text_catalog.dart';

export 'package:zeta_agent_core/src/application/agent_conversation_reducer_context.dart';

/// 将规范化 [AgentEvent] 纯同步归约为 nextState/timeline/UI/snapshot/effect 描述。
///
/// 门面：按 runtimeType 分发给共享 handler 注册表。live / history / replay
/// 共用同一份 registry，但各自持有独立 [AgentReducerScratch]（G3）。
final class AgentConversationReducer {
  AgentConversationReducer._({
    required this.scope,
    required AgentReducerScratch scratch,
    AgentEventHandlerRegistry? registry,
  }) : _scratch = scratch,
       _registry = registry ?? defaultAgentEventHandlerRegistry;

  factory AgentConversationReducer.live({
    AgentConversationClock? clock,
    AgentConversationLocalTimelineIdGenerator? timelineIds,
    AgentUiTextCatalog textCatalog = const FallbackAgentUiTextCatalog(),
  }) {
    return AgentConversationReducer._(
      scope: AgentConversationReductionScope.live,
      scratch: AgentReducerScratch(
        timelineIds:
            timelineIds ??
            AgentConversationLocalTimelineIdGenerator(clock: clock),
        textCatalog: textCatalog,
      ),
    );
  }

  factory AgentConversationReducer.history({
    AgentConversationClock? clock,
    AgentUiTextCatalog textCatalog = const FallbackAgentUiTextCatalog(),
  }) {
    return AgentConversationReducer._(
      scope: AgentConversationReductionScope.history,
      scratch: AgentReducerScratch(
        timelineIds: AgentConversationLocalTimelineIdGenerator(clock: clock),
        textCatalog: textCatalog,
      ),
    );
  }

  factory AgentConversationReducer.replay({
    AgentConversationClock? clock,
    AgentUiTextCatalog textCatalog = const FallbackAgentUiTextCatalog(),
  }) {
    return AgentConversationReducer._(
      scope: AgentConversationReductionScope.replay,
      scratch: AgentReducerScratch(
        timelineIds: AgentConversationLocalTimelineIdGenerator(clock: clock),
        textCatalog: textCatalog,
      ),
    );
  }

  final AgentConversationReductionScope scope;
  final AgentReducerScratch _scratch;
  final AgentEventHandlerRegistry _registry;

  /// 步骤 11 贯通注入；步骤 12 起消费 Zeta 自有 context-free 文案。
  AgentUiTextCatalog get textCatalog => _scratch.textCatalog;

  AgentConversationReduction reduce(
    AgentEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
  ) {
    assert(
      context.scope == scope,
      'Reducer 与 context 的 live/history/replay scope 必须一致。',
    );
    return _registry.dispatch(event, state, context, _scratch);
  }

  /// Provider stream onDone 与 thread/closed 共用的中断收尾。不是事件归约，不进注册表。
  AgentConversationReduction settleInterruptedTurn({
    required String fallbackTurnId,
    required AgentConversationSessionState state,
    required AgentConversationReducerContext context,
  }) {
    return settleInterruptedTurnReduction(
      fallbackTurnId: fallbackTurnId,
      state: state,
      context: context,
    );
  }
}
