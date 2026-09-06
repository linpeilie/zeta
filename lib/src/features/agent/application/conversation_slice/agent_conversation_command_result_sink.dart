import 'package:zeta_foundation/zeta_foundation.dart';
import 'agent_conversation_command_result.dart';

/// Runner 只通过单次结果回流，不持有 Ref 或可写状态。
abstract interface class AgentConversationCommandResultSink {
  void settle(OperationId id, AgentConversationCommandResult result);
  bool isOpenOperation(OperationId id, Object ownerLifetimeToken);
}
