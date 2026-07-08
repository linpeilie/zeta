part of '../agent_pane.dart';

/// 命令集折叠卡片。
///
/// 连续工具调用和搜索事件会先规约成命令集，在这里统一展示摘要与展开列表。
class _AgentCommandGroupCard extends StatelessWidget {
  const _AgentCommandGroupCard({required this.group, required this.viewModel});

  final AgentTimelineCommandGroup group;
  final AgentConversationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final hoverBackground = ShadTheme.of(
      context,
    ).colorScheme.border.withValues(alpha: 0.12);
    return ListenableBuilder(
      listenable: viewModel.expansionVersionListenable,
      builder: (context, _) {
        final expanded = viewModel.isCommandGroupExpanded(group.id);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: PaneInteractiveSurface(
            key: ValueKey<String>('agent-command-group-header-${group.id}'),
            onPressed: () => viewModel.toggleCommandGroup(group.id),
            hoverBackgroundColor: hoverBackground,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.segment_rounded,
                      size: 14,
                      color: colors.accent.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _commandGroupSummary(group),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colors.mutedText.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.chevron_right_rounded,
                      size: 16,
                      color: colors.mutedText.withValues(alpha: 0.55),
                    ),
                  ],
                ),
                if (expanded)
                  RepaintBoundary(
                    child: Padding(
                      key: ValueKey<String>(
                        'agent-command-group-body-${group.id}',
                      ),
                      padding: const EdgeInsets.only(top: 8, left: 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (
                            var index = 0;
                            index < group.items.length;
                            index++
                          ) ...[
                            if (index > 0) const SizedBox(height: 8),
                            _AgentCommandGroupItemRow(item: group.items[index]),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AgentCommandGroupItemRow extends StatelessWidget {
  const _AgentCommandGroupItemRow({required this.item});

  final AgentTimelineCommandGroupItem item;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return Text(
      key: ValueKey<String>('agent-command-group-item-${item.id}'),
      item.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: colors.mutedText.withValues(alpha: 0.88),
        height: 1.35,
      ),
    );
  }
}

/// 文件编辑组折叠卡片。
///
/// 连续编辑操作会按文件拆分后显示在该组中，每个文件项支持独立展开详情。
class _AgentFileEditGroupCard extends StatefulWidget {
  const _AgentFileEditGroupCard({required this.group, required this.viewModel});

  final AgentTimelineFileEditGroup group;
  final AgentConversationViewModel viewModel;

  @override
  State<_AgentFileEditGroupCard> createState() =>
      _AgentFileEditGroupCardState();
}

class _AgentFileEditGroupCardState extends State<_AgentFileEditGroupCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final hoverBackground = ShadTheme.of(
      context,
    ).colorScheme.border.withValues(alpha: 0.12);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          PaneInteractiveSurface(
            key: ValueKey<String>(
              'agent-file-edit-group-header-${widget.group.id}',
            ),
            onPressed: () {
              setState(() {
                _expanded = !_expanded;
              });
            },
            hoverBackgroundColor: hoverBackground,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.edit_note_rounded,
                  size: 14,
                  color: colors.accent.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text.rich(
                        key: ValueKey<String>(
                          'agent-file-edit-group-summary-${widget.group.id}',
                        ),
                        _fileEditGroupSummarySpan(widget.group, colors),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.mutedText.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.chevron_right_rounded,
                  size: 16,
                  color: colors.mutedText.withValues(alpha: 0.55),
                ),
              ],
            ),
          ),
          if (_expanded)
            RepaintBoundary(
              child: Padding(
                key: ValueKey<String>(
                  'agent-file-edit-group-body-${widget.group.id}',
                ),
                padding: const EdgeInsets.only(top: 8, left: 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (
                      var index = 0;
                      index < widget.group.items.length;
                      index++
                    ) ...[
                      if (index > 0) const SizedBox(height: 8),
                      _AgentFileEditItemRow(
                        key: ValueKey<String>(
                          'agent-file-edit-item-${widget.group.items[index].id}',
                        ),
                        item: widget.group.items[index],
                        viewModel: widget.viewModel,
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AgentFileEditItemRow extends StatelessWidget {
  const _AgentFileEditItemRow({
    super.key,
    required this.item,
    required this.viewModel,
  });

  final AgentTimelineFileEditItem item;
  final AgentConversationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final hoverBackground = ShadTheme.of(
      context,
    ).colorScheme.border.withValues(alpha: 0.12);
    return ListenableBuilder(
      listenable: viewModel.expansionVersionListenable,
      builder: (context, _) {
        final expanded = viewModel.isFileEditItemExpanded(item.id);
        final canExpand = item.hasDetails;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            PaneInteractiveSurface(
              key: ValueKey<String>('agent-file-edit-item-row-${item.id}'),
              onPressed: canExpand
                  ? () => viewModel.toggleFileEditItem(item.id)
                  : null,
              hoverBackgroundColor: hoverBackground,
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: colors.mutedText.withValues(alpha: 0.88),
                              height: 1.35,
                            ),
                          ),
                        ),
                        if (item.addedLines != null ||
                            item.removedLines != null) ...[
                          const SizedBox(width: 12),
                          Text.rich(
                            key: ValueKey<String>(
                              'agent-file-edit-item-line-stats-${item.id}',
                            ),
                            _fileEditLineStatsSpan(item, colors),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IdeTooltip(
                    message: canExpand ? '查看详情' : '无详情可查看',
                    child: SizedBox(
                      key: ValueKey<String>(
                        'agent-file-edit-item-toggle-${item.id}',
                      ),
                      width: 20,
                      height: 20,
                      child: Icon(
                        expanded
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.chevron_right_rounded,
                        size: 16,
                        color: canExpand
                            ? colors.mutedText.withValues(alpha: 0.55)
                            : colors.mutedText.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (expanded && item.details != null)
              Padding(
                key: ValueKey<String>(
                  'agent-file-edit-item-details-${item.id}',
                ),
                padding: const EdgeInsets.only(top: 6, right: 28),
                child: _AgentDiffDetails(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _AgentDiffDetails extends StatefulWidget {
  const _AgentDiffDetails({required this.item});

  final AgentTimelineFileEditItem item;

  @override
  State<_AgentDiffDetails> createState() => _AgentDiffDetailsState();
}

class _AgentDiffDetailsState extends State<_AgentDiffDetails> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final details = widget.item.details!;
    final shouldCollapse = _shouldPreviewCodeBlock(
      details,
      maxLines: _diffPreviewLineCount,
    );
    final code = !_showAll && shouldCollapse
        ? _previewCodeBlock(details, maxLines: _diffPreviewLineCount)
        : details;
    final hiddenLines = shouldCollapse
        ? _codeBlockLineCount(details) - _diffPreviewLineCount
        : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _AgentHighlightedCodeBlock(code: code, language: 'diff'),
        if (shouldCollapse)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _showAll ? '已显示完整差异' : '已省略 $hiddenLines 行',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.mutedText.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(width: 8),
                ShadButton.ghost(
                  key: ValueKey<String>(
                    'agent-file-edit-item-expand-all-${widget.item.id}',
                  ),
                  onPressed: () {
                    setState(() {
                      _showAll = !_showAll;
                    });
                  },
                  size: ShadButtonSize.sm,
                  textStyle: const TextStyle(fontSize: 11),
                  child: Text(_showAll ? '收起差异' : '展开全部'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AgentHighlightedCodeBlock extends StatelessWidget {
  const _AgentHighlightedCodeBlock({
    required this.code,
    required this.language,
  });

  final String code;
  final String language;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: _agentCodeBlockDecoration(colors),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: HighlightView(
            code,
            language: language,
            theme: _agentHighlightTheme(context),
            padding: const EdgeInsets.all(10),
            textStyle: _agentCodeTextStyle(context),
          ),
        ),
      ),
    );
  }
}

/// 工具调用卡片。
///
/// 命令输出、文件变更、计划等 provider 事件都会规约到这个组件展示。
class _AgentToolCallCard extends StatelessWidget {
  const _AgentToolCallCard({required this.toolCall, required this.viewModel});

  final AgentToolCall toolCall;
  final AgentConversationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final hoverBackground = ShadTheme.of(
      context,
    ).colorScheme.border.withValues(alpha: 0.12);
    return ListenableBuilder(
      listenable: viewModel.expansionVersionListenable,
      builder: (context, _) {
        final canExpand =
            toolCall.content != null && toolCall.content!.isNotEmpty;
        final expanded = viewModel.isToolCallExpanded(toolCall.id);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: PaneInteractiveSurface(
            key: ValueKey<String>('agent-tool-header-${toolCall.id}'),
            onPressed: canExpand
                ? () => viewModel.toggleToolCall(toolCall.id)
                : null,
            hoverBackgroundColor: hoverBackground,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _toolIcon(toolCall.kind),
                      size: 14,
                      color: colors.accent.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        toolCall.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colors.mutedText.withValues(alpha: 0.88),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.chevron_right_rounded,
                      size: 16,
                      color: canExpand
                          ? colors.mutedText.withValues(alpha: 0.55)
                          : colors.mutedText.withValues(alpha: 0.25),
                    ),
                  ],
                ),
                if (expanded && toolCall.content != null)
                  RepaintBoundary(
                    child: Padding(
                      key: ValueKey<String>('agent-tool-body-${toolCall.id}'),
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        toolCall.content!,
                        style: TextStyle(
                          color: colors.mutedText.withValues(alpha: 0.6),
                          fontFamily: IdeTypography.of(context).codeFontFamily,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 审批卡片。
///
/// 用户点击后 ViewModel 会把 approve/deny 回写给 provider。
class _AgentPermissionCard extends StatelessWidget {
  const _AgentPermissionCard({
    required this.request,
    required this.onApprove,
    required this.onDeny,
  });

  final AgentPermissionRequest request;
  final VoidCallback onApprove;
  final VoidCallback onDeny;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.warning.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.warning.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 16,
                    color: colors.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      request.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              if (request.command != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    request.command!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    // 弱化命令显示：缩小字体并降低透明度
                    style: TextStyle(
                      color: colors.mutedText.withValues(alpha: 0.6),
                      fontFamily: IdeTypography.of(context).codeFontFamily,
                      fontSize: 11,
                    ),
                  ),
                ),
              if (request.description != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    request.description!,
                    style: TextStyle(color: colors.mutedText),
                  ),
                ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 6,
                children: [
                  ShadButton.outline(
                    key: ValueKey('agent-permission-deny-${request.id}'),
                    onPressed: onDeny,
                    size: ShadButtonSize.sm,
                    leading: const Icon(Icons.close_rounded, size: 16),
                    child: const Text('Deny'),
                  ),
                  ShadButton(
                    key: ValueKey('agent-permission-approve-${request.id}'),
                    onPressed: onApprove,
                    size: ShadButtonSize.sm,
                    leading: const Icon(Icons.check_rounded, size: 16),
                    child: const Text('Approve'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 只读历史事件卡片。
class _AgentHistoryEventCard extends StatelessWidget {
  const _AgentHistoryEventCard({required this.event});

  final AgentHistoryEventEntry event;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    // request_user_input 携带结构化问答对时，优先渲染问答样式：
    // 第一行问题，下一行回答。
    if (event.qaPairs != null && event.qaPairs!.isNotEmpty) {
      return _AgentUserInputQaList(qaPairs: event.qaPairs!);
    }

    final accent = _historyEventAccent(event.kind, colors);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withValues(alpha: 0.26)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(_historyEventIcon(event.kind), size: 16, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              if (event.description != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    event.description!,
                    style: TextStyle(color: colors.mutedText),
                  ),
                ),
              if (event.content != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    event.content!,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    // 弱化历史事件正文：缩小字体并降低透明度
                    style: TextStyle(
                      color: colors.mutedText.withValues(alpha: 0.6),
                      fontFamily: IdeTypography.of(context).codeFontFamily,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 用户输入问答列表。
///
/// 每个问题占两行：第一行是问题文本，下一行是用户选择的回答；
/// 回答未回填时展示占位符。整体弱化以突出 Agent 正文。
class _AgentUserInputQaList extends StatelessWidget {
  const _AgentUserInputQaList({required this.qaPairs});

  final List<AgentUserInputQaPair> qaPairs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < qaPairs.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _AgentUserInputQaRow(pair: qaPairs[i]),
          ],
        ],
      ),
    );
  }
}

class _AgentUserInputQaRow extends StatelessWidget {
  const _AgentUserInputQaRow({required this.pair});

  final AgentUserInputQaPair pair;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final answerText = pair.answers.isEmpty ? '—' : pair.answers.join('、');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 第一行：问题
        Text(
          pair.question,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: colors.mutedText.withValues(alpha: 0.88),
            height: 1.35,
          ),
        ),
        // 下一行：回答
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            answerText,
            style: TextStyle(
              fontSize: 11,
              color: colors.mutedText.withValues(alpha: 0.6),
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}
