import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';

/// 时间线虚拟化视口中的稳定 item。
///
/// 阶段 4 先按 turn 粒度投影；后续可继续拆成 block / footer 级 item，
/// 而不必改动 Store 或 Provider 协议。
sealed class AgentTimelineViewportItem {
  const AgentTimelineViewportItem({required this.id});

  /// 稳定 id，用于 [ValueKey] 与 `findChildIndexCallback`。
  final String id;
}

/// 「加载更早历史」入口。
final class AgentLoadOlderViewportItem extends AgentTimelineViewportItem {
  const AgentLoadOlderViewportItem() : super(id: 'load-older');
}

/// 一个完整 turn（history / standby / live）对应的视口项。
final class AgentTurnViewportItem extends AgentTimelineViewportItem {
  AgentTurnViewportItem({
    required this.turnId,
    required this.isLive,
    required this.isStandby,
  }) : super(
         id: isLive
             ? 'live-turn-$turnId'
             : isStandby
             ? 'standby-turn-$turnId'
             : 'history-turn-$turnId',
       );

  final String turnId;
  final bool isLive;
  final bool isStandby;
}

/// 将当前可见会话状态投影为稳定有序的视口 item 列表。
///
/// 顺序：
/// Load older → standby → visible history turns → live turn
List<AgentTimelineViewportItem> projectAgentTimelineViewportItems({
  required bool hasOlderTurns,
  required AgentConversationTurnGroup? standbyTurn,
  required List<AgentConversationTurnGroup> visibleHistoryTurns,
  required AgentConversationTurnGroup? liveTurn,
}) {
  final items = <AgentTimelineViewportItem>[];
  if (hasOlderTurns) {
    items.add(const AgentLoadOlderViewportItem());
  }
  if (standbyTurn != null && standbyTurn.entries.isNotEmpty) {
    items.add(
      AgentTurnViewportItem(
        turnId: standbyTurn.id,
        isLive: false,
        isStandby: true,
      ),
    );
  }
  for (final turn in visibleHistoryTurns) {
    items.add(
      AgentTurnViewportItem(
        turnId: turn.id,
        isLive: false,
        isStandby: turn.isStandby,
      ),
    );
  }
  if (liveTurn != null) {
    items.add(
      AgentTurnViewportItem(
        turnId: liveTurn.id,
        isLive: true,
        isStandby: false,
      ),
    );
  }
  return List<AgentTimelineViewportItem>.unmodifiable(items);
}

/// 视口 item 的稳定 Widget key 字符串。
String agentTimelineViewportItemKey(AgentTimelineViewportItem item) {
  return 'timeline-viewport-${item.id}';
}
