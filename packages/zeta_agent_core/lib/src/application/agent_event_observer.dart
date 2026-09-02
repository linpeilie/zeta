import 'package:zeta_agent_core/src/application/agent_conversation_mutation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_reducer.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';

/// 事件处理完成后的只读旁路观察者。
///
/// **契约（违反即回退）：**
/// - 只读。不得回写 TimelineStore、不得产生 effect、不得触发 UI 发布。
/// - 观察者抛出的异常由 processor 吞掉并降级为诊断日志，绝不影响主线。
/// - 看到的是**已经应用完**的结果；想在应用前介入请用 effect，不要用观察者。
///
/// 典型实现：turn 上下文记录、事件录制、调试面板。
abstract interface class AgentEventObserver {
  void onProcessed(
    AgentEvent event,
    AgentConversationReduction reduction,
    AgentConversationReducerContext context,
  );
}
