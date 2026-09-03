/// 零高度条目的共享 renderer 基类。
///
/// 这些条目会进入渲染块序列（因而占一个 viewport item），但在流内不展示——
/// 它们的交互面在 Composer 上方的 dock 或别的分组块里。既然实际高度是 0，
/// [kindOf] 就必须报 [AgentTimelineExtentKinds.hidden] 且估算 0：迁移前它们
/// 按 48px（或 fileEditGroup 口径）估算而实测 0px，长会话滚动锚点会漂。
library;

import 'package:flutter/widgets.dart';

import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_region_state.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_extent_descriptor.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_renderer.dart';

/// 不在流内渲染的条目。
abstract base class AgentHiddenEntryRenderer<P extends AgentTimelineEntry>
    extends AgentTimelineRendererBase<P> {
  /// 创建零高度 renderer。
  const AgentHiddenEntryRenderer();

  @override
  String kindOf(P payload) => AgentTimelineExtentKinds.hidden;

  @override
  Widget build(
    BuildContext context,
    P payload,
    AgentTimelineRenderContext renderContext, {
    required AgentConversationTurnGroup turn,
    required AgentPendingInteractionState pendingState,
  }) => const SizedBox.shrink();

  @override
  double estimateExtent(
    P payload, {
    required double crossAxisExtent,
    required double textScale,
    required AgentTimelineExpansionLookup expansion,
    required bool precededByOperationGroup,
    required bool followedByOperationGroup,
  }) => 0;

  /// 零高度条目不能当导航锚点：跳过去等于跳到不可见位置。
  @override
  bool get rendersInline => false;
}
