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
            color: colors.textTertiary,
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
      _commandGroupItemTitle(item),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _agentItemTextStyle(context),
    );
  }
}

/// 展开命令组后同时显示事件类型和具体标题，避免 Grok 事件退化成重复的「操作」。
String _commandGroupItemTitle(AgentTimelineCommandGroupItem item) {
  final kindLabel = _toolKindLabel(item.kind);
  final title = item.title.trim();
  if (title.isEmpty || title == kindLabel || title.startsWith('$kindLabel ·')) {
    return title.isEmpty ? kindLabel : title;
  }
  return '$kindLabel · $title';
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
        color: colors.textTertiary,
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
                sf.GhostButton(
                  key: ValueKey<String>(
                    'agent-file-edit-item-expand-all-${widget.item.id}',
                  ),
                  onPressed: () {
                    setState(() {
                      _showAll = !_showAll;
                    });
                  },
                  size: sf.ButtonSize.small,
                  child: Text(
                    _showAll ? '收起差异' : '展开全部',
                    style: textStyles.bodySmall,
                  ),
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
    final textStyles = IdeTextStyles.of(context);
    final needsElapsedTick =
        toolCall.duration == null &&
        toolCall.startedAt != null &&
        toolCall.isActiveStatus;
    final listenables = <Listenable>[viewModel.expansionVersionListenable];
    if (needsElapsedTick) {
      listenables.add(viewModel.elapsedClockListenable);
    }
    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (context, _) {
        final canExpand =
            toolCall.content != null && toolCall.content!.isNotEmpty;
        final expanded = viewModel.isToolCallExpanded(toolCall.id);
        final elapsedLabel = _toolElapsedLabel(
          viewModel,
          toolCall,
          viewModel.elapsedNow,
        );
        return IdeCollapsibleCard(
          headerKey: ValueKey<String>('agent-tool-header-${toolCall.id}'),
          bodyKey: ValueKey<String>('agent-tool-body-${toolCall.id}'),
          expanded: expanded,
          canExpand: canExpand,
          onToggle: canExpand
              ? () => viewModel.toggleToolCall(toolCall.id)
              : () {},
          titleWidget: Row(
            children: [
              Expanded(
                child: Text(
                  _toolCardTitle(toolCall),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _agentItemTextStyle(context),
                ),
              ),
              if (elapsedLabel != null) ...[
                const SizedBox(width: IdeSpacing.space8),
                Text(
                  elapsedLabel,
                  key: ValueKey<String>('agent-tool-elapsed-${toolCall.id}'),
                  style: textStyles.caption.copyWith(
                    color: colors.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
          leading: toolCall.isActiveStatus
              ? const IdeBusySpinner(
                  size: 12,
                  strokeWidth: 1.8,
                  semanticsLabel: 'Tool running',
                )
              : Icon(
                  _toolIcon(toolCall.kind),
                  size: 14,
                  color: colors.textTertiary,
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

/// 思考/命令卡标题：进行中时用更明确的相位文案。
String _toolCardTitle(AgentToolCall toolCall) {
  // displayTitle 会把 call-... 合成成「类型 · 路径/命令」。
  final resolved = toolCall.displayTitle.trim();
  if (!toolCall.isActiveStatus) {
    return resolved;
  }
  if (toolCall.kind == AgentToolKind.think) {
    return '思考中';
  }
  if (resolved.isEmpty) {
    return '执行中';
  }
  // 已是「执行中」前缀则不再重复。
  if (resolved.startsWith('执行中') || resolved.startsWith('思考中')) {
    return resolved;
  }
  return '执行中 · $resolved';
}

/// 审批卡片。
///
/// 用户点击后 ViewModel 会把 approve/deny 回写给 provider。
/// 支持独立计划审批的 provider 所使用的审批卡片。
class _AgentPlanApprovalCard extends StatelessWidget {
  const _AgentPlanApprovalCard({
    required this.request,
    required this.onRespond,
  });

  final AgentPlanApprovalRequest request;
  final ValueChanged<AgentPlanApprovalDecisionKind> onRespond;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return IdeStatusCard(
      tone: IdeStatusCardTone.warning,
      title: request.title,
      leading: Icon(
        Icons.account_tree_outlined,
        size: 16,
        color: colors.warning,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (request.overview case final overview?
              when overview.trim().isNotEmpty) ...[
            Text(
              overview,
              style: textStyles.bodyMedium.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: IdeSpacing.space8),
          ],
          if (request.markdown.trim().isNotEmpty)
            _AgentMarkdownBody(data: request.markdown),
          if (request.todos.isNotEmpty) ...[
            const SizedBox(height: IdeSpacing.space8),
            _AgentPlanTodoList(title: 'Todos', todos: request.todos),
          ],
          for (final phase in request.phases) ...[
            const SizedBox(height: IdeSpacing.space8),
            _AgentPlanTodoList(title: phase.name, todos: phase.todos),
          ],
        ],
      ),
      footer: Wrap(
        alignment: WrapAlignment.end,
        spacing: IdeSpacing.space8,
        runSpacing: IdeSpacing.space6,
        children: [
          sf.GhostButton(
            key: ValueKey<String>('agent-plan-cancel-${request.id}'),
            onPressed: () => onRespond(AgentPlanApprovalDecisionKind.cancelled),
            size: sf.ButtonSize.small,
            child: const Text('Cancel turn'),
          ),
          sf.OutlineButton(
            key: ValueKey<String>('agent-plan-reject-${request.id}'),
            onPressed: () => onRespond(AgentPlanApprovalDecisionKind.rejected),
            size: sf.ButtonSize.small,
            child: const Text('Reject'),
          ),
          sf.PrimaryButton(
            key: ValueKey<String>('agent-plan-accept-${request.id}'),
            onPressed: () => onRespond(AgentPlanApprovalDecisionKind.accepted),
            size: sf.ButtonSize.small,
            leading: const Icon(Icons.check_rounded, size: 16),
            child: const Text('Accept plan'),
          ),
        ],
      ),
    );
  }
}

class _AgentPlanTodoList extends StatelessWidget {
  const _AgentPlanTodoList({required this.title, required this.todos});

  final String title;
  final List<AgentPlanEntry> todos;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textStyles.bodySmall.copyWith(
            color: colors.textTertiary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: IdeSpacing.space4),
        for (final todo in todos)
          Padding(
            padding: const EdgeInsets.only(bottom: IdeSpacing.space2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _planTodoIcon(todo.status),
                  size: 14,
                  color: todo.status == 'completed'
                      ? colors.success
                      : colors.textTertiary,
                ),
                const SizedBox(width: IdeSpacing.space6),
                Expanded(
                  child: Text(
                    todo.content,
                    style: textStyles.bodySmall.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

IconData _planTodoIcon(String? status) {
  return switch (status) {
    'completed' => Icons.check_circle_outline_rounded,
    'in_progress' => Icons.radio_button_checked_rounded,
    'cancelled' => Icons.cancel_outlined,
    _ => Icons.radio_button_unchecked_rounded,
  };
}

class _AgentPermissionCard extends StatefulWidget {
  const _AgentPermissionCard({
    required this.request,
    required this.onRespond,
    this.autoReview,
    this.onApproveGuardian,
  });

  final AgentPermissionRequest request;
  final void Function({
    required bool approved,
    bool cancelTurn,
    Map<String, List<String>> answers,
    AgentCommandApprovalDecisionKind? commandDecision,
    List<String> execpolicyAmendment,
  })
  onRespond;
  final AgentAutoApprovalReviewEvent? autoReview;
  final VoidCallback? onApproveGuardian;

  @override
  State<_AgentPermissionCard> createState() => _AgentPermissionCardState();
}

class _AgentPermissionCardState extends State<_AgentPermissionCard> {
  /// questionId → 已选答案（选项标签或自由文本）。
  late final Map<String, List<String>> _answers = <String, List<String>>{};
  late final Map<String, TextEditingController> _otherControllers =
      <String, TextEditingController>{};

  AgentPermissionRequest get request => widget.request;

  @override
  void initState() {
    super.initState();
    for (final question in request.questions) {
      if (question.isOther || question.resolvedOptions.isEmpty) {
        _otherControllers[question.questionId] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _otherControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (request.kind == AgentPermissionKind.userInput &&
        request.questions.isNotEmpty) {
      return _buildUserInputForm(context);
    }
    return _buildApprovalCard(context);
  }

  Widget _buildApprovalCard(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final hasAmendment = request.proposedExecpolicyAmendment.isNotEmpty;
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
          if (widget.autoReview != null)
            Padding(
              padding: const EdgeInsets.only(bottom: IdeSpacing.space6),
              child: Text(
                _autoReviewLabel(widget.autoReview!),
                style: textStyles.bodySmall.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          if (request.command != null)
            Text(
              request.command!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: _agentCodeTextStyle(
                context,
              ).copyWith(color: colors.textSecondary.withValues(alpha: 0.78)),
            ),
          if (request.commandActions.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                top: request.command == null ? 0 : IdeSpacing.space6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final action in request.commandActions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: IdeSpacing.space2),
                      child: Text(
                        action,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textStyles.bodySmall.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (request.description != null)
            Padding(
              padding: EdgeInsets.only(
                top: request.command == null && request.commandActions.isEmpty
                    ? 0
                    : IdeSpacing.space6,
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
          sf.GhostButton(
            key: ValueKey('agent-permission-cancel-${request.id}'),
            onPressed: () =>
                widget.onRespond(approved: false, cancelTurn: true),
            size: sf.ButtonSize.small,
            child: const Text('Cancel turn'),
          ),
          sf.OutlineButton(
            key: ValueKey('agent-permission-deny-${request.id}'),
            onPressed: () => widget.onRespond(
              approved: false,
              commandDecision:
                  request.kind == AgentPermissionKind.commandExecution
                  ? AgentCommandApprovalDecisionKind.decline
                  : null,
            ),
            size: sf.ButtonSize.small,
            leading: const Icon(Icons.close_rounded, size: 16),
            child: const Text('Deny'),
          ),
          if (request.kind == AgentPermissionKind.commandExecution) ...[
            sf.OutlineButton(
              key: ValueKey('agent-permission-session-${request.id}'),
              onPressed: () => widget.onRespond(
                approved: true,
                commandDecision:
                    AgentCommandApprovalDecisionKind.acceptForSession,
              ),
              size: sf.ButtonSize.small,
              child: const Text('Allow for session'),
            ),
            if (hasAmendment)
              sf.OutlineButton(
                key: ValueKey('agent-permission-always-${request.id}'),
                onPressed: () => widget.onRespond(
                  approved: true,
                  commandDecision: AgentCommandApprovalDecisionKind
                      .acceptWithExecpolicyAmendment,
                  execpolicyAmendment: request.proposedExecpolicyAmendment,
                ),
                size: sf.ButtonSize.small,
                child: const Text('Always allow'),
              ),
          ],
          if (widget.autoReview?.status == 'denied' &&
              widget.onApproveGuardian != null)
            sf.OutlineButton(
              key: ValueKey('agent-permission-guardian-override-${request.id}'),
              onPressed: widget.onApproveGuardian,
              size: sf.ButtonSize.small,
              child: const Text('Override guardian'),
            ),
          sf.PrimaryButton(
            key: ValueKey('agent-permission-approve-${request.id}'),
            onPressed: () => widget.onRespond(
              approved: true,
              commandDecision:
                  request.kind == AgentPermissionKind.commandExecution
                  ? AgentCommandApprovalDecisionKind.accept
                  : null,
            ),
            size: sf.ButtonSize.small,
            leading: const Icon(Icons.check_rounded, size: 16),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }

  Widget _buildUserInputForm(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return IdeStatusCard(
      tone: IdeStatusCardTone.warning,
      title: request.title,
      leading: Icon(
        Icons.help_outline_rounded,
        size: 16,
        color: colors.warning,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (request.description != null &&
              request.description!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: IdeSpacing.space8),
              child: Text(
                request.description!,
                style: textStyles.bodyMedium.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          for (var index = 0; index < request.questions.length; index++) ...[
            if (index > 0) const SizedBox(height: IdeSpacing.space10),
            _buildQuestion(context, request.questions[index]),
          ],
        ],
      ),
      footer: Wrap(
        alignment: WrapAlignment.end,
        spacing: IdeSpacing.space8,
        runSpacing: IdeSpacing.space6,
        children: [
          sf.GhostButton(
            key: ValueKey('agent-permission-cancel-${request.id}'),
            onPressed: () =>
                widget.onRespond(approved: false, cancelTurn: true),
            size: sf.ButtonSize.small,
            child: const Text('Cancel turn'),
          ),
          sf.OutlineButton(
            key: ValueKey('agent-permission-deny-${request.id}'),
            onPressed: () => widget.onRespond(approved: false),
            size: sf.ButtonSize.small,
            leading: const Icon(Icons.close_rounded, size: 16),
            child: const Text('Skip'),
          ),
          sf.PrimaryButton(
            key: ValueKey('agent-permission-approve-${request.id}'),
            onPressed: _submitUserInput,
            size: sf.ButtonSize.small,
            leading: const Icon(Icons.check_rounded, size: 16),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestion(BuildContext context, AgentUserInputQaPair question) {
    final textStyles = IdeTextStyles.of(context);
    final colors = IdeColors.of(context);
    final selected = _answers[question.questionId] ?? const <String>[];
    final otherController = _otherControllers[question.questionId];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (question.header != null && question.header!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: IdeSpacing.space2),
            child: Text(
              question.header!,
              style: textStyles.bodySmall.copyWith(
                color: colors.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Text(question.question, style: _agentItemTextStyle(context)),
        if (question.resolvedOptions.isNotEmpty) ...[
          const SizedBox(height: IdeSpacing.space6),
          Wrap(
            spacing: IdeSpacing.space6,
            runSpacing: IdeSpacing.space4,
            children: [
              for (final option in question.resolvedOptions)
                IdeTab(
                  key: ValueKey(
                    'agent-user-input-${request.id}-${question.questionId}-${option.id}',
                  ),
                  label: option.label,
                  selected: selected.contains(option.id),
                  trailingIcon: null,
                  onPressed: () => _toggleOption(question, option.id),
                ),
            ],
          ),
        ],
        if (otherController != null) ...[
          const SizedBox(height: IdeSpacing.space6),
          sf.TextField(
            key: ValueKey(
              'agent-user-input-other-${request.id}-${question.questionId}',
            ),
            controller: otherController,
            placeholder: Text(
              question.isOther ? 'Other…' : 'Your answer',
              style: textStyles.bodySmall.copyWith(color: colors.textTertiary),
            ),
            obscureText: question.isSecret,
            onChanged: (value) => _setOtherAnswer(question.questionId, value),
          ),
        ],
      ],
    );
  }

  void _toggleOption(AgentUserInputQaPair question, String optionId) {
    final questionId = question.questionId;
    setState(() {
      final current = List<String>.from(
        _answers[questionId] ?? const <String>[],
      );
      if (current.contains(optionId)) {
        current.remove(optionId);
      } else {
        if (!question.allowMultiple) {
          current.clear();
          _otherControllers[questionId]?.clear();
        }
        current.add(optionId);
      }
      if (current.isEmpty) {
        _answers.remove(questionId);
      } else {
        _answers[questionId] = current;
      }
    });
  }

  void _setOtherAnswer(String questionId, String value) {
    final trimmed = value.trim();
    setState(() {
      if (trimmed.isEmpty) {
        // 保留已选选项；仅清掉自由文本。
        final current = _answers[questionId];
        if (current != null) {
          final optionsOnly = current
              .where(
                (answer) => request.questions
                    .where((q) => q.questionId == questionId)
                    .expand((q) => q.options)
                    .contains(answer),
              )
              .toList();
          if (optionsOnly.isEmpty) {
            _answers.remove(questionId);
          } else {
            _answers[questionId] = optionsOnly;
          }
        }
        return;
      }
      _answers[questionId] = <String>[trimmed];
    });
  }

  void _submitUserInput() {
    final answers = <String, List<String>>{};
    for (final question in request.questions) {
      final selected = _answers[question.questionId];
      if (selected != null && selected.isNotEmpty) {
        answers[question.questionId] = List<String>.unmodifiable(selected);
        continue;
      }
      final other = _otherControllers[question.questionId]?.text.trim();
      if (other != null && other.isNotEmpty) {
        answers[question.questionId] = <String>[other];
      }
    }
    widget.onRespond(approved: true, answers: answers);
  }

  String _autoReviewLabel(AgentAutoApprovalReviewEvent review) {
    final status = switch (review.status) {
      'inProgress' => 'Auto-reviewing…',
      'approved' => 'Auto-review approved',
      'denied' => 'Auto-review denied',
      'timedOut' => 'Auto-review timed out',
      'aborted' => 'Auto-review aborted',
      _ => 'Auto-review: ${review.status}',
    };
    final rationale = review.rationale?.trim();
    if (rationale == null || rationale.isEmpty) {
      return status;
    }
    return '$status · $rationale';
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
      key: ValueKey<String>('agent-history-event-${event.id}'),
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
          child: Text(answerText, style: _agentMetaTextStyle(context)),
        ),
      ],
    );
  }
}
