import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_grouping.dart';

/// 单个 turn 的可缓存投影结果。
///
/// 只保存 presentation 派生数据，不持有 BuildContext / Widget / raw payload。
final class AgentTurnProjection {
  const AgentTurnProjection({
    required this.turnId,
    required this.renderRevision,
    required this.blocks,
  });

  final String turnId;
  final int renderRevision;
  final List<AgentTimelineRenderBlock> blocks;
}

typedef AgentTimelineRenderBlocksBuilder =
    List<AgentTimelineRenderBlock> Function({
      required String turnId,
      required List<AgentTimelineEntry> entries,
    });

/// presentation 层 turn projection 缓存。
///
/// 命中条件：`turn.id` 相同且 `turn.renderRevision` 相同。
/// 每个 turn 独立失效；live turn 更新不会重算历史 turn。
final class AgentTimelineProjectionCache {
  AgentTimelineProjectionCache({AgentTimelineRenderBlocksBuilder? buildBlocks})
    : _buildBlocks = buildBlocks ?? buildAgentTimelineRenderBlocks;

  final AgentTimelineRenderBlocksBuilder _buildBlocks;
  final Map<String, AgentTurnProjection> _turns =
      <String, AgentTurnProjection>{};

  /// 实际调用 [buildAgentTimelineRenderBlocks]（或注入 builder）的次数。
  ///
  /// 仅供测试与性能诊断；不进入业务逻辑。
  int computeCount = 0;

  /// 解析 turn 的渲染块列表；命中缓存时返回同一列表实例。
  List<AgentTimelineRenderBlock> resolve(AgentConversationTurnGroup turn) {
    final cached = _turns[turn.id];
    if (cached != null && cached.renderRevision == turn.renderRevision) {
      return cached.blocks;
    }
    computeCount += 1;
    final blocks = _buildBlocks(turnId: turn.id, entries: turn.entries);
    final projection = AgentTurnProjection(
      turnId: turn.id,
      renderRevision: turn.renderRevision,
      blocks: blocks,
    );
    _turns[turn.id] = projection;
    return projection.blocks;
  }

  /// 完整投影（含 revision 元数据）；测试可用来断言命中的 revision。
  AgentTurnProjection resolveProjection(AgentConversationTurnGroup turn) {
    resolve(turn);
    return _turns[turn.id]!;
  }

  /// 只保留当前仍可见的 turn，避免关闭会话后缓存无限增长。
  void retainOnly(Set<String> visibleTurnIds) {
    _turns.removeWhere((turnId, _) => !visibleTurnIds.contains(turnId));
  }

  void clear() {
    _turns.clear();
    computeCount = 0;
  }

  /// 当前缓存的 turn 数量；测试用。
  int get cachedTurnCount => _turns.length;

  /// 指定 turn 是否有缓存条目；测试用。
  bool containsTurn(String turnId) => _turns.containsKey(turnId);
}
