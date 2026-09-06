import 'package:zeta_foundation/zeta_foundation.dart';
import '../agent_command_outcome.dart';
import 'agent_conversation_region_state.dart';
import 'agent_conversation_command_payload.dart';

sealed class AgentConversationSliceIntent {
  const AgentConversationSliceIntent();
}

final class AgentConversationRegionsRefreshed
    extends AgentConversationSliceIntent {
  const AgentConversationRegionsRefreshed({
    this.header,
    this.composer,
    this.pendingInteractions,
    this.expansion,
    this.history,
  });

  final AgentHeaderState? header;
  final AgentComposerState? composer;
  final AgentPendingInteractionState? pendingInteractions;
  final AgentExpansionState? expansion;
  final AgentConversationHistoryState? history;

  /// 本次是否没有任何 region 变化。
  bool get isEmpty =>
      header == null &&
      composer == null &&
      pendingInteractions == null &&
      expansion == null &&
      history == null;
}

final class AgentConversationCommandRequested
    extends AgentConversationSliceIntent {
  const AgentConversationCommandRequested(this.command);
  final AgentConversationCommandEnvelope command;
}

final class AgentConversationOperationSettled
    extends AgentConversationSliceIntent {
  const AgentConversationOperationSettled(this.id, this.failureKind);
  final OperationId id;
  final AgentCommandFailureKind? failureKind;
}
