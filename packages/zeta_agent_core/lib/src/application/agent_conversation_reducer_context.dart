import 'package:zeta_agent_core/src/application/agent_conversation_effect.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';

typedef AgentConversationClock = DateTime Function();

/// 会话时间线本地条目的同步 identity 生成器。
///
/// live facade 与 live reducer 共用一个实例，保持命令侧和事件侧 entryId 的单调唯一性；
/// history/replay 必须各自创建实例，避免跨 reduction scope 共享 identity 状态。
final class AgentConversationLocalTimelineIdGenerator {
  AgentConversationLocalTimelineIdGenerator({AgentConversationClock? clock})
    : _clock = clock ?? DateTime.now;

  final AgentConversationClock _clock;
  int _sequence = 0;

  String next(String prefix) {
    _sequence += 1;
    return '$prefix-${_clock().microsecondsSinceEpoch}-$_sequence';
  }
}

/// reducer 所需的只读会话视图。
///
/// [hasTurn] 与 [isHistoryTurnId] 是 O(1)/增量 Store 查询端口，避免每个 delta
/// 为了接收判断复制完整 Timeline。
final class AgentConversationReducerContext {
  const AgentConversationReducerContext({
    required this.scope,
    required this.selectedThreadId,
    required this.requiresResumedSelectedThread,
    required this.pendingTurnGroupId,
    required this.hasTurn,
    required this.isHistoryTurnId,
    required this.hasRunningTurnExcluding,
    required this.modelsRefreshing,
    required this.activeProviderName,
    required this.activeProviderConfig,
    required this.effectScope,
  });

  final AgentConversationReductionScope scope;
  final String? selectedThreadId;
  final bool requiresResumedSelectedThread;
  final String? pendingTurnGroupId;
  final bool Function(String turnId) hasTurn;
  final bool Function(String turnId) isHistoryTurnId;

  /// 排除指定 turn 后，是否仍有 running turn。
  ///
  /// 供 turn 终态归约判断"这一回合结束后会话是否仍在运行"，
  /// 避免 reducer 依赖 timeline mutation 的应用顺序。
  final bool Function(String excludedTurnId) hasRunningTurnExcluding;
  final bool modelsRefreshing;
  final String activeProviderName;
  final AgentProviderConfig activeProviderConfig;
  final AgentConversationEffectScope effectScope;
}
