import 'package:zeta_agent_core/src/application/agent_conversation_mutation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_reducer_context.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_session_state.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';

/// 单个事件类型的归约器。
abstract interface class AgentEventHandler<E extends AgentEvent> {
  AgentConversationReduction handle(
    E event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
    AgentReducerScratch scratch,
  );
}

/// 跨事件的可变归约状态。
///
/// live / history / replay 各自持有独立实例（G3）。
final class AgentReducerScratch {
  AgentReducerScratch({required this.timelineIds, required this.textCatalog});

  final AgentConversationLocalTimelineIdGenerator timelineIds;
  final AgentUiTextCatalog textCatalog;

  /// 已展示过的弃用提示摘要，用于去重。
  final Set<String> shownDeprecationSummaries = <String>{};

  /// 最近一次已展示的错误文案，用于去重。
  String? lastShownErrorMessage;

  String nextLocalTimelineId(String prefix) => timelineIds.next(prefix);
}
