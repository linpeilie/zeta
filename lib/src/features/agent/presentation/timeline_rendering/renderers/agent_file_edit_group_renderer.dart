/// 文件编辑组渲染条目。
library;

import 'package:flutter/widgets.dart';

import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_region_state.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_grouping.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_extent_math.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_renderer.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_pane_cards.dart';

/// 连续编辑操作折叠成的文件编辑组（也承接回合级 typed fallback）。
final class AgentFileEditGroupRenderer
    extends AgentTimelineRendererBase<AgentTimelineFileEditGroupRenderBlock> {
  /// 创建文件编辑组 renderer。
  const AgentFileEditGroupRenderer();

  @override
  Type get payloadType => AgentTimelineFileEditGroupRenderBlock;

  @override
  String kindOf(AgentTimelineFileEditGroupRenderBlock payload) =>
      AgentTimelineExtentKinds.fileEditGroup;

  @override
  Widget build(
    BuildContext context,
    AgentTimelineFileEditGroupRenderBlock payload,
    AgentTimelineRenderContext renderContext, {
    required AgentConversationTurnGroup turn,
    required AgentPendingInteractionState pendingState,
  }) {
    return AgentFileEditGroupCard(
      group: payload.group,
      controller: renderContext.controller,
      actions: renderContext.actions,
    );
  }

  @override
  double estimateExtent(
    AgentTimelineFileEditGroupRenderBlock payload, {
    required double crossAxisExtent,
    required double textScale,
    required AgentTimelineExpansionLookup expansion,
    required bool precededByOperationGroup,
    required bool followedByOperationGroup,
  }) {
    final metrics = AgentTimelineExtentMetrics.from(
      crossAxisExtent: crossAxisExtent,
      textScale: textScale,
    );
    // 内容区：折叠头约 30 + 各文件行；外间距与命令集相同规则。
    var content = 30.0;
    for (final item in payload.group.items) {
      if (expansion.isFileEditItemExpanded(item.id)) {
        content += 120;
      } else {
        content += 28;
      }
    }
    final outer = agentOperationGroupOuterExtent(
      precededByOperationGroup: precededByOperationGroup,
      followedByOperationGroup: followedByOperationGroup,
    );
    return (content + outer) * metrics.scale;
  }

  @override
  Object layoutRevision(
    AgentTimelineFileEditGroupRenderBlock payload,
    AgentTimelineExpansionLookup expansion,
  ) {
    final items = payload.group.items;
    return Object.hash(
      Object.hashAll(<Object>[
        for (final item in items)
          Object.hash(
            item.id,
            item.title,
            item.status,
            item.projection.snapshotRevision,
            item.projection.replayability,
            item.projection.changeId,
            item.projection.kind,
            item.projection.path,
            item.projection.destinationPath,
          ),
      ]),
      Object.hashAll(<Object>[
        for (final item in items)
          Object.hash(item.id, expansion.isFileEditItemExpanded(item.id)),
      ]),
    );
  }
}
