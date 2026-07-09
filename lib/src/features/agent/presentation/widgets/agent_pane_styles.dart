part of '../agent_pane.dart';

TextStyle _agentSummaryTextStyle(BuildContext context) {
  final colors = IdeColors.of(context);
  final textStyles = IdeTextStyles.of(context);
  return textStyles.bodyMedium.copyWith(
    fontWeight: FontWeight.w600,
    color: colors.textSecondary.withValues(alpha: 0.9),
  );
}

TextStyle _agentItemTextStyle(
  BuildContext context, {
  FontWeight fontWeight = FontWeight.w500,
}) {
  final colors = IdeColors.of(context);
  final textStyles = IdeTextStyles.of(context);
  return textStyles.bodyMedium.copyWith(
    fontWeight: fontWeight,
    color: colors.textSecondary.withValues(alpha: 0.88),
  );
}

TextStyle _agentMetaTextStyle(
  BuildContext context, {
  double alpha = 0.68,
  FontWeight fontWeight = FontWeight.w400,
}) {
  final colors = IdeColors.of(context);
  final textStyles = IdeTextStyles.of(context);
  return textStyles.bodySmall.copyWith(
    fontWeight: fontWeight,
    color: colors.textSecondary.withValues(alpha: alpha),
  );
}

Color _agentHoverBackground(BuildContext context) {
  return IdeColors.of(context).border.withValues(alpha: 0.12);
}

String _commandGroupSummary(AgentTimelineCommandGroup group) {
  final counts = <AgentToolKind, int>{};
  final order = <AgentToolKind>[];
  for (final item in group.items) {
    if (!counts.containsKey(item.kind)) {
      order.add(item.kind);
    }
    counts[item.kind] = (counts[item.kind] ?? 0) + 1;
  }

  return order
      .map((kind) => '${counts[kind]} 次${_toolKindLabel(kind)}')
      .join(' · ');
}

String _planPreviewText(String markdown) {
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

bool _shouldCollapseMarkdown(String markdown) {
  return markdown.length >= _markdownCollapseLengthThreshold ||
      _codeBlockLineCount(markdown) >= _markdownCollapseLineThreshold;
}

String _markdownPreviewText(String markdown) {
  final parts = <String>[];
  for (final rawLine in LineSplitter.split(markdown)) {
    final preview = rawLine
        .trim()
        .replaceFirst(RegExp(r'^#+\s*'), '')
        .replaceFirst(RegExp(r'^[-*+]\s+(\[[ xX]\]\s+)?'), '')
        .replaceAll('`', '')
        .trim();
    if (preview.isEmpty) {
      continue;
    }
    parts.add(preview);
    if (parts.length >= 4 || parts.join(' ').length >= 220) {
      break;
    }
  }
  return parts.isEmpty ? 'Markdown message' : parts.join('  ');
}

InlineSpan _fileEditGroupSummarySpan(
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
  // 回合级聚合 diff 用固定标题，与单次 fileChange 工具卡区分。
  final label = group.id.startsWith('turn-diff-group-')
      ? '本回合改动'
      : '${group.items.length} 个文件';
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

InlineSpan _fileEditLineStatsSpan(
  BuildContext context,
  AgentTimelineFileEditItem item,
) {
  final colors = IdeColors.of(context);
  final textStyles = IdeTextStyles.of(context);
  final added = item.addedLines ?? 0;
  final removed = item.removedLines ?? 0;
  return TextSpan(
    style: textStyles.bodySmall.copyWith(
      color: colors.textSecondary.withValues(alpha: 0.66),
      height: 1.45,
    ),
    children: <InlineSpan>[
      TextSpan(
        text: '+$added',
        style: TextStyle(
          color: colors.success.withValues(alpha: 0.98),
          fontWeight: FontWeight.w600,
        ),
      ),
      const TextSpan(text: ' / '),
      TextSpan(
        text: '-$removed',
        style: TextStyle(
          color: colors.error.withValues(alpha: 0.98),
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

String _toolKindLabel(AgentToolKind kind) {
  return switch (kind) {
    AgentToolKind.read => '读取',
    AgentToolKind.edit => '编辑',
    AgentToolKind.delete => '删除',
    AgentToolKind.move => '移动',
    AgentToolKind.search => '搜索',
    AgentToolKind.execute => '执行',
    AgentToolKind.think => '思考',
    AgentToolKind.fetch => '获取',
    AgentToolKind.other => '操作',
  };
}

bool _shouldPreviewCodeBlock(String code, {required int maxLines}) {
  return _codeBlockLineCount(code) > maxLines;
}

String _previewCodeBlock(String code, {required int maxLines}) {
  final lines = LineSplitter.split(code).toList(growable: false);
  if (lines.length <= maxLines) {
    return code;
  }
  return lines.take(maxLines).join('\n');
}

int _codeBlockLineCount(String code) {
  return LineSplitter.split(code).length;
}

/// 根据工具类型选择图标。
IconData _toolIcon(AgentToolKind kind) {
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

IconData _historyEventIcon(AgentHistoryEventKind kind) {
  return switch (kind) {
    AgentHistoryEventKind.permission => Icons.verified_user_outlined,
    AgentHistoryEventKind.warning => Icons.warning_amber_rounded,
    AgentHistoryEventKind.search => Icons.search_rounded,
    AgentHistoryEventKind.system => Icons.info_outline_rounded,
  };
}

Color _historyEventAccent(AgentHistoryEventKind kind, IdeColors colors) {
  return switch (kind) {
    AgentHistoryEventKind.permission ||
    AgentHistoryEventKind.warning => colors.warning,
    AgentHistoryEventKind.search || AgentHistoryEventKind.system => colors.info,
  };
}

IdeStatusCardTone _historyEventTone(AgentHistoryEventKind kind) {
  return switch (kind) {
    AgentHistoryEventKind.permission => IdeStatusCardTone.warning,
    AgentHistoryEventKind.warning => IdeStatusCardTone.error,
    AgentHistoryEventKind.search => IdeStatusCardTone.info,
    AgentHistoryEventKind.system => IdeStatusCardTone.info,
  };
}

MarkdownThemeData _agentMarkdownTheme(BuildContext context) {
  final colors = IdeColors.of(context);
  final textStyles = IdeTextStyles.of(context);
  final base = textStyles.bodyMedium.copyWith(
    color: colors.textPrimary,
    height: 1.42,
  );
  final codeStyle = _agentCodeTextStyle(context, baseStyle: base);

  return MarkdownThemeData.fallback(
    context,
    maxContentWidth: _agentContentMaxWidth,
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

TextStyle _agentCodeTextStyle(BuildContext context, {TextStyle? baseStyle}) {
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

BoxDecoration _agentCodeBlockDecoration(IdeColors colors) {
  return BoxDecoration(
    color: colors.surfaceElevated,
    borderRadius: IdeRadius.allSmall,
    border: Border.all(color: colors.borderSubtle),
  );
}

Map<String, TextStyle> _agentHighlightTheme(BuildContext context) {
  final colors = IdeColors.of(context);
  final base = _agentCodeTextStyle(context);
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

String? _formatDuration(Duration? duration) {
  if (duration == null) {
    return null;
  }
  final totalSeconds = duration.inSeconds;
  if (totalSeconds <= 0) {
    return null;
  }
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  if (minutes > 0) {
    return '${minutes}m ${seconds}s';
  }
  return '${seconds}s';
}

String? _threadOpenStatusText(AgentConversationViewModel viewModel) {
  return switch (viewModel.threadOpenPhase) {
    AgentThreadOpenPhase.loadingHistory => 'Loading thread history...',
    AgentThreadOpenPhase.openFailed =>
      'Thread open failed. Click this thread again to retry.',
    // 打开成功时，头栏可展示模型改道等非阻塞系统提示。
    AgentThreadOpenPhase.idle => viewModel.systemNoticeLabel,
  };
}

/// token 用量短标签；有上下文窗口时展示占用比例。
String? _tokenUsageLabel(AgentTokenUsage? usage) {
  final total = usage?.totalTokens;
  if (total == null || total <= 0) {
    return null;
  }
  final window = usage?.modelContextWindow;
  if (window != null && window > 0) {
    final percent = ((total / window) * 100).clamp(0, 999).round();
    return '${_compactTokenCount(total)} / ${_compactTokenCount(window)} · $percent%';
  }
  return '${_compactTokenCount(total)} tokens';
}

/// 当前上下文窗口 token 用量短标签；缺少窗口大小时不展示。
String? _contextWindowTokenUsageLabel(AgentTokenUsage? usage) {
  final total = usage?.totalTokens;
  final window = usage?.modelContextWindow;
  if (total == null || total <= 0 || window == null || window <= 0) {
    return null;
  }
  return '${_compactTokenCount(total)} tokens';
}

double? _contextWindowTokenUsageProgressValue(AgentTokenUsage? usage) {
  final total = usage?.totalTokens;
  final window = usage?.modelContextWindow;
  if (total == null || total <= 0 || window == null || window <= 0) {
    return null;
  }
  return (total / window).clamp(0.0, 1.0);
}

/// 当前上下文窗口 token 用量的悬停明细。
String _contextWindowTokenUsageTooltip(AgentTokenUsage? usage) {
  final total = usage?.totalTokens;
  final window = usage?.modelContextWindow;
  if (total == null || total <= 0 || window == null || window <= 0) {
    return '';
  }
  final percent = ((total / window) * 100).round();
  final parts = <String>[
    'Usage: $percent%',
    'Used: ${_formatTokenCount(total)}',
    'Total: ${_formatTokenCount(window)}',
  ];
  if (usage?.inputTokens != null) {
    parts.add('input_tokens: ${_formatTokenCount(usage!.inputTokens!)}');
  }
  if (usage?.outputTokens != null) {
    parts.add('output_tokens: ${_formatTokenCount(usage!.outputTokens!)}');
  }
  if (usage?.cachedInputTokens != null) {
    parts.add(
      'cached_input_tokens: ${_formatTokenCount(usage!.cachedInputTokens!)}',
    );
  }
  return parts.join('\n');
}

/// 悬停时展示的 token 明细，含输入/缓存/输出/推理分项。
String _tokenUsageTooltip(AgentTokenUsage? usage) {
  if (usage == null) {
    return '';
  }
  final parts = <String>[];
  if (usage.totalTokens != null) {
    parts.add('Total: ${_formatTokenCount(usage.totalTokens!)}');
  }
  if (usage.modelContextWindow != null) {
    parts.add(
      'Context window: ${_formatTokenCount(usage.modelContextWindow!)}',
    );
  }
  if (usage.inputTokens != null) {
    parts.add('Input: ${_formatTokenCount(usage.inputTokens!)}');
  }
  if (usage.cachedInputTokens != null) {
    parts.add('Cached: ${_formatTokenCount(usage.cachedInputTokens!)}');
  }
  if (usage.outputTokens != null) {
    parts.add('Output: ${_formatTokenCount(usage.outputTokens!)}');
  }
  return parts.isEmpty ? '' : parts.join('\n');
}

/// 紧凑形式的 token 数，例如 1234 -> "1.2k"、1234567 -> "1.2M"。
String _compactTokenCount(int tokens) {
  if (tokens >= 1000000) {
    final millions = tokens / 1000000;
    return '${millions.toStringAsFixed(millions >= 10 ? 0 : 1)}M';
  }
  if (tokens >= 1000) {
    final thousands = tokens / 1000;
    return '${thousands.toStringAsFixed(thousands >= 100 ? 0 : 1)}k';
  }
  return tokens.toString();
}

/// 完整数字形式的 token 数，带千位分隔。
String _formatTokenCount(int tokens) {
  final str = tokens.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < str.length; i += 1) {
    if (i > 0 && (str.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(str[i]);
  }
  return buffer.toString();
}
