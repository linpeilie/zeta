import 'package:zeta_agent_core/src/application/agent_conversation_reducer.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';
import 'package:zeta_agent_core/src/domain/fallback_agent_ui_text_catalog.dart';

/// live/history/replay 各自持有独立可变 identity 状态的 reducer 集合。
final class AgentConversationReducerContexts {
  factory AgentConversationReducerContexts({
    AgentConversationClock? clock,
    AgentConversationLocalTimelineIdGenerator? liveTimelineIds,
    AgentUiTextCatalog textCatalog = const FallbackAgentUiTextCatalog(),
  }) {
    return AgentConversationReducerContexts._(
      clock,
      liveTimelineIds,
      textCatalog,
    );
  }

  AgentConversationReducerContexts._(
    this._clock,
    this._liveTimelineIds,
    this._textCatalog,
  );

  final AgentConversationClock? _clock;
  final AgentConversationLocalTimelineIdGenerator? _liveTimelineIds;
  final AgentUiTextCatalog _textCatalog;

  /// 生产路径唯一消费者。
  late final AgentConversationReducer live = AgentConversationReducer.live(
    clock: _clock,
    timelineIds: _liveTimelineIds,
    textCatalog: _textCatalog,
  );

  /// 历史加载路径预留；当前仅测试消费（G3 隔离守卫）。
  late final AgentConversationReducer history =
      AgentConversationReducer.history(
        clock: _clock,
        textCatalog: _textCatalog,
      );

  /// 回放路径预留；当前仅测试消费（G3 隔离守卫）。
  late final AgentConversationReducer replay = AgentConversationReducer.replay(
    clock: _clock,
    textCatalog: _textCatalog,
  );
}
