/// 流内计划审批卡渲染条目。
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_region_state.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_extent_math.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_renderer.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_pane_cards.dart';

/// 计划审批：仍待审批时在流内渲染交互卡，决定后条目即被移除。
final class AgentPlanApprovalRenderer
    extends AgentTimelineRendererBase<AgentPlanApprovalTimelineEntry> {
  /// 创建计划审批 renderer。
  const AgentPlanApprovalRenderer();

  @override
  Type get payloadType => AgentPlanApprovalTimelineEntry;

  @override
  // 审批卡在流内展示完整计划正文，不能按 tool card 的固定高度估算。
  String kindOf(AgentPlanApprovalTimelineEntry payload) =>
      AgentTimelineExtentKinds.planInteraction;

  @override
  Widget build(
    BuildContext context,
    AgentPlanApprovalTimelineEntry payload,
    AgentTimelineRenderContext renderContext, {
    required AgentConversationTurnGroup turn,
    required AgentPendingInteractionState pendingState,
  }) {
    return buildAgentPlanApprovalCard(
      context,
      payload.request,
      controller: renderContext.controller,
      actions: renderContext.actions,
      planRevisionDrafts: renderContext.planRevisionDrafts,
    );
  }

  @override
  double estimateExtent(
    AgentPlanApprovalTimelineEntry payload, {
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
    // 审批卡在流内始终是交互态：正文全文 + 底部输入与动作栏。
    return math.max(
      24.0,
      estimateAgentMarkdownExtent(
            payload.request.markdown,
            width: metrics.width,
            lineHeight: metrics.lineHeight,
            scale: metrics.scale,
          ) +
          agentPlanInteractionChromeExtent(metrics.scale),
    );
  }

  @override
  Object layoutRevision(
    AgentPlanApprovalTimelineEntry payload,
    AgentTimelineExpansionLookup expansion,
  ) {
    final request = payload.request;
    return Object.hash(
      Object.hash(
        request.id,
        request.title,
        request.markdown.length,
        request.markdown.hashCode,
        request.todos.length,
      ),
      0,
    );
  }
}
