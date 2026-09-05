import 'package:flutter/material.dart';
import 'package:zeta_markdown/zeta_markdown.dart';

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_ui/zeta_ui.dart';

/// 折叠摘要文字的不透明度：弱于正文但可辨认。
const double kAgentSummaryTextAlpha = 0.68;

/// hover 背景的不透明度（border 色稀释）。
const double kAgentHoverBackgroundAlpha = 0.12;

/// 卡片内次要图标的不透明度。
const double kAgentSecondaryIconAlpha = 0.65;

/// diff 增删统计文字的不透明度。
const double kAgentDiffStatTextAlpha = 0.98;

TextStyle agentSummaryTextStyle(BuildContext context) {
  final colors = IdeColors.of(context);
  final textStyles = IdeTextStyles.of(context);
  // 折叠摘要：中等字重 + 低对比，弱于正文但可辨认。
  return textStyles.bodyMedium.copyWith(
    fontWeight: FontWeight.w500,
    color: colors.textSecondary.withValues(alpha: kAgentSummaryTextAlpha),
  );
}

TextStyle agentMetaTextStyle(
  BuildContext context, {
  FontWeight fontWeight = FontWeight.w400,
}) {
  final textStyles = IdeTextStyles.of(context);
  return textStyles.meta.copyWith(fontWeight: fontWeight);
}

Color agentHoverBackground(BuildContext context) {
  return IdeColors.of(
    context,
  ).border.withValues(alpha: kAgentHoverBackgroundAlpha);
}

/// 操作组（命令集 / 文件编辑组）外间距：由列表层 [Padding] 包一层，卡片自身零 margin。
///
/// **块内紧、块外松**：连续操作之间只留 [IdeSpacing.space2]，让一串操作读成
/// 一块「过程记录」；只有操作块与正文的交界处才留 [IdeSpacing.space10]。
///
/// 折叠行本身只有 20px 高，之前每行固定 10px 外边距意味着三分之一的垂直空间
/// 是缝隙——这才是「操作日志占地过多」的真正来源，不是行本身胖。
EdgeInsets operationGroupOuterPadding({
  required bool precededByOperationGroup,
  required bool followedByOperationGroup,
}) {
  return EdgeInsets.only(
    top: precededByOperationGroup ? 0 : IdeSpacing.space10,
    bottom: followedByOperationGroup ? IdeSpacing.space2 : IdeSpacing.space10,
  );
}

/// 根据工具类型选择图标。
IconData toolIcon(AgentToolKind kind) {
  return switch (kind) {
    AgentToolKind.read => Icons.description_outlined,
    AgentToolKind.edit => Icons.edit_outlined,
    AgentToolKind.delete => Icons.delete_outline,
    AgentToolKind.move => Icons.drive_file_move_outline,
    AgentToolKind.search => Icons.search_rounded,
    AgentToolKind.execute => Icons.terminal_rounded,
    AgentToolKind.think => Icons.psychology_alt_outlined,
    AgentToolKind.fetch => Icons.cloud_download_outlined,
    AgentToolKind.other => Icons.build_outlined,
  };
}

IconData historyEventIcon(AgentHistoryEventKind kind) {
  return switch (kind) {
    AgentHistoryEventKind.permission => Icons.verified_user_outlined,
    AgentHistoryEventKind.warning => Icons.warning_amber_rounded,
    AgentHistoryEventKind.search => Icons.search_rounded,
    AgentHistoryEventKind.system => Icons.info_outline_rounded,
  };
}

Color historyEventAccent(AgentHistoryEventKind kind, IdeColors colors) {
  return switch (kind) {
    AgentHistoryEventKind.warning => colors.warning,
    AgentHistoryEventKind.permission ||
    AgentHistoryEventKind.search ||
    AgentHistoryEventKind.system => colors.textTertiary,
  };
}

IdeStatusCardTone historyEventTone(AgentHistoryEventKind kind) {
  return switch (kind) {
    AgentHistoryEventKind.warning => IdeStatusCardTone.warning,
    AgentHistoryEventKind.permission ||
    AgentHistoryEventKind.search ||
    AgentHistoryEventKind.system => IdeStatusCardTone.neutral,
  };
}

/// 代码块高亮的 Graphite 语义映射。
///
/// 不映射的槽位（link）继续走包内从 `linkStyle` 的推导，与正文链接同色。
/// 颜色一律取自 token，明暗主题各自解析——这里不写死任何 hex。
MarkdownCodeHighlightPalette agentCodeHighlightPalette(IdeColors colors) {
  return MarkdownCodeHighlightPalette(
    // 关键字与正文链接同源（accent），代码块里最重的一档。
    keyword: colors.accent,
    string: colors.success,
    number: colors.warning,
    // 注释压到三级文本，避免与正文抢注意力。
    comment: colors.textTertiary,
    type: colors.info,
    title: colors.textPrimary,
    meta: colors.textSecondary,
    punctuation: colors.textSecondary,
  );
}

MarkdownThemeData agentMarkdownTheme(BuildContext context) {
  final colors = IdeColors.of(context);
  final textStyles = IdeTextStyles.of(context);
  final base = textStyles.proseBody;
  final codeStyle = agentCodeTextStyle(context, baseStyle: base);

  return MarkdownThemeData.fallback(
    context,
    maxContentWidth: IdeMetrics.contentMaxWidth,
  ).copyWith(
    padding: EdgeInsets.zero,
    blockSpacing: IdeSpacing.space8,
    listItemSpacing: IdeSpacing.space4,
    bodyStyle: base,
    quoteStyle: textStyles.bodyMedium.copyWith(color: colors.textSecondary),
    linkStyle: base.copyWith(color: colors.accent, fontWeight: FontWeight.w600),
    inlineCodeStyle: codeStyle,
    inlineCodeBackgroundColor: colors.surfaceElevated.withValues(alpha: 0.92),
    codeBlockStyle: codeStyle,
    codeBlockPadding: IdeSpacing.cardPadding,
    codeBlockBackgroundColor: colors.surfaceElevated,
    codeBlockBorderRadius: IdeRadius.allSmall,
    codeHighlightPalette: agentCodeHighlightPalette(colors),
    quotePadding: const EdgeInsets.fromLTRB(
      IdeSpacing.space12,
      IdeSpacing.space8,
      IdeSpacing.space12,
      IdeSpacing.space8,
    ),
    quoteBackgroundColor: colors.surfaceElevated.withValues(alpha: 0.82),
    quoteBorderColor: colors.info,
    quoteBorderWidth: 3,
    quoteBorderRadius: IdeRadius.allSmall,
    tableHeaderStyle: textStyles.titleSmall.copyWith(
      fontWeight: FontWeight.w700,
    ),
    tableCellPadding: const EdgeInsets.symmetric(
      horizontal: IdeSpacing.space8,
      vertical: IdeSpacing.space6,
    ),
    tableBorderColor: colors.borderSubtle,
    tableHeaderBackgroundColor: colors.surfaceElevated,
    tableRowBackgroundColor: Colors.transparent,
    dividerColor: colors.borderSubtle,
    selectionColor: colors.primaryMuted,
    imagePlaceholderBackgroundColor: colors.surfaceElevated,
    heading1Style: textStyles.displayLarge.copyWith(
      fontWeight: FontWeight.w700,
    ),
    heading2Style: textStyles.displaySmall.copyWith(
      fontWeight: FontWeight.w700,
    ),
    heading3Style: textStyles.titleLarge.copyWith(fontWeight: FontWeight.w700),
    heading4Style: textStyles.titleSmall.copyWith(fontWeight: FontWeight.w700),
    heading5Style: textStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700),
    heading6Style: textStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700),
    showHeading1Divider: false,
    showHeading2Divider: false,
  );
}

MarkdownThemeData agentUserBubbleMarkdownTheme(BuildContext context) {
  final colors = IdeColors.of(context);
  final textStyles = IdeTextStyles.of(context);
  final base = agentMarkdownTheme(context);
  // 用户/系统消息内收敛：标题统一降级为正文加粗，代码/引用/表格底色用控制面。
  // 控制面（surfaceElevated）比用户气泡的 hoverSurface 底色或系统日志行的纯
  // 画布底色都更深一档，两层天然有对比，不需要再对代码块/引用做透明度调和。
  // 用户正文比 Agent 长文重一档字重：Agent 走 proseBody（w400 / 行高 1.55）
  // 追求长段可读，用户提问通常只有一两句，加重后在回溯时更容易被扫到，
  // 和左侧竖线、等宽角色前缀共同构成身份锚点。
  final bodyStyle = textStyles.bodyMedium.copyWith(
    height: 1.4,
    color: colors.textPrimary,
    fontWeight: FontWeight.w500,
  );
  return base.copyWith(
    bodyStyle: bodyStyle,
    heading1Style: bodyStyle.copyWith(fontWeight: FontWeight.w700),
    heading2Style: bodyStyle.copyWith(fontWeight: FontWeight.w700),
    heading3Style: bodyStyle.copyWith(fontWeight: FontWeight.w700),
    heading4Style: bodyStyle.copyWith(fontWeight: FontWeight.w700),
    heading5Style: bodyStyle.copyWith(fontWeight: FontWeight.w700),
    heading6Style: bodyStyle.copyWith(fontWeight: FontWeight.w700),
    codeBlockBackgroundColor: colors.controlSurface,
    quoteBackgroundColor: colors.controlSurface,
    tableHeaderBackgroundColor: colors.controlSurface,
  );
}

TextStyle agentCodeTextStyle(BuildContext context, {TextStyle? baseStyle}) {
  final colors = IdeColors.of(context);
  final textStyles = IdeTextStyles.of(context);
  final effectiveBase =
      baseStyle ?? textStyles.codeSmall.copyWith(color: colors.textPrimary);
  return effectiveBase.copyWith(
    color: colors.textPrimary,
    fontFamily: textStyles.codeSmall.fontFamily,
    height: 1.35,
    backgroundColor: Colors.transparent,
  );
}

BoxDecoration agentCodeBlockDecoration(IdeColors colors) {
  return BoxDecoration(
    color: colors.surfaceElevated,
    borderRadius: IdeRadius.allSmall,
    border: Border.all(color: colors.borderSubtle),
  );
}

Map<String, TextStyle> agentHighlightTheme(BuildContext context) {
  final colors = IdeColors.of(context);
  final base = agentCodeTextStyle(context);
  return <String, TextStyle>{
    'root': base,
    'meta': base.copyWith(color: colors.textSecondary.withValues(alpha: 0.9)),
    'comment': base.copyWith(
      color: colors.textSecondary.withValues(alpha: 0.72),
    ),
    'addition': base.copyWith(
      color: colors.success.withValues(alpha: 0.98),
      backgroundColor: colors.success.withValues(alpha: 0.12),
    ),
    'deletion': base.copyWith(
      color: colors.error.withValues(alpha: 0.98),
      backgroundColor: colors.error.withValues(alpha: 0.1),
    ),
    'emphasis': base.copyWith(fontStyle: FontStyle.italic),
    'strong': base.copyWith(fontWeight: FontWeight.w700),
  };
}

double? contextWindowTokenUsageProgressValue(AgentTokenUsage? usage) {
  final total = usage?.totalTokens;
  final window = usage?.modelContextWindow;
  if (total == null || total <= 0 || window == null || window <= 0) {
    return null;
  }
  return (total / window).clamp(0.0, 1.0);
}
