part of '../agent_pane.dart';

/// 单条用户、Agent 或系统消息。
class _AgentMessageEntry extends StatelessWidget {
  const _AgentMessageEntry({
    required this.message,
    required this.collapseHeavyContent,
    required this.useStreamingMarkdown,
    required this.viewModel,
  });

  final AgentConversationMessage message;
  final bool collapseHeavyContent;
  final bool useStreamingMarkdown;
  final AgentConversationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    if (message.isPlan) {
      return _AgentPlanMessageCard(message: message, viewModel: viewModel);
    }
    if (message.role == AgentMessageRole.agent) {
      return _AgentMarkdownMessage(
        message: message,
        collapseHeavyContent: collapseHeavyContent,
        useStreamingMarkdown: useStreamingMarkdown,
      );
    }
    return _AgentBubbleMessage(message: message);
  }
}

/// 回合之间的分隔线，附带可选的耗时/状态标签。
///
/// 用于在按 turn 聚合的时间线中区分不同回合，保持 IDE 风格的紧凑观感。
class _AgentTurnDivider extends StatelessWidget {
  const _AgentTurnDivider({required this.turn});

  final AgentConversationTurnGroup turn;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final label = _turnLabel(turn);
    final tokenLabel = _tokenUsageLabel(turn.tokenUsage);
    final tokenTooltip = _tokenUsageTooltip(turn.tokenUsage);
    final showTokens = tokenLabel != null;
    final hasMeta = label != null || showTokens;
    return Padding(
      padding: const EdgeInsets.only(
        top: IdeSpacing.space16,
        bottom: IdeSpacing.space10,
      ),
      child: Row(
        children: [
          Expanded(
            child: ShadSeparator.horizontal(
              margin: EdgeInsets.zero,
              thickness: 1,
              color: colors.borderSubtle,
            ),
          ),
          if (hasMeta) ...[
            const SizedBox(width: IdeSpacing.space10),
            Flexible(
              child: Align(
                alignment: Alignment.center,
                child: Wrap(
                  spacing: IdeSpacing.space8,
                  runSpacing: IdeSpacing.space4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (label != null)
                      Text(
                        label,
                        style: textStyles.caption.copyWith(
                          color: colors.textSecondary.withValues(alpha: 0.72),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    if (showTokens)
                      IdeTooltip(
                        message: tokenTooltip,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.bolt_outlined,
                                size: 12,
                                color: colors.textSecondary.withValues(
                                  alpha: 0.56,
                                ),
                              ),
                              const SizedBox(width: IdeSpacing.space4),
                              Text(
                                tokenLabel,
                                style: textStyles.caption.copyWith(
                                  color: colors.textSecondary.withValues(
                                    alpha: 0.72,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: IdeSpacing.space10),
          ],
          if (hasMeta)
            Expanded(
              child: ShadSeparator.horizontal(
                margin: EdgeInsets.zero,
                thickness: 1,
                color: colors.borderSubtle,
              ),
            ),
        ],
      ),
    );
  }

  String? _turnLabel(AgentConversationTurnGroup group) {
    final durationText = _formatDuration(group.duration);
    return switch (group.status) {
      AgentHistoryTurnStatus.running => 'Running',
      // 中断/失败终态优先展示状态词，有耗时再附加。
      AgentHistoryTurnStatus.interrupted =>
        durationText == null ? 'Interrupted' : 'Interrupted · $durationText',
      AgentHistoryTurnStatus.failed =>
        durationText == null ? 'Failed' : 'Failed · $durationText',
      AgentHistoryTurnStatus.completed => durationText ?? 'Completed',
      AgentHistoryTurnStatus.unknown || null => durationText,
    };
  }
}

/// 用户或系统消息仍然使用紧凑气泡。
class _AgentBubbleMessage extends StatelessWidget {
  const _AgentBubbleMessage({required this.message});

  final AgentConversationMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final isUser = message.role == AgentMessageRole.user;

    return Padding(
      padding: const EdgeInsets.only(bottom: IdeSpacing.space12),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isUser ? colors.primaryMuted : colors.surfaceElevated,
              borderRadius: IdeRadius.allMedium,
              border: Border.all(
                color: isUser
                    ? colors.accent.withValues(alpha: 0.22)
                    : colors.borderSubtle,
              ),
            ),
            child: Padding(
              padding: IdeSpacing.inputContentPadding,
              child: SelectableText(
                message.text,
                style: textStyles.bodyMedium.copyWith(
                  height: 1.4,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 普通 Agent 正文使用全宽 Markdown 渲染。
///
/// 超长 markdown 默认先展示预览，避免历史区滚动时提前创建整段重组件。
class _AgentMarkdownMessage extends StatefulWidget {
  const _AgentMarkdownMessage({
    required this.message,
    required this.collapseHeavyContent,
    required this.useStreamingMarkdown,
  });

  final AgentConversationMessage message;
  final bool collapseHeavyContent;
  final bool useStreamingMarkdown;

  @override
  State<_AgentMarkdownMessage> createState() => _AgentMarkdownMessageState();
}

class _AgentMarkdownMessageState extends State<_AgentMarkdownMessage> {
  bool _expanded = false;
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
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final markdown = widget.message.text;
    final useStreamingMarkdown = widget.useStreamingMarkdown;
    if (!widget.collapseHeavyContent || !_shouldCollapseMarkdown(markdown)) {
      return RepaintBoundary(
        child: useStreamingMarkdown
            ? _AgentMarkdownBody(controller: _ensureMarkdownController())
            : _AgentMarkdownBody(data: markdown),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: IdeSpacing.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: IdeMotion.durationNormal,
            curve: IdeMotion.curvePopup,
            alignment: Alignment.topCenter,
            child: _expanded
                ? RepaintBoundary(
                    key: ValueKey<String>(
                      'agent-markdown-body-${widget.message.id}',
                    ),
                    child: _AgentMarkdownBody(data: markdown),
                  )
                : Text(
                    _markdownPreviewText(markdown),
                    key: ValueKey<String>(
                      'agent-markdown-preview-${widget.message.id}',
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: textStyles.bodyMedium.copyWith(
                      height: 1.45,
                      color: colors.textSecondary.withValues(alpha: 0.88),
                    ),
                  ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: ShadButton.ghost(
              key: ValueKey<String>(
                'agent-markdown-toggle-${widget.message.id}',
              ),
              onPressed: () {
                setState(() {
                  _expanded = !_expanded;
                });
              },
              size: ShadButtonSize.sm,
              leading: Icon(
                _expanded
                    ? Icons.unfold_less_rounded
                    : Icons.unfold_more_rounded,
                size: 15,
              ),
              textStyle: textStyles.bodySmall,
              child: Text(_expanded ? '收起正文' : '展开正文'),
            ),
          ),
        ],
      ),
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
              borderRadius: IdeRadius.allComposer,
              hoverBackgroundColor: colors.border.withValues(alpha: 0.08),
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
