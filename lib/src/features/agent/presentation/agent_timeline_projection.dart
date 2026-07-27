import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_grouping.dart';

/// 时间线虚拟化视口中的稳定 item。
///
/// item 按 render block / activity / footer 粒度拆分，避免单个长 turn 迫使
/// [SliverList] 布局该 turn 的全部 Markdown、命令和 diff 子树。
sealed class AgentTimelineViewportItem {
  const AgentTimelineViewportItem({required this.id});

  /// 稳定 id，用于 [ValueKey] 与 `findChildIndexCallback`。
  final String id;
}

/// 「加载更早历史」入口。
final class AgentLoadOlderViewportItem extends AgentTimelineViewportItem {
  const AgentLoadOlderViewportItem() : super(id: 'load-older');
}

/// 单个 turn 内的一个稳定渲染块。
final class AgentBlockViewportItem extends AgentTimelineViewportItem {
  AgentBlockViewportItem({
    required this.turn,
    required this.block,
    required this.isLive,
  }) : super(
         id:
             '${_turnScope(turn: turn, isLive: isLive)}-block-'
             '${turn.id}-${block.id}',
       );

  final AgentConversationTurnGroup turn;
  final AgentTimelineRenderBlock block;
  final bool isLive;
}

/// live turn 的进行中活动状态。
final class AgentLiveActivityViewportItem extends AgentTimelineViewportItem {
  AgentLiveActivityViewportItem({required this.turn})
    : super(id: 'live-activity-${turn.id}');

  final AgentConversationTurnGroup turn;
}

/// 非 standby turn 的耗时、token 与模型配置 footer。
final class AgentTurnFooterViewportItem extends AgentTimelineViewportItem {
  AgentTurnFooterViewportItem({required this.turn, required this.isLive})
    : super(
        id: '${_turnScope(turn: turn, isLive: isLive)}-footer-${turn.id}',
      );

  final AgentConversationTurnGroup turn;
  final bool isLive;
}

typedef AgentTimelineBlocksResolver =
    List<AgentTimelineRenderBlock> Function(AgentConversationTurnGroup turn);

/// 将当前可见会话状态投影为稳定有序的 block 级视口 item 列表。
///
/// 顺序：
/// Load older → standby blocks → history blocks/footer
/// → live blocks/activity/footer
List<AgentTimelineViewportItem> projectAgentTimelineViewportItems({
  required bool hasOlderTurns,
  required AgentConversationTurnGroup? standbyTurn,
  required List<AgentConversationTurnGroup> visibleHistoryTurns,
  required AgentConversationTurnGroup? liveTurn,
  required AgentTimelineBlocksResolver resolveBlocks,
}) {
  final items = <AgentTimelineViewportItem>[];

  void appendTurn(AgentConversationTurnGroup turn, {required bool isLive}) {
    for (final block in resolveBlocks(turn)) {
      items.add(
        AgentBlockViewportItem(turn: turn, block: block, isLive: isLive),
      );
    }
    if (isLive && turn.status == AgentHistoryTurnStatus.running) {
      items.add(AgentLiveActivityViewportItem(turn: turn));
    }
    if (!turn.isStandby) {
      items.add(AgentTurnFooterViewportItem(turn: turn, isLive: isLive));
    }
  }

  if (hasOlderTurns) {
    items.add(const AgentLoadOlderViewportItem());
  }
  if (standbyTurn != null && standbyTurn.entries.isNotEmpty) {
    appendTurn(standbyTurn, isLive: false);
  }
  for (final turn in visibleHistoryTurns) {
    appendTurn(turn, isLive: false);
  }
  if (liveTurn != null) {
    appendTurn(liveTurn, isLive: true);
  }
  return List<AgentTimelineViewportItem>.unmodifiable(items);
}

/// 视口 item 的稳定 Widget key 字符串。
String agentTimelineViewportItemKey(AgentTimelineViewportItem item) {
  return 'timeline-viewport-${item.id}';
}

String _turnScope({
  required AgentConversationTurnGroup turn,
  required bool isLive,
}) {
  if (isLive) {
    return 'live';
  }
  return turn.isStandby ? 'standby' : 'history';
}
