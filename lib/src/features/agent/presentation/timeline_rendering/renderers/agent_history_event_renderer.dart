/// 历史事件卡渲染条目。
library;

import 'package:flutter/widgets.dart';

import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_region_state.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_extent_descriptor.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_extent_math.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_renderer.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_pane_cards.dart';

/// 历史回放里的中立事件条目。
final class AgentHistoryEventRenderer
    extends AgentTimelineRendererBase<AgentHistoryEventTimelineEntry> {
  /// 创建历史事件 renderer。
  const AgentHistoryEventRenderer();

  @override
  Type get payloadType => AgentHistoryEventTimelineEntry;

  @override
  String kindOf(AgentHistoryEventTimelineEntry payload) =>
      AgentTimelineExtentKinds.system;

  @override
  Widget build(
    BuildContext context,
    AgentHistoryEventTimelineEntry payload,
    AgentTimelineRenderContext renderContext, {
    required AgentConversationTurnGroup turn,
    required AgentPendingInteractionState pendingState,
  }) {
    return AgentHistoryEventCard(event: payload.event);
  }

  @override
  double estimateExtent(
    AgentHistoryEventTimelineEntry payload, {
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
    // 迁移前落在 _estimateEntry 的 48 兜底分支。
    return 48 * metrics.scale;
  }

  @override
  Object layoutRevision(
    AgentHistoryEventTimelineEntry payload,
    AgentTimelineExpansionLookup expansion,
  ) {
    final event = payload.event;
    return Object.hash(
      Object.hash(
        event.id,
        event.kind,
        event.title,
        event.description,
        event.content?.length,
      ),
      0,
    );
  }
}
