/// 会话内对话导航（Conversation Navigation Rail）的中立模型与派生逻辑。
///
/// 只消费 [AgentConversationTurnGroup] / 视口 item 身份，不读 Provider raw
/// payload，也不落盘提问正文。
library;

import 'package:flutter/foundation.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_grouping.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_projection.dart';
import 'package:zeta_ui/zeta_ui.dart';
import 'package:zeta/src/ui/localization/generated/app_localizations.dart';

/// 少于该数量时隐藏导航轨，避免短对话视觉噪声。
const int kAgentConversationNavigationMinEntries = 3;

/// 提问摘要最大字符数（仅 UI 展示，不持久化）。
const int kAgentConversationNavigationLabelMaxChars = 48;

/// 导航项回合状态（与 Provider 无关的展示语义）。
enum AgentConversationNavigationStatus {
  /// 流式生成中。
  streaming,

  /// 已成功完成。
  completed,

  /// 失败。
  failed,

  /// 用户中断。
  interrupted,

  /// 未知 / 未标注。
  unknown,
}

/// 单个导航项：绑定稳定 turn 身份与视口锚点，不含布局坐标。
@immutable
final class AgentConversationNavigationEntry {
  /// 创建导航项。
  const AgentConversationNavigationEntry({
    required this.entryId,
    required this.turnId,
    required this.ordinal,
    required this.label,
    required this.status,
    required this.anchorViewportItemId,
    this.startedAt,
    this.tokenUsage,
  });

  /// 稳定导航身份（与 [turnId] 一致，便于扩展）。
  final String entryId;

  /// 所属回合 id（Provider adapter 已确定）。
  final String turnId;

  /// 从 1 起的展示序号。
  final int ordinal;

  /// 用户提问摘要（仅内存 UI）。
  final String label;

  /// 回合展示状态。
  final AgentConversationNavigationStatus status;

  /// 跳转用的视口 item 稳定 id（优先用户提问块）。
  final String anchorViewportItemId;

  /// 回合开始时间（悬停预览可选）。
  final DateTime? startedAt;

  /// 本回合 token 用量（悬停预览；与 turn footer 同源）。
  final AgentTokenUsage? tokenUsage;
}

/// 从可见 history + live turn 派生导航项列表。
///
/// - 跳过 standby；
/// - 每个非 standby turn 至多一项；
/// - live 与 history 同 id 时只保留一项（history 优先）；
/// - 锚点优先用户消息 block，否则 turn 内首个 block。
List<AgentConversationNavigationEntry> buildAgentConversationNavigationEntries({
  required List<AgentConversationTurnGroup> visibleHistoryTurns,
  required AgentConversationTurnGroup? liveTurn,
  AgentTimelineBlocksResolver resolveBlocks = _defaultResolveBlocks,
}) {
  final turns = <AgentConversationTurnGroup>[];
  final seenIds = <String>{};

  void addTurn(AgentConversationTurnGroup turn) {
    if (turn.isStandby) {
      return;
    }
    if (!seenIds.add(turn.id)) {
      return;
    }
    turns.add(turn);
  }

  for (final turn in visibleHistoryTurns) {
    addTurn(turn);
  }
  if (liveTurn != null) {
    addTurn(liveTurn);
  }

  final entries = <AgentConversationNavigationEntry>[];
  for (final turn in turns) {
    final isLive = liveTurn != null && liveTurn.id == turn.id;
    final userMessage = _firstUserMessage(turn);
    final blocks = resolveBlocks(turn);
    final anchorBlock =
        _preferUserMessageBlock(blocks, userMessage) ??
        (blocks.isEmpty ? null : blocks.first);
    if (anchorBlock == null) {
      // 尚无可见块（极早的 live 空回合）时跳过，避免不可跳转的幽灵项。
      continue;
    }
    final anchorItem = AgentBlockViewportItem(
      turn: turn,
      block: anchorBlock,
      isLive: isLive,
    );
    entries.add(
      AgentConversationNavigationEntry(
        entryId: turn.id,
        turnId: turn.id,
        ordinal: entries.length + 1,
        label: _summarizePromptLabel(userMessage?.text),
        status: _mapTurnStatus(turn.status),
        anchorViewportItemId: anchorItem.id,
        startedAt: turn.startedAt,
        tokenUsage: turn.tokenUsage,
      ),
    );
  }
  return List<AgentConversationNavigationEntry>.unmodifiable(entries);
}

/// 是否应展示导航轨。
bool shouldShowAgentConversationNavigation(
  List<AgentConversationNavigationEntry> entries,
) {
  return entries.length >= kAgentConversationNavigationMinEntries;
}

/// 视口 item 所属 turn id。
String? agentTimelineViewportItemTurnId(AgentTimelineViewportItem item) {
  return switch (item) {
    AgentBlockViewportItem(:final turn) => turn.id,
    AgentLiveActivityViewportItem(:final turn) => turn.id,
    AgentTurnFooterViewportItem(:final turn) => turn.id,
  };
}

/// 根据滚动位置解析当前导航回合。
///
/// 使用视口上方阅读线（[viewportProbeFraction]）映射到 extent index，再落到
/// 最近的导航 turn；不测量 Widget 高度。
String? resolveActiveNavigationTurnId({
  required List<AgentConversationNavigationEntry> entries,
  required List<AgentTimelineViewportItem> items,
  required IdeVirtualListController controller,
  required double scrollPixels,
  required double contentTopInset,
  required double viewportDimension,
  double viewportProbeFraction = 0.12,
}) {
  if (entries.isEmpty || items.isEmpty) {
    return null;
  }
  final extentIndex = controller.extentIndex;
  if (extentIndex.length == 0) {
    // 尚未 synchronize：回退到末项（流式跟随底部时合理）。
    return entries.last.turnId;
  }

  final probeInContent =
      (scrollPixels - contentTopInset) +
      (viewportDimension * viewportProbeFraction).clamp(0.0, viewportDimension);
  final safeProbe = probeInContent.isFinite ? probeInContent : 0.0;
  final itemIndex = extentIndex.indexAtOffset(safeProbe);
  if (itemIndex == kIdeExtentIndexEmptySentinel ||
      itemIndex < 0 ||
      itemIndex >= items.length) {
    return entries.last.turnId;
  }

  final navTurnIds = <String>{for (final entry in entries) entry.turnId};
  // 从探针项向前找最近的可导航 turn。
  for (var i = itemIndex; i >= 0; i--) {
    final turnId = agentTimelineViewportItemTurnId(items[i]);
    if (turnId != null && navTurnIds.contains(turnId)) {
      return turnId;
    }
  }
  for (var i = itemIndex + 1; i < items.length; i++) {
    final turnId = agentTimelineViewportItemTurnId(items[i]);
    if (turnId != null && navTurnIds.contains(turnId)) {
      return turnId;
    }
  }
  return entries.first.turnId;
}

/// 计算跳转到导航锚点所需的 scroll pixels（含 [contentTopInset]）。
///
/// 返回 null 表示锚点尚未进入 extent index。
double? resolveNavigationScrollOffset({
  required AgentConversationNavigationEntry entry,
  required IdeVirtualListController controller,
  required double contentTopInset,
  required double maxScrollExtent,
}) {
  final index = controller.indexOfId(entry.anchorViewportItemId);
  if (index == null) {
    return null;
  }
  final contentOffset = controller.extentIndex.offsetOf(index);
  final target = contentTopInset + contentOffset;
  if (!target.isFinite) {
    return null;
  }
  if (maxScrollExtent <= 0) {
    return 0;
  }
  return target.clamp(0.0, maxScrollExtent);
}

/// 悬停/无障碍用的多行预览文案（仅内存）。
String buildAgentConversationNavigationTooltip(
  AgentConversationNavigationEntry entry,
  AppLocalizations l10n,
) {
  final buffer = StringBuffer()
    ..writeln(l10n.agentTurnOrdinal('${entry.ordinal}'))
    ..writeln(entry.label.isEmpty ? l10n.agentNoPromptSummary : entry.label)
    ..write(l10n.agentStatusWithValue(_statusLabel(entry.status, l10n)));
  final tokenLabel = agentConversationNavigationTokenLabel(entry.tokenUsage);
  if (tokenLabel != null) {
    buffer
      ..writeln()
      ..write(tokenLabel);
  }
  if (entry.startedAt != null) {
    final t = entry.startedAt!.toLocal();
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    buffer
      ..writeln()
      ..write(l10n.agentTimeWithValue('$hh:$mm'));
  }
  return buffer.toString();
}

/// 导航预览用的 turn token 短标签；口径与 turn footer 一致。
String? agentConversationNavigationTokenLabel(AgentTokenUsage? usage) {
  final total = usage?.totalTokens;
  if (total == null || total <= 0) {
    return null;
  }
  return '${usage!.displayTotalTokens!} tokens';
}

List<AgentTimelineRenderBlock> _defaultResolveBlocks(
  AgentConversationTurnGroup turn,
) {
  return buildAgentTimelineRenderBlocks(turnId: turn.id, entries: turn.entries);
}

AgentConversationMessage? _firstUserMessage(AgentConversationTurnGroup turn) {
  for (final entry in turn.entries) {
    if (entry is AgentMessageTimelineEntry &&
        entry.message.role == AgentMessageRole.user) {
      return entry.message;
    }
  }
  return null;
}

AgentTimelineRenderBlock? _preferUserMessageBlock(
  List<AgentTimelineRenderBlock> blocks,
  AgentConversationMessage? userMessage,
) {
  if (userMessage == null) {
    return null;
  }
  final expectedId = 'message-${userMessage.id}';
  for (final block in blocks) {
    if (block is AgentTimelineEntryRenderBlock && block.id == expectedId) {
      return block;
    }
  }
  return null;
}

String _summarizePromptLabel(String? text) {
  final normalized = (text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) {
    return '';
  }
  if (normalized.length <= kAgentConversationNavigationLabelMaxChars) {
    return normalized;
  }
  return '${normalized.substring(0, kAgentConversationNavigationLabelMaxChars)}…';
}

AgentConversationNavigationStatus _mapTurnStatus(
  AgentHistoryTurnStatus? status,
) {
  return switch (status) {
    AgentHistoryTurnStatus.running =>
      AgentConversationNavigationStatus.streaming,
    AgentHistoryTurnStatus.completed =>
      AgentConversationNavigationStatus.completed,
    AgentHistoryTurnStatus.failed => AgentConversationNavigationStatus.failed,
    AgentHistoryTurnStatus.interrupted =>
      AgentConversationNavigationStatus.interrupted,
    AgentHistoryTurnStatus.unknown ||
    null => AgentConversationNavigationStatus.unknown,
  };
}

String _statusLabel(
  AgentConversationNavigationStatus status,
  AppLocalizations l10n,
) {
  return switch (status) {
    AgentConversationNavigationStatus.streaming => l10n.agentStatusStreaming,
    AgentConversationNavigationStatus.completed => l10n.agentStatusCompleted,
    AgentConversationNavigationStatus.failed => l10n.agentStatusFailed,
    AgentConversationNavigationStatus.interrupted =>
      l10n.agentStatusInterrupted,
    AgentConversationNavigationStatus.unknown => l10n.agentStatusUnknown,
  };
}
