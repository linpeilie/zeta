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

/// 单个 turn 内的一个稳定渲染块。
final class AgentBlockViewportItem extends AgentTimelineViewportItem {
  AgentBlockViewportItem({
    required this.turn,
    required this.block,
    required this.isLive,
  }) : super(
         id:
             '${_turnScope(turn: turn)}-block-'
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
    : super(id: '${_turnScope(turn: turn)}-footer-${turn.id}');

  final AgentConversationTurnGroup turn;
  final bool isLive;
}

typedef AgentTimelineBlocksResolver =
    List<AgentTimelineRenderBlock> Function(AgentConversationTurnGroup turn);

/// 将当前可见会话状态投影为稳定有序的 block 级视口 item 列表。
///
/// 顺序：standby blocks → history blocks/footer → live blocks/activity/footer
///
/// [showLiveActivity] 为 false 时不生成 live 活动条（例如 Plan 浮层已展示当前
/// 步骤进度，避免计划卡下方再叠一条「进行中」工具条）。
List<AgentTimelineViewportItem> projectAgentTimelineViewportItems({
  required AgentConversationTurnGroup? standbyTurn,
  required List<AgentConversationTurnGroup> visibleHistoryTurns,
  required AgentConversationTurnGroup? liveTurn,
  required AgentTimelineBlocksResolver resolveBlocks,
  bool showLiveActivity = true,
}) {
  final items = <AgentTimelineViewportItem>[];

  void appendTurn(AgentConversationTurnGroup turn, {required bool isLive}) {
    for (final block in resolveBlocks(turn)) {
      items.add(
        AgentBlockViewportItem(turn: turn, block: block, isLive: isLive),
      );
    }
    if (isLive &&
        showLiveActivity &&
        turn.status == AgentHistoryTurnStatus.running) {
      items.add(AgentLiveActivityViewportItem(turn: turn));
    }
    if (!turn.isStandby) {
      items.add(AgentTurnFooterViewportItem(turn: turn, isLive: isLive));
    }
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
  assert(
    items.map((item) => item.id).toSet().length == items.length,
    'Agent timeline viewport item ID 必须唯一。',
  );
  return List<AgentTimelineViewportItem>.unmodifiable(items);
}

/// 视口 item 的稳定 Widget key 字符串。
String agentTimelineViewportItemKey(AgentTimelineViewportItem item) {
  return 'timeline-viewport-${item.id}';
}

String _turnScope({required AgentConversationTurnGroup turn}) {
  // live/history 是同一 turn 的展示阶段，不能进入虚拟列表的稳定身份。
  return turn.isStandby ? 'standby' : 'turn';
}
