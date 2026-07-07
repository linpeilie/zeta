part of '../agent_pane.dart';

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

InlineSpan _fileEditGroupSummarySpan(AgentTimelineFileEditGroup group) {
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
  if (addedLines == 0 && removedLines == 0) {
    return TextSpan(text: '${group.items.length} 个文件');
  }
  return TextSpan(
    children: <InlineSpan>[
      TextSpan(text: '${group.items.length} 个文件'),
      const TextSpan(text: ' · '),
      TextSpan(
        text: '+$addedLines',
        style: TextStyle(
          color: ideAccentColor.withValues(alpha: 0.98),
          fontWeight: FontWeight.w600,
        ),
      ),
      const TextSpan(text: ' / '),
      TextSpan(
        text: '-$removedLines',
        style: TextStyle(
          color: ideWarningColor.withValues(alpha: 0.98),
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

InlineSpan _fileEditLineStatsSpan(AgentTimelineFileEditItem item) {
  final added = item.addedLines ?? 0;
  final removed = item.removedLines ?? 0;
  return TextSpan(
    style: TextStyle(
      fontSize: 11,
      color: ideMutedTextColor.withValues(alpha: 0.6),
      height: 1.45,
    ),
    children: <InlineSpan>[
      TextSpan(
        text: '+$added',
        style: TextStyle(
          color: ideAccentColor.withValues(alpha: 0.98),
          fontWeight: FontWeight.w600,
        ),
      ),
      const TextSpan(text: ' / '),
      TextSpan(
        text: '-$removed',
        style: TextStyle(
          color: ideWarningColor.withValues(alpha: 0.98),
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

Color _historyEventAccent(AgentHistoryEventKind kind) {
  return switch (kind) {
    AgentHistoryEventKind.permission ||
    AgentHistoryEventKind.warning => ideWarningColor,
    AgentHistoryEventKind.search ||
    AgentHistoryEventKind.system => ideAccentColor,
  };
}

MarkdownStyleSheet _agentMarkdownStyleSheet(BuildContext context) {
  final textColor = Theme.of(context).colorScheme.onSurface;
  final base = DefaultTextStyle.of(
    context,
  ).style.copyWith(color: textColor, height: 1.42);
  final codeStyle = _agentCodeTextStyle(context, baseStyle: base);

  return MarkdownStyleSheet(
    p: base,
    pPadding: const EdgeInsets.only(bottom: 8),
    a: base.copyWith(color: ideAccentColor, fontWeight: FontWeight.w600),
    code: codeStyle.copyWith(
      backgroundColor: ideMutedTextColor.withValues(alpha: 0.16),
    ),
    blockSpacing: 8,
    listIndent: 22,
    listBullet: base,
    listBulletPadding: const EdgeInsets.only(right: 8),
    strong: const TextStyle(fontWeight: FontWeight.w700),
    em: const TextStyle(fontStyle: FontStyle.italic),
    h1: base.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
    h2: base.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
    h3: base.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
    h4: base.copyWith(fontWeight: FontWeight.w700),
    h5: base.copyWith(fontWeight: FontWeight.w700),
    h6: base.copyWith(fontWeight: FontWeight.w700),
    blockquote: base.copyWith(color: ideMutedTextColor),
    blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    blockquoteDecoration: BoxDecoration(
      color: ideSurfaceColor,
      borderRadius: BorderRadius.circular(6),
      border: const Border(left: BorderSide(color: ideAccentColor, width: 3)),
    ),
    codeblockPadding: const EdgeInsets.all(10),
    codeblockDecoration: _agentCodeBlockDecoration(),
    tableHead: base.copyWith(fontWeight: FontWeight.w700),
    tableBody: base,
    tableBorder: TableBorder.all(color: ideBorderColor),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    horizontalRuleDecoration: const BoxDecoration(
      border: Border(top: BorderSide(color: ideBorderColor)),
    ),
  );
}

TextStyle _agentCodeTextStyle(BuildContext context, {TextStyle? baseStyle}) {
  final effectiveBase =
      baseStyle ??
      DefaultTextStyle.of(
        context,
      ).style.copyWith(color: Theme.of(context).colorScheme.onSurface);
  return effectiveBase.copyWith(
    color: Theme.of(context).colorScheme.onSurface,
    fontFamily: ideFontFamily,
    fontSize: 11,
    height: 1.35,
    backgroundColor: Colors.transparent,
  );
}

BoxDecoration _agentCodeBlockDecoration() {
  return BoxDecoration(
    color: ideSurfaceColor,
    borderRadius: BorderRadius.circular(6),
    border: Border.all(color: ideBorderColor),
  );
}

Map<String, TextStyle> _agentHighlightTheme(BuildContext context) {
  final base = _agentCodeTextStyle(context);
  return <String, TextStyle>{
    'root': base,
    'meta': base.copyWith(color: ideMutedTextColor.withValues(alpha: 0.9)),
    'comment': base.copyWith(color: ideMutedTextColor.withValues(alpha: 0.72)),
    'addition': base.copyWith(
      color: ideAccentColor.withValues(alpha: 0.98),
      backgroundColor: ideAccentColor.withValues(alpha: 0.12),
    ),
    'deletion': base.copyWith(
      color: ideWarningColor.withValues(alpha: 0.98),
      backgroundColor: ideWarningColor.withValues(alpha: 0.1),
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
    AgentThreadOpenPhase.idle => null,
  };
}

/// token 用量短标签，例如 "1.2k tokens"。
String? _tokenUsageLabel(AgentTokenUsage? usage) {
  final total = usage?.totalTokens;
  if (total == null || total <= 0) {
    return null;
  }
  return '${_compactTokenCount(total)} tokens';
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
  if (usage.inputTokens != null) {
    parts.add('Input: ${_formatTokenCount(usage.inputTokens!)}');
  }
  if (usage.cachedInputTokens != null) {
    parts.add('Cached: ${_formatTokenCount(usage.cachedInputTokens!)}');
  }
  if (usage.outputTokens != null) {
    parts.add('Output: ${_formatTokenCount(usage.outputTokens!)}');
  }
  if (usage.reasoningOutputTokens != null) {
    parts.add('Reasoning: ${_formatTokenCount(usage.reasoningOutputTokens!)}');
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
