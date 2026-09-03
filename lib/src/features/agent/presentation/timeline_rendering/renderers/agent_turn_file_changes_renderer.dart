/// 回合级文件变更条目：流内零高度。
library;

import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_extent_math.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/renderers/agent_hidden_entry_renderer.dart';

/// 防御性登记。
///
/// 正常路径下 `buildAgentTimelineRenderBlocks` 会把回合级快照转成文件编辑组，
/// 快照为空时直接丢弃——这类 entry 不会自己成块。真到达时按零高度处理，与迁移
/// 前 sections 渲染 `SizedBox.shrink()` 的实际表现一致。
final class AgentTurnFileChangesRenderer
    extends AgentHiddenEntryRenderer<AgentTurnFileChangesTimelineEntry> {
  /// 创建回合级文件变更 renderer。
  const AgentTurnFileChangesRenderer();

  @override
  Type get payloadType => AgentTurnFileChangesTimelineEntry;

  @override
  Object layoutRevision(
    AgentTurnFileChangesTimelineEntry payload,
    AgentTimelineExpansionLookup expansion,
  ) {
    final snapshot = payload.snapshot;
    return Object.hash(
      Object.hash(
        payload.turnId,
        snapshot.revision,
        snapshot.replayability,
        snapshot.changes.length,
      ),
      0,
    );
  }
}
