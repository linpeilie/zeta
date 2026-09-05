/// 会话消息渲染条目（用户 / agent 正文 / 计划 / 系统）。
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_region_state.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_extent_math.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_renderer.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_pane_messages.dart';

/// 消息条目：同一种 entry 覆盖四个 kind，按 role 与 isPlan 区分。
final class AgentMessageRenderer
    extends AgentTimelineRendererBase<AgentMessageTimelineEntry> {
  /// 创建消息 renderer。
  const AgentMessageRenderer();

  @override
  Type get payloadType => AgentMessageTimelineEntry;

  @override
  String kindOf(AgentMessageTimelineEntry payload) {
    final message = payload.message;
    if (message.isPlan) {
      return AgentTimelineExtentKinds.plan;
    }
    return switch (message.role) {
      AgentMessageRole.user => AgentTimelineExtentKinds.userMessage,
      AgentMessageRole.agent => AgentTimelineExtentKinds.agentMarkdown,
      AgentMessageRole.system => AgentTimelineExtentKinds.system,
    };
  }

  @override
  Widget build(
    BuildContext context,
    AgentMessageTimelineEntry payload,
    AgentTimelineRenderContext renderContext, {
    required AgentConversationTurnGroup turn,
    required AgentPendingInteractionState pendingState,
  }) {
    final isLiveTurn = renderContext.controller.liveTurnState?.id == turn.id;
    return AgentMessageEntry(
      message: payload.message,
      // 历史与 live 正文均全文渲染，禁止折叠预览。
      useStreamingMarkdown: isLiveTurn,
      controller: renderContext.controller,
      markdownCache: renderContext.markdownCache,
      planRevisionDrafts: renderContext.planRevisionDrafts,
      planExecutionHandoff: pendingState.planExecutionHandoff,
    );
  }

  @override
  double estimateExtent(
    AgentMessageTimelineEntry payload, {
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
    final scale = metrics.scale;
    final message = payload.message;
    final text = message.text;
    final isInteractivePlan =
        message.isPlan && expansion.isPlanMessageInteractive(message.id);
    if (text.trim().isEmpty) {
      return isInteractivePlan
          ? 32 * scale + agentPlanInteractionChromeExtent(scale)
          : 32 * scale;
    }

    final kind = kindOf(payload);
    final padding = 24 * scale;
    final base = kind == AgentTimelineExtentKinds.agentMarkdown
        ? 200 * scale
        : kind == AgentTimelineExtentKinds.plan
        ? 120 * scale
        : 48 * scale;

    final content =
        padding +
        estimateAgentMarkdownExtent(
          text,
          width: metrics.width,
          lineHeight: metrics.lineHeight,
          scale: scale,
        );
    // 冷启动基线：取 content 与 kind 默认的较大者。不要截断长消息估算，
    // 否则单项超过旧上限后会在滚动帧内产生巨大的同步 measurement delta。
    final estimated = math.max(base * 0.5, content);
    // 交互态计划卡额外挂着输入框与动作栏，不加上会严重低估。
    final chrome = isInteractivePlan
        ? agentPlanInteractionChromeExtent(scale)
        : 0.0;
    return math.max(24.0, estimated + chrome);
  }

  @override
  Object layoutRevision(
    AgentMessageTimelineEntry payload,
    AgentTimelineExpansionLookup expansion,
  ) {
    final message = payload.message;
    return Object.hash(
      Object.hash(
        message.id,
        message.kind,
        message.phase,
        message.status,
        message.role,
        message.text.length,
        message.text.hashCode,
      ),
      // plan 消息在折叠卡与交互卡之间切换时高度差异巨大，必须让缓存测量失效。
      message.isPlan ? expansion.isPlanMessageInteractive(message.id) : 0,
    );
  }

  @override
  ValueListenable<bool>? prepareWarmEntry(
    AgentMessageTimelineEntry payload,
    AgentTimelineRenderContext renderContext, {
    required bool isLive,
  }) {
    final message = payload.message;
    if (message.role != AgentMessageRole.agent || message.isPlan) {
      return null;
    }
    return renderContext.markdownCache.prepareWarmEntry(
      messageId: message.id,
      data: message.text,
      preferIncrementalUpdate: isLive,
    );
  }
}
