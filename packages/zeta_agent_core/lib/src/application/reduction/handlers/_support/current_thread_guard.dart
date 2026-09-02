import 'package:zeta_agent_core/src/application/agent_conversation_reducer_context.dart';

/// 当前 thread / turn 是否应处理该事件。
///
/// 有 sessionId 时只比 selectedThreadId，不再加强 turnId 校验。
bool shouldHandleCurrent(
  AgentConversationReducerContext context, {
  String? sessionId,
  String? turnId,
}) {
  if (sessionId != null) {
    return context.selectedThreadId == sessionId;
  }
  if (turnId != null) {
    return context.hasTurn(turnId) || turnId == context.pendingTurnGroupId;
  }
  return true;
}
