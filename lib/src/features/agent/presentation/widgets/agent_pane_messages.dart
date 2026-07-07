part of '../agent_pane.dart';

/// 单条用户、Agent 或系统消息。
class _AgentMessageEntry extends StatelessWidget {
  const _AgentMessageEntry({
    required this.message,
    required this.collapseHeavyContent,
    required this.viewModel,
  });

  final AgentConversationMessage message;
  final bool collapseHeavyContent;
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
    final label = _turnLabel(turn);
    final tokenLabel = _tokenUsageLabel(turn.tokenUsage);
    final tokenTooltip = _tokenUsageTooltip(turn.tokenUsage);
    final showTokens = tokenLabel != null;
    final hasMeta = label != null || showTokens;
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Row(
        children: [
          const Expanded(
            child: Divider(height: 1, thickness: 1, color: ideBorderColor),
          ),
          if (hasMeta) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Align(
                alignment: Alignment.center,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (label != null)
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          color: ideMutedTextColor.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    if (showTokens)
                      Tooltip(
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
                                color: ideMutedTextColor.withValues(alpha: 0.5),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                tokenLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: ideMutedTextColor.withValues(
                                    alpha: 0.6,
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
            const SizedBox(width: 10),
          ],
          if (hasMeta)
            const Expanded(
              child: Divider(height: 1, thickness: 1, color: ideBorderColor),
            ),
        ],
      ),
    );
  }

  String? _turnLabel(AgentConversationTurnGroup group) {
    final duration = group.duration;
    final durationText = _formatDuration(duration);
    final status = group.status;
    if (durationText == null && status == null) {
      return null;
    }
    if (durationText != null && status == AgentHistoryTurnStatus.running) {
      return 'Running';
    }
    return durationText ??
        switch (status) {
          AgentHistoryTurnStatus.running => 'Running',
          AgentHistoryTurnStatus.completed => 'Completed',
          AgentHistoryTurnStatus.unknown => null,
          null => null,
        };
  }
}

/// 用户或系统消息仍然使用紧凑气泡。
class _AgentBubbleMessage extends StatelessWidget {
  const _AgentBubbleMessage({required this.message});

  final AgentConversationMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == AgentMessageRole.user;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isUser
                  ? ideAccentColor.withValues(alpha: 0.18)
                  : ideSurfaceColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isUser
                    ? ideAccentColor.withValues(alpha: 0.32)
                    : ideBorderColor,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      message.text,
                      style: const TextStyle(height: 1.35),
                    ),
                  ),
                ],
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
  });

  final AgentConversationMessage message;
  final bool collapseHeavyContent;

  @override
  State<_AgentMarkdownMessage> createState() => _AgentMarkdownMessageState();
}

class _AgentMarkdownMessageState extends State<_AgentMarkdownMessage> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final markdown = widget.message.text;
    if (!widget.collapseHeavyContent || !_shouldCollapseMarkdown(markdown)) {
      return RepaintBoundary(child: _AgentMarkdownBody(data: markdown));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
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
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: ideMutedTextColor.withValues(alpha: 0.86),
                    ),
                  ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: ValueKey<String>(
                'agent-markdown-toggle-${widget.message.id}',
              ),
              onPressed: () {
                setState(() {
                  _expanded = !_expanded;
                });
              },
              icon: Icon(
                _expanded
                    ? Icons.unfold_less_rounded
                    : Icons.unfold_more_rounded,
                size: 15,
              ),
              label: Text(_expanded ? '收起正文' : '展开正文'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentMarkdownBody extends StatelessWidget {
  const _AgentMarkdownBody({required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: data,
      fitContent: false,
      selectable: false,
      softLineBreak: true,
      styleSheet: _agentMarkdownStyleSheet(context),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ListenableBuilder(
        listenable: viewModel.expansionVersionListenable,
        builder: (context, _) {
          final expanded = viewModel.isPlanMessageExpanded(message.id);
          return RepaintBoundary(
            child: DecoratedBox(
              key: ValueKey<String>('agent-plan-card-${message.id}'),
              decoration: BoxDecoration(
                color: ideSurfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: ideBorderColor),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.checklist_rounded,
                          size: 16,
                          color: ideMutedTextColor.withValues(alpha: 0.75),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '计划',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: ideMutedTextColor.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                        IconButton(
                          key: ValueKey<String>(
                            'agent-plan-toggle-${message.id}',
                          ),
                          tooltip: expanded ? '收起计划' : '展开计划',
                          onPressed: () =>
                              viewModel.togglePlanMessage(message.id),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 28,
                            height: 28,
                          ),
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            expanded
                                ? Icons.close_fullscreen_rounded
                                : Icons.open_in_full_rounded,
                            size: 16,
                            color: ideMutedTextColor.withValues(alpha: 0.72),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: expanded
                          ? RepaintBoundary(
                              child: Padding(
                                key: ValueKey<String>(
                                  'agent-plan-body-${message.id}',
                                ),
                                padding: const EdgeInsets.only(right: 4),
                                child: _AgentMarkdownBody(data: message.text),
                              ),
                            )
                          : SizedBox(
                              key: ValueKey<String>(
                                'agent-plan-preview-${message.id}',
                              ),
                              height: 20,
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: Text(
                                  _planPreviewText(message.text),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.2,
                                    color: ideMutedTextColor.withValues(
                                      alpha: 0.72,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
