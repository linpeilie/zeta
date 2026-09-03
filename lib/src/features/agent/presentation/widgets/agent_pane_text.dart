import 'package:flutter/material.dart';

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_ui/zeta_ui.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_region_state.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_runtime_controller.dart';
import 'package:zeta/src/features/agent/presentation/agent_presentation_l10n.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_grouping.dart';
import 'package:zeta/src/ui/localization/app_localizations_x.dart';

String commandGroupSummary(
  AgentTimelineCommandGroup group,
  AppLocalizations l10n,
) {
  final counts = <AgentToolKind, int>{};
  final order = <AgentToolKind>[];
  for (final item in group.items) {
    if (!counts.containsKey(item.kind)) {
      order.add(item.kind);
    }
    counts[item.kind] = (counts[item.kind] ?? 0) + 1;
  }

  return order
      .map(
        (kind) =>
            l10n.agentCountTimes('${counts[kind]}', toolKindLabel(kind, l10n)),
      )
      .join(' · ');
}

String planPreviewText(String markdown) {
  for (final rawLine in markdown.split('\n')) {
    final preview = rawLine
        .trim()
        .replaceFirst(RegExp(r'^#+\s*'), '')
        .replaceFirst(RegExp(r'^[-*+]\s+(\[[ xX]\]\s+)?'), '')
        .replaceAll('`', '')
        .trim();
    if (preview.isNotEmpty) {
      return preview;
    }
  }
  return 'Plan';
}

InlineSpan fileEditGroupSummarySpan(
  BuildContext context,
  AgentTimelineFileEditGroup group,
) {
  final colors = IdeColors.of(context);
  final withStats = group.items.where(
    (item) => item.addedLines != null || item.removedLines != null,
  );
  final addedLines = withStats.fold<int>(
    0,
    (sum, item) => sum + (item.addedLines ?? 0),
  );
  final removedLines = withStats.fold<int>(
    0,
    (sum, item) => sum + (item.removedLines ?? 0),
  );
  // 回合级降级汇总用固定标题，与单次 fileChange 工具卡区分。
  final l10n = context.l10n;
  final label = group.isTurnFallback
      ? l10n.agentTurnChanges
      : l10n.agentFileCount('${group.items.length}');
  if (addedLines == 0 && removedLines == 0) {
    return TextSpan(text: label);
  }
  // 增删行数沿用 diff 语义色：新增为 success、删除为 error。
  return TextSpan(
    children: <InlineSpan>[
      TextSpan(text: label),
      const TextSpan(text: ' · '),
      TextSpan(
        text: '+$addedLines',
        style: TextStyle(
          color: colors.success.withValues(alpha: 0.98),
          fontWeight: FontWeight.w600,
        ),
      ),
      const TextSpan(text: ' / '),
      TextSpan(
        text: '-$removedLines',
        style: TextStyle(
          color: colors.error.withValues(alpha: 0.98),
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

String toolKindLabel(AgentToolKind kind, AppLocalizations l10n) {
  return kind.localizedLabel(l10n);
}

String? formatDuration(Duration? duration, {bool includeSubSecond = false}) =>
    formatAgentDuration(duration, includeSubSecond: includeSubSecond);

/// 对话流执行中文案：主 segment 时长 + turn 总时长。
///
/// 例：`思考中 · 24s · 共 1m 12s`、`启动中 · 共 3s`。
String liveActivityStatusText(
  AgentHeaderState state,
  DateTime now,
  AppLocalizations l10n,
) {
  final segmentLabel = state.runningActivityLabel;
  final segmentElapsed = formatDuration(
    resolveAgentElapsed(now: now, startedAt: state.segmentStartedAt),
    includeSubSecond: true,
  );
  final turnElapsed = formatDuration(
    resolveAgentElapsed(now: now, startedAt: state.turnStartedAt),
    includeSubSecond: true,
  );
  final parts = <String>[];
  if (segmentLabel != null) {
    if (segmentElapsed != null) {
      parts.add('$segmentLabel · $segmentElapsed');
    } else {
      parts.add(segmentLabel);
    }
  }
  if (turnElapsed != null) {
    parts.add(l10n.agentElapsedTotal(turnElapsed));
  }
  if (parts.isEmpty) {
    return l10n.agentRunning;
  }
  return parts.join(' · ');
}

/// 工具/思考卡旁的耗时文案。
String? toolElapsedLabel(
  AgentConversationRuntimeController controller,
  AgentToolCall toolCall,
  DateTime now,
) {
  final elapsed = controller.toolElapsedAt(toolCall, now);
  // 进行中不足 1 秒也给即时反馈；终态仍隐藏 0 时长。
  final live = toolCall.isActiveStatus && toolCall.duration == null;
  return formatDuration(elapsed, includeSubSecond: live);
}

String? threadOpenStatusText(AgentHeaderState state) {
  return switch (state.threadOpenPhase) {
    AgentThreadOpenPhase.loadingHistory => 'Loading thread history...',
    AgentThreadOpenPhase.openFailed =>
      'Thread open failed. Click this thread again to retry.',
    // 打开成功时，头栏可展示模型改道等非阻塞系统提示。
    AgentThreadOpenPhase.idle => state.systemNoticeLabel,
  };
}

/// 单个 turn 的 token 用量短标签（turn 增量，不展示上下文窗口占比）。
String? turnTokenUsageLabel(AgentTokenUsage? usage) {
  final total = usage?.totalTokens;
  if (total == null || total <= 0) {
    return null;
  }
  return '${usage!.displayTotalTokens!} tokens';
}

/// 当前会话累计 token 总量短标签；与上下文面板「总 Token」一致。
String? threadTotalTokenUsageLabel(AgentTokenUsage? usage) {
  final total = usage?.totalTokens;
  if (total == null || total <= 0) {
    return null;
  }
  return '${usage!.displayTotalTokens!} tokens';
}

/// 当前上下文窗口 token 用量的悬停明细（仅已用 / 上限 / 占比）。
String contextWindowTokenUsageTooltip(AgentTokenUsage? usage) {
  final total = usage?.totalTokens;
  final window = usage?.modelContextWindow;
  if (total == null || total <= 0 || window == null || window <= 0) {
    return '';
  }
  final tokenUsage = usage!;
  final percent = ((total / window) * 100).round();
  return [
    'Usage: $percent%',
    'Used: ${tokenUsage.displayTotalTokens}',
    'Total: ${tokenUsage.displayModelContextWindow}',
  ].join('\n');
}

/// 悬停时展示的 token 明细，含输入/缓存/输出/推理分项。
String tokenUsageTooltip(AgentTokenUsage? usage) {
  if (usage == null) {
    return '';
  }
  final parts = <String>[];
  if (usage.displayTotalTokens case final value?) {
    parts.add('Total: $value');
  }
  if (usage.displayModelContextWindow case final value?) {
    parts.add('Context window: $value');
  }
  if (usage.displayInputTokens case final value?) {
    parts.add('Input: $value');
  }
  if (usage.displayCachedInputTokens case final value?) {
    parts.add('Cached: $value');
  }
  if (usage.displayOutputTokens case final value?) {
    parts.add('Output: $value');
  }
  return parts.isEmpty ? '' : parts.join('\n');
}
