import 'package:zeta_agent_core/src/application/agent_conversation_mutation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_reducer_context.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_session_state.dart';
import 'package:zeta_agent_core/src/application/reduction/agent_event_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/reduction_result.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';

/// 更新 provider 连接状态。
final class StatusHandler implements AgentEventHandler<AgentStatusEvent> {
  const StatusHandler();

  @override
  AgentConversationReduction handle(
    AgentStatusEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
    AgentReducerScratch scratch,
  ) {
    return acceptedReduction(
      state.copyWith(status: event.status),
      // 空 immediate request 仍可吸收并冲刷已有的 next-frame pending。
    );
  }
}
