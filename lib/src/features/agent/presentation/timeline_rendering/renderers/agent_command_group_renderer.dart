/// 命令集渲染条目。
library;

import 'package:flutter/widgets.dart';

import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_region_state.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_grouping.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_extent_math.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_renderer.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_pane_cards.dart';

/// 取单个 entry 的布局指纹。
///
/// 命令集的内容指纹要包含组内每个条目的内容，而条目指纹归条目自己的 renderer
/// 所有；注册表装配时把查表闭包注入进来，避免在这里再写一次 entry 类型分支。
typedef AgentTimelineEntryLayoutRevision =
    Object Function(
      AgentTimelineEntry entry,
      AgentTimelineExpansionLookup expansion,
    );

/// 连续非编辑操作折叠成的命令集。
final class AgentCommandGroupRenderer
    extends AgentTimelineRendererBase<AgentTimelineCommandGroupRenderBlock> {
  /// 创建命令集 renderer。
  const AgentCommandGroupRenderer({required this.entryLayoutRevision});

  /// 组内条目的指纹查询（由注册表装配注入）。
  final AgentTimelineEntryLayoutRevision entryLayoutRevision;

  @override
  Type get payloadType => AgentTimelineCommandGroupRenderBlock;

  @override
  String kindOf(AgentTimelineCommandGroupRenderBlock payload) =>
      AgentTimelineExtentKinds.commandGroup;

  @override
  Widget build(
    BuildContext context,
    AgentTimelineCommandGroupRenderBlock payload,
    AgentTimelineRenderContext renderContext, {
    required AgentConversationTurnGroup turn,
    required AgentPendingInteractionState pendingState,
  }) {
    return AgentCommandGroupCard(
      group: payload.group,
      controller: renderContext.controller,
    );
  }

  @override
  double estimateExtent(
    AgentTimelineCommandGroupRenderBlock payload, {
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
    // 内容区约 30；展开后每条 28。外间距与 `operationGroupOuterPadding` 一致。
    final group = payload.group;
    final content = expansion.isCommandGroupExpanded(group.id)
        ? 30 + group.items.length * 28
        : 30;
    final outer = agentOperationGroupOuterExtent(
      precededByOperationGroup: precededByOperationGroup,
      followedByOperationGroup: followedByOperationGroup,
    );
    return (content + outer) * metrics.scale;
  }

  @override
  Object layoutRevision(
    AgentTimelineCommandGroupRenderBlock payload,
    AgentTimelineExpansionLookup expansion,
  ) {
    final group = payload.group;
    return Object.hash(
      Object.hashAll(<Object>[
        for (final item in group.items)
          Object.hash(
            item.id,
            item.kind,
            item.title,
            entryLayoutRevision(item.entry, expansion),
          ),
      ]),
      expansion.isCommandGroupExpanded(group.id),
    );
  }
}
