import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_effect.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_intent.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_state.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

/// 纯同步转移：region 是运行事实的投影，命令只登记独立 OperationId。
Transition<AgentConversationSliceState, AgentConversationSliceEffect>
agentConversationSliceReduce(
  AgentConversationSliceState state,
  AgentConversationSliceIntent intent,
) {
  switch (intent) {
    case AgentConversationRegionsRefreshed():
      if (intent.isEmpty) return Transition.none(state);
      return Transition.stateOnly(
        state.copyWith(
          header: intent.header,
          composer: intent.composer,
          pendingInteractions: intent.pendingInteractions,
          expansion: intent.expansion,
          history: intent.history,
        ),
      );
    case AgentConversationCommandRequested(:final command):
      return Transition(
        state.copyWith(
          pendingOperations: Set.unmodifiable({
            ...state.pendingOperations,
            command.id,
          }),
          clearLastFailure: true,
        ),
        [AgentConversationExecuteCommandEffect(command)],
      );
    case AgentConversationOperationSettled(:final id, :final failureKind):
      if (!state.pendingOperations.contains(id)) return Transition.none(state);
      return Transition.stateOnly(
        state.copyWith(
          pendingOperations: Set.unmodifiable(
            state.pendingOperations.where((candidate) => candidate != id),
          ),
          lastFailure: failureKind == null
              ? state.lastFailure
              : AgentConversationOperationFailure(
                  operationId: id,
                  kind: failureKind,
                ),
        ),
      );
  }
}
