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
    return ListenableBuilder(
      listenable: viewModel.expansionVersionListenable,
      builder: (context, _) {
        final expanded = viewModel.isCommandGroupExpanded(group.id);
        return IdeCollapsibleCard(
          headerKey: ValueKey<String>('agent-command-group-header-${group.id}'),
          bodyKey: ValueKey<String>('agent-command-group-body-${group.id}'),
          expanded: expanded,
          onToggle: () => viewModel.toggleCommandGroup(group.id),
          title: _commandGroupSummary(group),
          leading: Icon(
            Icons.segment_rounded,
            size: 14,
            color: colors.accent.withValues(alpha: 0.7),
          ),
          margin: const EdgeInsets.only(bottom: IdeSpacing.space10),
          bodyPadding: const EdgeInsets.only(
            top: IdeSpacing.space8,
            left: IdeSpacing.space20,
          ),
          hoverBackgroundColor: _agentHoverBackground(context),
          semanticLabel: '命令组',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < group.items.length; index++) ...[
                if (index > 0) const SizedBox(height: IdeSpacing.space8),
                _AgentCommandGroupItemRow(item: group.items[index]),
              ],
            ],
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
    return Text(
      key: ValueKey<String>('agent-command-group-item-${item.id}'),
      item.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _agentItemTextStyle(context),
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
    return IdeCollapsibleCard(
      headerKey: ValueKey<String>(
        'agent-file-edit-group-header-${widget.group.id}',
      ),
      bodyKey: ValueKey<String>(
        'agent-file-edit-group-body-${widget.group.id}',
      ),
      expanded: _expanded,
      onToggle: () {
        setState(() {
          _expanded = !_expanded;
        });
      },
      leading: Icon(
        Icons.edit_note_rounded,
        size: 14,
        color: colors.accent.withValues(alpha: 0.7),
      ),
      titleWidget: Text.rich(
        key: ValueKey<String>(
          'agent-file-edit-group-summary-${widget.group.id}',
        ),
        _fileEditGroupSummarySpan(context, widget.group),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _agentSummaryTextStyle(context),
      ),
      margin: const EdgeInsets.only(bottom: IdeSpacing.space10),
      bodyPadding: const EdgeInsets.only(
        top: IdeSpacing.space8,
        left: IdeSpacing.space20,
      ),
      hoverBackgroundColor: _agentHoverBackground(context),
      semanticLabel: '文件编辑组',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < widget.group.items.length; index++) ...[
            if (index > 0) const SizedBox(height: IdeSpacing.space8),
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
    return ListenableBuilder(
      listenable: viewModel.expansionVersionListenable,
      builder: (context, _) {
        final expanded = viewModel.isFileEditItemExpanded(item.id);
        final canExpand = item.hasDetails;
        return IdeCollapsibleCard(
          headerKey: ValueKey<String>('agent-file-edit-item-row-${item.id}'),
          toggleKey: ValueKey<String>('agent-file-edit-item-toggle-${item.id}'),
          bodyKey: ValueKey<String>('agent-file-edit-item-details-${item.id}'),
          expanded: expanded,
          canExpand: canExpand,
          onToggle: canExpand
              ? () => viewModel.toggleFileEditItem(item.id)
              : () {},
          hoverBackgroundColor: _agentHoverBackground(context),
          padding: const EdgeInsets.symmetric(vertical: IdeSpacing.space2),
          bodyPadding: const EdgeInsets.only(
            top: IdeSpacing.space6,
            right: IdeSpacing.space20,
          ),
          semanticLabel: canExpand ? '查看文件编辑详情' : '文件编辑详情',
          titleWidget: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _agentItemTextStyle(context),
                ),
              ),
              if (item.addedLines != null || item.removedLines != null) ...[
                const SizedBox(width: IdeSpacing.space12),
                Text.rich(
                  key: ValueKey<String>(
                    'agent-file-edit-item-line-stats-${item.id}',
                  ),
                  _fileEditLineStatsSpan(context, item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
          body: item.details == null ? null : _AgentDiffDetails(item: item),
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
    final textStyles = IdeTextStyles.of(context);
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
            padding: const EdgeInsets.only(top: IdeSpacing.space6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _showAll ? '已显示完整差异' : '已省略 $hiddenLines 行',
                  style: _agentMetaTextStyle(context),
                ),
                const SizedBox(width: IdeSpacing.space8),
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
                  textStyle: textStyles.bodySmall,
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
          borderRadius: IdeRadius.allSmall,
          child: HighlightView(
            code,
            language: language,
            theme: _agentHighlightTheme(context),
            padding: IdeSpacing.cardPadding,
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
    return ListenableBuilder(
      listenable: viewModel.expansionVersionListenable,
      builder: (context, _) {
        final canExpand =
            toolCall.content != null && toolCall.content!.isNotEmpty;
        final expanded = viewModel.isToolCallExpanded(toolCall.id);
        return IdeCollapsibleCard(
          headerKey: ValueKey<String>('agent-tool-header-${toolCall.id}'),
          bodyKey: ValueKey<String>('agent-tool-body-${toolCall.id}'),
          expanded: expanded,
          canExpand: canExpand,
          onToggle: canExpand
              ? () => viewModel.toggleToolCall(toolCall.id)
              : () {},
          titleWidget: Text(
            toolCall.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _agentItemTextStyle(context),
          ),
          leading: Icon(
            _toolIcon(toolCall.kind),
            size: 14,
            color: colors.accent.withValues(alpha: 0.7),
          ),
          margin: const EdgeInsets.only(bottom: IdeSpacing.space10),
          bodyPadding: const EdgeInsets.only(top: IdeSpacing.space8),
          hoverBackgroundColor: _agentHoverBackground(context),
          semanticLabel: '工具调用',
          body: toolCall.content == null
              ? null
              : SelectableText(
                  toolCall.content!,
                  style: _agentCodeTextStyle(context).copyWith(
                    color: colors.textSecondary.withValues(alpha: 0.8),
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
    final textStyles = IdeTextStyles.of(context);
    return IdeStatusCard(
      tone: IdeStatusCardTone.warning,
      title: request.title,
      leading: Icon(
        Icons.verified_user_outlined,
        size: 16,
        color: colors.warning,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (request.command != null)
            Text(
              request.command!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: _agentCodeTextStyle(
                context,
              ).copyWith(color: colors.textSecondary.withValues(alpha: 0.78)),
            ),
          if (request.description != null)
            Padding(
              padding: EdgeInsets.only(
                top: request.command == null ? 0 : IdeSpacing.space6,
              ),
              child: Text(
                request.description!,
                style: textStyles.bodyMedium.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
        ],
      ),
      footer: Wrap(
        alignment: WrapAlignment.end,
        spacing: IdeSpacing.space8,
        runSpacing: IdeSpacing.space6,
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
    );
  }
}

/// 只读历史事件卡片。
class _AgentHistoryEventCard extends StatelessWidget {
  const _AgentHistoryEventCard({required this.event});

  final AgentHistoryEventEntry event;

  @override
  Widget build(BuildContext context) {
    if (event.qaPairs != null && event.qaPairs!.isNotEmpty) {
      return _AgentUserInputQaList(
        title: event.title,
        description: event.description,
        qaPairs: event.qaPairs!,
      );
    }

    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final accent = _historyEventAccent(event.kind, colors);

    return IdeStatusCard(
      tone: _historyEventTone(event.kind),
      title: event.title,
      leading: Icon(_historyEventIcon(event.kind), size: 16, color: accent),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (event.description != null)
            Text(
              event.description!,
              style: textStyles.bodyMedium.copyWith(
                color: colors.textSecondary,
              ),
            ),
          if (event.content != null)
            Padding(
              padding: EdgeInsets.only(
                top: event.description == null ? 0 : IdeSpacing.space8,
              ),
              child: Text(
                event.content!,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: _agentCodeTextStyle(
                  context,
                ).copyWith(color: colors.textSecondary.withValues(alpha: 0.78)),
              ),
            ),
        ],
      ),
    );
  }
}

/// 用户输入问答列表。
///
/// 每个问题占两行：第一行是问题文本，下一行是用户选择的回答；
/// 回答未回填时展示占位符。整体弱化以突出 Agent 正文。
class _AgentUserInputQaList extends StatelessWidget {
  const _AgentUserInputQaList({
    required this.title,
    required this.description,
    required this.qaPairs,
  });

  final String title;
  final String? description;
  final List<AgentUserInputQaPair> qaPairs;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return IdeStatusCard(
      tone: IdeStatusCardTone.info,
      title: title,
      leading: Icon(Icons.help_outline_rounded, size: 16, color: colors.info),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (description != null && description!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: IdeSpacing.space8),
              child: Text(
                description!,
                style: textStyles.bodyMedium.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          for (var index = 0; index < qaPairs.length; index++) ...[
            if (index > 0) const SizedBox(height: IdeSpacing.space10),
            _AgentUserInputQaRow(pair: qaPairs[index]),
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
    final answerText = pair.answers.isEmpty ? '—' : pair.answers.join('、');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(pair.question, style: _agentItemTextStyle(context)),
        Padding(
          padding: const EdgeInsets.only(top: IdeSpacing.space2),
          child: Text(
            answerText,
            style: _agentMetaTextStyle(context, alpha: 0.72),
          ),
        ),
      ],
    );
  }
}
