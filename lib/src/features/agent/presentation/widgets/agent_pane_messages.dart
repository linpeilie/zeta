part of '../agent_pane.dart';

/// 单条用户、Agent 或系统消息。
class _AgentMessageEntry extends StatelessWidget {
  const _AgentMessageEntry({
    required this.message,
    required this.useStreamingMarkdown,
    required this.viewModel,
  });

  final AgentConversationMessage message;
  final bool useStreamingMarkdown;
  final AgentConversationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    if (message.isPlan) {
      return _AgentPlanMessageCard(message: message, viewModel: viewModel);
    }
    // Codex phase=final_answer → 完成汇总卡片；无正文时不占位。
    if (message.isFinalAnswer) {
      if (message.text.trim().isEmpty) {
        return const SizedBox.shrink();
      }
      return _AgentFinalAnswerCard(
        message: message,
        useStreamingMarkdown: useStreamingMarkdown,
      );
    }
    if (message.role == AgentMessageRole.agent) {
      return _AgentMarkdownMessage(
        message: message,
        useStreamingMarkdown: useStreamingMarkdown,
      );
    }
    return _AgentBubbleMessage(message: message, viewModel: viewModel);
  }
}

/// 对话流内的进行中状态条。
///
/// 挂在 live turn 条目之后、footer 之前：展示主活动段 + 时长，
/// 思考数据本身不进入可见时间线，但仍通过此状态条反馈当前活动相位。
class _AgentLiveActivityStatus extends StatelessWidget {
  const _AgentLiveActivityStatus({required this.viewModel});

  final AgentConversationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        viewModel.elapsedClockListenable,
        viewModel.headerVersionListenable,
      ]),
      builder: (context, _) {
        if (!viewModel.isTurnRunning) {
          return const SizedBox.shrink();
        }
        final colors = IdeColors.of(context);
        final textStyles = IdeTextStyles.of(context);
        final waitingLabel = viewModel.threadStatusCapsuleLabel;
        final isWaiting = waitingLabel != null;
        final statusText = isWaiting
            ? waitingLabel
            : _headerRunningStatusText(viewModel, viewModel.elapsedNow);
        final accent = isWaiting ? colors.warning : colors.accent;
        return Padding(
          key: const ValueKey<String>('agent-live-activity-status'),
          padding: const EdgeInsets.only(
            bottom: IdeSpacing.space10,
            top: IdeSpacing.space2,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (isWaiting)
                Icon(
                  viewModel.threadWaitingOnApproval
                      ? Icons.verified_user_outlined
                      : viewModel.threadWaitingOnUserInput
                      ? Icons.edit_note_rounded
                      : Icons.error_outline_rounded,
                  size: 14,
                  color: accent,
                )
              else
                const IdeBusySpinner(
                  key: ValueKey<String>('agent-live-activity-spinner'),
                  size: 12,
                  strokeWidth: 1.8,
                  semanticsLabel: 'Turn running',
                ),
              const SizedBox(width: IdeSpacing.space8),
              Expanded(
                child: Text(
                  statusText,
                  key: const ValueKey<String>('agent-live-activity-label'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textStyles.bodySmall.copyWith(
                    color: isWaiting
                        ? colors.warning
                        : colors.textSecondary.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 单个 turn 末尾的分割线：展示本回合耗时、模型配置与 token 用量。
///
/// 仅终态（完成/中断/失败）展示；进行中耗时已在 live 活动条展示，避免重复。
/// 无任何可展示元数据时不渲染，避免空行干扰时间线。
class _AgentTurnFooter extends StatelessWidget {
  const _AgentTurnFooter({required this.turn});

  final AgentConversationTurnGroup turn;

  @override
  Widget build(BuildContext context) {
    // 进行中不展示底部「进行中 · 耗时」分隔线。
    if (turn.status == AgentHistoryTurnStatus.running) {
      return const SizedBox.shrink();
    }
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final metaStyle = textStyles.caption.copyWith(
      color: colors.textSecondary.withValues(alpha: 0.72),
      fontWeight: FontWeight.w500,
    );
    final durationLabel = _turnDurationLabel(turn);
    final modelConfig = turn.modelConfig;
    final modelLabel = _nonEmptyTrimmed(modelConfig?.modelId);
    final effortLabel = agentReasoningEffortFooterLabel(
      modelConfig?.reasoningEffort,
    );
    final showFast = modelConfig?.fastEnabled == true;
    final tokenLabel = _turnTokenUsageLabel(turn.tokenUsage);
    final tokenTooltip = _tokenUsageTooltip(turn.tokenUsage);
    final showTokens = tokenLabel != null;
    final hasMeta =
        durationLabel != null ||
        modelLabel != null ||
        effortLabel != null ||
        showFast ||
        showTokens;
    if (!hasMeta) {
      return const SizedBox.shrink();
    }
    return Padding(
      key: ValueKey<String>('agent-turn-footer-${turn.id}'),
      padding: const EdgeInsets.only(
        top: IdeSpacing.space12,
        bottom: IdeSpacing.space16,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final meta = Wrap(
            key: ValueKey<String>('agent-turn-footer-meta-${turn.id}'),
            alignment: WrapAlignment.center,
            runSpacing: IdeSpacing.space6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: _turnFooterMetaItems(
              turnId: turn.id,
              style: metaStyle,
              durationLabel: durationLabel,
              modelLabel: modelLabel,
              effortLabel: effortLabel,
              showFast: showFast,
              tokenLabel: showTokens ? tokenLabel : null,
              tokenTooltip: tokenTooltip,
            ),
          );
          final divider = sf.Divider(
            padding: EdgeInsets.zero,
            thickness: 1,
            color: colors.borderSubtle,
          );

          if (constraints.maxWidth < IdeMetrics.stackedRowBreakpoint) {
            return Column(
              key: ValueKey<String>('agent-turn-footer-stacked-${turn.id}'),
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: double.infinity, child: divider),
                const SizedBox(height: IdeSpacing.space8),
                meta,
              ],
            );
          }
          return Row(
            key: ValueKey<String>('agent-turn-footer-inline-${turn.id}'),
            children: [
              Expanded(child: divider),
              const SizedBox(width: IdeSpacing.space12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * 2 / 3,
                ),
                child: meta,
              ),
              const SizedBox(width: IdeSpacing.space12),
              Expanded(
                child: sf.Divider(
                  padding: EdgeInsets.zero,
                  thickness: 1,
                  color: colors.borderSubtle,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

String? _nonEmptyTrimmed(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

/// 组装 turn footer 元数据项，各项以带留白的 `•` 分隔，无 icon。
List<Widget> _turnFooterMetaItems({
  required String turnId,
  required TextStyle style,
  required String? durationLabel,
  required String? modelLabel,
  required String? effortLabel,
  required bool showFast,
  required String? tokenLabel,
  required String tokenTooltip,
}) {
  final items = <Widget>[];
  var separatorIndex = 0;
  void add(Widget child) {
    if (items.isEmpty) {
      items.add(child);
      return;
    }
    items.add(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            key: ValueKey<String>(
              'agent-turn-footer-separator-$turnId-${separatorIndex++}',
            ),
            padding: const EdgeInsets.symmetric(horizontal: IdeSpacing.space8),
            child: Text('•', style: style),
          ),
          Flexible(child: child),
        ],
      ),
    );
  }

  if (durationLabel != null) {
    add(Text(durationLabel, style: style));
  }
  if (modelLabel != null) {
    add(
      Text(
        modelLabel,
        key: ValueKey<String>('agent-turn-footer-model-$turnId'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
  if (effortLabel != null) {
    add(
      Text(
        effortLabel,
        key: ValueKey<String>('agent-turn-footer-effort-$turnId'),
        style: style,
      ),
    );
  }
  if (showFast) {
    add(
      Text(
        'Fast',
        key: ValueKey<String>('agent-turn-footer-fast-$turnId'),
        style: style,
      ),
    );
  }
  if (tokenLabel != null) {
    add(
      IdeTooltip(
        message: tokenTooltip,
        child: Text(tokenLabel, style: style),
      ),
    );
  }
  return items;
}

/// turn 末尾耗时/状态文案（仅终态 footer 使用；进行中不渲染 footer）。
String? _turnDurationLabel(AgentConversationTurnGroup group) {
  final durationText = _formatDuration(group.duration);
  return switch (group.status) {
    AgentHistoryTurnStatus.running => null,
    // 中断/失败终态优先展示状态词，有耗时再附加。
    AgentHistoryTurnStatus.interrupted =>
      durationText == null ? '已中断' : '已中断 · $durationText',
    AgentHistoryTurnStatus.failed =>
      durationText == null ? '失败' : '失败 · $durationText',
    AgentHistoryTurnStatus.completed => durationText ?? '已完成',
    AgentHistoryTurnStatus.unknown || null => durationText,
  };
}

/// 用户或系统消息仍然使用紧凑气泡。
class _AgentBubbleMessage extends StatelessWidget {
  const _AgentBubbleMessage({required this.message, required this.viewModel});

  final AgentConversationMessage message;
  final AgentConversationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final isUser = message.role == AgentMessageRole.user;
    final hasText = message.text.trim().isNotEmpty;
    final imagePaths = message.localImagePaths;
    final canEdit =
        isUser &&
        hasText &&
        viewModel.canEditLastUserMessage &&
        viewModel.lastEditableUserMessageId == message.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: IdeSpacing.space12),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: isUser
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                key: ValueKey<String>('agent-message-bubble-${message.id}'),
                decoration: BoxDecoration(
                  color: isUser
                      ? colors.userMessageSurface
                      : colors.controlSurface,
                  borderRadius: IdeRadius.allMedium,
                  border: Border.all(color: colors.borderSubtle),
                ),
                child: Padding(
                  padding: IdeSpacing.inputContentPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (imagePaths.isNotEmpty) ...[
                        Wrap(
                          spacing: IdeSpacing.space8,
                          runSpacing: IdeSpacing.space8,
                          children: [
                            for (final path in imagePaths)
                              ClipRRect(
                                borderRadius: IdeRadius.allSmall,
                                child: Image.file(
                                  File(path),
                                  key: ValueKey<String>(
                                    'agent-message-image-${message.id}-$path',
                                  ),
                                  width: 120,
                                  height: 120,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: colors.surfaceElevated,
                                      borderRadius: IdeRadius.allSmall,
                                    ),
                                    child: SizedBox(
                                      width: 120,
                                      height: 120,
                                      child: Center(
                                        child: Icon(
                                          Icons.broken_image_outlined,
                                          size: 20,
                                          color: colors.textTertiary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (hasText) const SizedBox(height: IdeSpacing.space8),
                      ],
                      if (hasText)
                        SelectableText(
                          message.text,
                          style:
                              (isUser
                                      ? textStyles.bodyMedium
                                      : textStyles.proseBody)
                                  .copyWith(
                                    height: 1.4,
                                    color: colors.textPrimary,
                                  ),
                        ),
                    ],
                  ),
                ),
              ),
              if (canEdit) ...[
                const SizedBox(height: IdeSpacing.space4),
                sf.GhostButton(
                  key: ValueKey<String>('agent-edit-retry-${message.id}'),
                  size: sf.ButtonSize.small,
                  onPressed: () {
                    unawaited(_showEditRetryDialog(context));
                  },
                  child: Text('从此处创建分支', style: textStyles.bodySmall),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEditRetryDialog(BuildContext context) async {
    final controller = TextEditingController(text: message.text);
    final confirmed = await showIdeDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return IdeDialog(
          title: const Text('创建分支并重试'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '将保留原会话，并从上一回合结束处创建新分支。'
                  '工作区文件不会回滚，之前由 Agent 写入的改动仍然存在。',
                ),
                const SizedBox(height: IdeSpacing.space12),
                sf.TextField(
                  controller: controller,
                  autofocus: true,
                  placeholder: const Text('编辑消息…'),
                ),
              ],
            ),
          ),
          actions: [
            IdeDialogAction.cancel(
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            IdeDialogAction.confirm(
              label: '创建分支并发送',
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );
    final text = controller.text;
    controller.dispose();
    if (confirmed == true && text.trim().isNotEmpty) {
      await viewModel.editLastUserMessageAndRetry(text);
    }
  }
}

/// 普通 Agent 正文使用全宽 Markdown 渲染（全文，不折叠）。
class _AgentMarkdownMessage extends StatefulWidget {
  const _AgentMarkdownMessage({
    required this.message,
    required this.useStreamingMarkdown,
  });

  final AgentConversationMessage message;
  final bool useStreamingMarkdown;

  @override
  State<_AgentMarkdownMessage> createState() => _AgentMarkdownMessageState();
}

class _AgentMarkdownMessageState extends State<_AgentMarkdownMessage> {
  MarkdownController? _markdownController;
  bool _streamCommitted = false;

  @override
  void initState() {
    super.initState();
    _syncMarkdownController();
  }

  @override
  void didUpdateWidget(covariant _AgentMarkdownMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.useStreamingMarkdown != widget.useStreamingMarkdown) {
      _disposeMarkdownController();
    }
    _syncMarkdownController();
  }

  @override
  void dispose() {
    _disposeMarkdownController();
    super.dispose();
  }

  MarkdownController _ensureMarkdownController() {
    return _markdownController ??= MarkdownController();
  }

  void _syncMarkdownController() {
    if (!widget.useStreamingMarkdown) {
      _disposeMarkdownController();
      return;
    }
    final controller = _ensureMarkdownController();
    final nextText = widget.message.text;
    final currentText = controller.data;
    if (nextText != currentText) {
      if (nextText.startsWith(currentText)) {
        controller.appendChunk(nextText.substring(currentText.length));
      } else {
        controller.setData(nextText);
      }
      _streamCommitted = false;
    }

    final isCompleted = widget.message.status == AgentMessageStatus.completed;
    if (isCompleted && !_streamCommitted) {
      controller.commitStream();
      _streamCommitted = true;
    } else if (!isCompleted) {
      _streamCommitted = false;
    }
  }

  void _disposeMarkdownController() {
    _markdownController?.dispose();
    _markdownController = null;
    _streamCommitted = false;
  }

  @override
  Widget build(BuildContext context) {
    final markdown = widget.message.text;
    final useStreamingMarkdown = widget.useStreamingMarkdown;
    return RepaintBoundary(
      child: useStreamingMarkdown
          ? _AgentMarkdownBody(controller: _ensureMarkdownController())
          : _AgentMarkdownBody(data: markdown),
    );
  }
}

class _AgentMarkdownBody extends StatelessWidget {
  const _AgentMarkdownBody({this.data, this.controller})
    : assert((data == null) != (controller == null));

  final String? data;
  final MarkdownController? controller;

  @override
  Widget build(BuildContext context) {
    return MarkdownWidget(
      data: data,
      controller: controller,
      theme: _agentMarkdownTheme(context),
      useColumn: true,
      selectable: true,
      padding: EdgeInsets.zero,
      enableCopyFullDocumentShortcut: false,
      showCopyAllInContextMenu: false,
    );
  }
}

/// Agent 完成汇总卡片：对应 Codex `agent_message` + `phase=final_answer`。
///
/// 以固定卡片壳展示全文 Markdown（不做历史折叠），流式回合内仍可增量渲染。
class _AgentFinalAnswerCard extends StatefulWidget {
  const _AgentFinalAnswerCard({
    required this.message,
    required this.useStreamingMarkdown,
  });

  final AgentConversationMessage message;
  final bool useStreamingMarkdown;

  @override
  State<_AgentFinalAnswerCard> createState() => _AgentFinalAnswerCardState();
}

class _AgentFinalAnswerCardState extends State<_AgentFinalAnswerCard> {
  MarkdownController? _markdownController;
  bool _streamCommitted = false;

  @override
  void initState() {
    super.initState();
    _syncMarkdownController();
  }

  @override
  void didUpdateWidget(covariant _AgentFinalAnswerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.useStreamingMarkdown != widget.useStreamingMarkdown) {
      _disposeMarkdownController();
    }
    _syncMarkdownController();
  }

  @override
  void dispose() {
    _disposeMarkdownController();
    super.dispose();
  }

  MarkdownController _ensureMarkdownController() {
    return _markdownController ??= MarkdownController();
  }

  void _syncMarkdownController() {
    if (!widget.useStreamingMarkdown) {
      _disposeMarkdownController();
      return;
    }
    final controller = _ensureMarkdownController();
    final nextText = widget.message.text;
    final currentText = controller.data;
    if (nextText != currentText) {
      if (nextText.startsWith(currentText)) {
        controller.appendChunk(nextText.substring(currentText.length));
      } else {
        controller.setData(nextText);
      }
      _streamCommitted = false;
    }

    final isCompleted = widget.message.status == AgentMessageStatus.completed;
    if (isCompleted && !_streamCommitted) {
      controller.commitStream();
      _streamCommitted = true;
    } else if (!isCompleted) {
      _streamCommitted = false;
    }
  }

  void _disposeMarkdownController() {
    _markdownController?.dispose();
    _markdownController = null;
    _streamCommitted = false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final markdown = widget.message.text;
    final useStreamingMarkdown = widget.useStreamingMarkdown;
    return RepaintBoundary(
      child: PanelCard(
        key: ValueKey<String>('agent-final-answer-card-${widget.message.id}'),
        color: colors.surfaceElevated,
        borderColor: colors.border,
        borderRadius: IdeRadius.allMedium,
        child: Padding(
          padding: IdeSpacing.sectionPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 16,
                    color: colors.success.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: IdeSpacing.space8),
                  Text(
                    '完成汇总',
                    style: textStyles.titleLarge.copyWith(
                      color: colors.textSecondary.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: IdeSpacing.space10),
              useStreamingMarkdown
                  ? _AgentMarkdownBody(controller: _ensureMarkdownController())
                  : _AgentMarkdownBody(data: markdown),
            ],
          ),
        ),
      ),
    );
  }
}

/// plan 消息使用独立卡片渲染，默认只显示一行预览。
class _AgentPlanMessageCard extends StatelessWidget {
  const _AgentPlanMessageCard({required this.message, required this.viewModel});

  final AgentConversationMessage message;
  final AgentConversationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: IdeSpacing.space12),
      child: ListenableBuilder(
        listenable: viewModel.expansionVersionListenable,
        builder: (context, _) {
          final expanded = viewModel.isPlanMessageExpanded(message.id);
          return RepaintBoundary(
            child: IdeCollapsibleCard(
              headerKey: ValueKey<String>('agent-plan-card-${message.id}'),
              toggleKey: ValueKey<String>('agent-plan-toggle-${message.id}'),
              bodyKey: ValueKey<String>('agent-plan-body-${message.id}'),
              expanded: expanded,
              onToggle: () => viewModel.togglePlanMessage(message.id),
              leading: Icon(
                Icons.checklist_rounded,
                size: 16,
                color: colors.textSecondary.withValues(alpha: 0.78),
              ),
              titleWidget: Text(
                '计划',
                style: textStyles.titleLarge.copyWith(
                  color: colors.textSecondary.withValues(alpha: 0.9),
                ),
              ),
              summaryWidget: expanded
                  ? null
                  : SizedBox(
                      key: ValueKey<String>('agent-plan-preview-${message.id}'),
                      height: 20,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          _planPreviewText(message.text),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textStyles.bodyMedium.copyWith(
                            height: 1.2,
                            color: colors.textSecondary.withValues(alpha: 0.76),
                          ),
                        ),
                      ),
                    ),
              padding: IdeSpacing.sectionPadding,
              summaryPadding: const EdgeInsets.only(top: IdeSpacing.space10),
              bodyPadding: const EdgeInsets.only(top: IdeSpacing.space10),
              backgroundColor: colors.surfaceElevated,
              borderColor: colors.border,
              borderRadius: IdeRadius.allMedium,
              hoverBackgroundColor: colors.hoverSurface,
              semanticLabel: expanded ? '收起计划' : '展开计划',
              body: Padding(
                padding: const EdgeInsets.only(right: IdeSpacing.space4),
                child: _AgentMarkdownBody(data: message.text),
              ),
            ),
          );
        },
      ),
    );
  }
}
