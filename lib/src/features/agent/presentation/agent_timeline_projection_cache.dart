import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/presentation/agent_file_change_projection_cache.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_grouping.dart';

/// 单个 turn 的可缓存投影结果。
///
/// 只保存 presentation 派生数据，不持有 BuildContext / Widget / raw payload。
final class AgentTurnProjection {
  const AgentTurnProjection({
    required this.turnId,
    required this.contentRevision,
    required this.blocks,
  });

  final String turnId;

  /// 与 [AgentConversationTurnGroup.contentRevision] 对齐。
  final int contentRevision;

  /// 兼容旧字段名：等于 [contentRevision]。
  int get renderRevision => contentRevision;

  final List<AgentTimelineRenderBlock> blocks;
}

typedef AgentTimelineRenderBlocksBuilder =
    List<AgentTimelineRenderBlock> Function({
      required String turnId,
      required List<AgentTimelineEntry> entries,
    });

/// presentation 层 turn projection 缓存。
///
/// 命中条件：`turn.id` 相同且 `turn.contentRevision` 相同。
/// token / meta 变化不推进 contentRevision，故不重算 blocks。
/// 每个 turn 独立失效；live turn 更新不会重算历史 turn。
final class AgentTimelineProjectionCache {
  AgentTimelineProjectionCache({
    AgentTimelineRenderBlocksBuilder? buildBlocks,
    AgentFileChangeProjectionCache? fileChangeProjectionCache,
  }) : _blockBuilder = buildBlocks,
       _fileChangeProjectionCache =
           fileChangeProjectionCache ?? AgentFileChangeProjectionCache();

  final AgentTimelineRenderBlocksBuilder? _blockBuilder;
  final AgentFileChangeProjectionCache _fileChangeProjectionCache;
  final Map<String, AgentTurnProjection> _turns =
      <String, AgentTurnProjection>{};

  /// 实际调用 [buildAgentTimelineRenderBlocks]（或注入 builder）的次数。
  ///
  /// 仅供测试与性能诊断；不进入业务逻辑。
  int computeCount = 0;

  /// 解析 turn 的渲染块列表；命中缓存时返回同一列表实例。
  List<AgentTimelineRenderBlock> resolve(AgentConversationTurnGroup turn) {
    final contentRevision = turn.contentRevision != 0
        ? turn.contentRevision
        : turn.renderRevision;
    final cached = _turns[turn.id];
    if (cached != null && cached.contentRevision == contentRevision) {
      return cached.blocks;
    }
    computeCount += 1;
    final blocks =
        _blockBuilder?.call(turnId: turn.id, entries: turn.entries) ??
        buildAgentTimelineRenderBlocks(
          turnId: turn.id,
          entries: turn.entries,
          fileChangeProjectionCache: _fileChangeProjectionCache,
        );
    final projection = AgentTurnProjection(
      turnId: turn.id,
      contentRevision: contentRevision,
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
    _fileChangeProjectionCache.retainOnly(<String>{
      for (final turn in _turns.values)
        for (final block in turn.blocks)
          if (block case AgentTimelineFileEditGroupRenderBlock(:final group))
            for (final item in group.items) item.ownerEntryId,
    });
  }

  void clear() {
    _turns.clear();
    _fileChangeProjectionCache.clear();
    computeCount = 0;
  }

  /// 当前缓存的 turn 数量；测试用。
  int get cachedTurnCount => _turns.length;

  /// 指定 turn 是否有缓存条目；测试用。
  bool containsTurn(String turnId) => _turns.containsKey(turnId);

  /// 长正文实际投影次数，用于 resize/revision 性能回归。
  int get fileChangeComputeCount => _fileChangeProjectionCache.computeCount;
}
