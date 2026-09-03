/// 工具调用卡渲染条目。
library;

import 'package:flutter/widgets.dart';

import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_region_state.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_extent_descriptor.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_extent_math.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_renderer.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_pane_cards.dart';

/// 未被折叠进命令集的单个工具调用。
final class AgentToolCallRenderer
    extends AgentTimelineRendererBase<AgentToolTimelineEntry> {
  /// 创建工具调用 renderer。
  const AgentToolCallRenderer();

  @override
  Type get payloadType => AgentToolTimelineEntry;

  @override
  String kindOf(AgentToolTimelineEntry payload) =>
      AgentTimelineExtentKinds.toolCard;

  @override
  Widget build(
    BuildContext context,
    AgentToolTimelineEntry payload,
    AgentTimelineRenderContext renderContext, {
    required AgentConversationTurnGroup turn,
    required AgentPendingInteractionState pendingState,
  }) {
    return AgentToolCallCard(
      toolCall: payload.toolCall,
      controller: renderContext.controller,
    );
  }

  @override
  double estimateExtent(
    AgentToolTimelineEntry payload, {
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
    return 56 * metrics.scale;
  }

  @override
  Object layoutRevision(
    AgentToolTimelineEntry payload,
    AgentTimelineExpansionLookup expansion,
  ) {
    final toolCall = payload.toolCall;
    return Object.hash(
      Object.hash(
        toolCall.id,
        toolCall.kind,
        toolCall.status,
        toolCall.title,
        toolCall.content?.length,
        toolCall.content?.hashCode,
        toolCall.duration?.inMilliseconds,
      ),
      0,
    );
  }
}
