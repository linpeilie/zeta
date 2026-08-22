import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/presentation/agent_file_change_projection.dart';

/// 单项投影函数；测试可注入计数实现验证缓存行为。
typedef AgentFileChangeItemProjector =
    AgentFileChangeItemProjection Function({
      required String ownerEntryId,
      required int snapshotRevision,
      required AgentFileChangeReplayability replayability,
      required AgentFileChange change,
    });

typedef _SnapshotKey = ({String ownerEntryId, int revision});
typedef _ItemKey = ({String ownerEntryId, int revision, String changeId});

/// 以 owner + revision + change id 为键的文件变更 projection 缓存。
///
/// 宽度不是内容 key；同一 snapshot 在连续 resize 中返回同一 projection 实例。
final class AgentFileChangeProjectionCache {
  AgentFileChangeProjectionCache({AgentFileChangeItemProjector? projectItem})
    : _projectItem = projectItem ?? projectAgentFileChange;

  final AgentFileChangeItemProjector _projectItem;
  final Map<_SnapshotKey, AgentFileChangeProjection> _snapshots =
      <_SnapshotKey, AgentFileChangeProjection>{};
  final Map<_ItemKey, AgentFileChangeItemProjection> _items =
      <_ItemKey, AgentFileChangeItemProjection>{};

  /// 实际发生的单项内容投影次数。
  int computeCount = 0;

  /// 解析或命中一个 owner 的完整 snapshot。
  AgentFileChangeProjection resolve({
    required String ownerEntryId,
    required AgentFileChangeSnapshot snapshot,
  }) {
    final snapshotKey = (
      ownerEntryId: ownerEntryId,
      revision: snapshot.revision,
    );
    final cached = _snapshots[snapshotKey];
    if (cached != null) {
      return cached;
    }

    _snapshots.removeWhere((key, _) => key.ownerEntryId == ownerEntryId);
    _items.removeWhere(
      (key, _) =>
          key.ownerEntryId == ownerEntryId && key.revision != snapshot.revision,
    );
    final projectedItems = <AgentFileChangeItemProjection>[];
    for (final change in snapshot.changes) {
      final itemKey = (
        ownerEntryId: ownerEntryId,
        revision: snapshot.revision,
        changeId: change.id,
      );
      final item = _items[itemKey] ??= _computeItem(
        ownerEntryId: ownerEntryId,
        snapshot: snapshot,
        change: change,
      );
      projectedItems.add(item);
    }
    final projection = AgentFileChangeProjection(
      ownerEntryId: ownerEntryId,
      revision: snapshot.revision,
      replayability: snapshot.replayability,
      items: projectedItems,
    );
    _snapshots[snapshotKey] = projection;
    return projection;
  }

  AgentFileChangeItemProjection _computeItem({
    required String ownerEntryId,
    required AgentFileChangeSnapshot snapshot,
    required AgentFileChange change,
  }) {
    computeCount += 1;
    return _projectItem(
      ownerEntryId: ownerEntryId,
      snapshotRevision: snapshot.revision,
      replayability: snapshot.replayability,
      change: change,
    );
  }

  /// 仅保留仍可见的 owner，避免已关闭会话长期占用正文投影。
  void retainOnly(Set<String> visibleOwnerEntryIds) {
    _snapshots.removeWhere(
      (key, _) => !visibleOwnerEntryIds.contains(key.ownerEntryId),
    );
    _items.removeWhere(
      (key, _) => !visibleOwnerEntryIds.contains(key.ownerEntryId),
    );
  }

  void clear() {
    _snapshots.clear();
    _items.clear();
    computeCount = 0;
  }

  int get cachedOwnerCount => _snapshots.length;
  int get cachedItemCount => _items.length;
}
