import 'package:flutter/foundation.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../../domain/agent/agent_models.dart';
import '../../../core/app_theme.dart';
import 'agent_timeline_grouping.dart';
import '../view_models/agent_conversation_view_model.dart';

const double _agentContentMaxWidth = 920;
const int _markdownCollapseLineThreshold = 12;
const int _markdownCollapseLengthThreshold = 420;
const int _diffPreviewLineCount = 24;

typedef _TurnSectionBuilder =
    Widget Function(AgentConversationTurnGroup turn, bool showDivider);

/// 中间 Agent 面板。
///
/// 该组件只负责渲染和用户输入，所有 provider 调用与状态合并都交给
/// [AgentConversationViewModel]。
class AgentPane extends StatefulWidget {
  const AgentPane({required this.viewModel, super.key});

  final AgentConversationViewModel viewModel;

  @override
  State<AgentPane> createState() => _AgentPaneState();
}

class _AgentPaneState extends State<AgentPane> {
  static const double _autoScrollBottomThreshold = 48;

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _canSendNotifier = ValueNotifier<bool>(false);
  bool _stickToBottom = true;
  late int _lastAutoScrollTick;

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_handleInputChanged);
    _scrollController.addListener(_handleScrollChanged);
    _lastAutoScrollTick = widget.viewModel.autoScrollTick;
    widget.viewModel.autoScrollTickListenable.addListener(
      _handleAutoScrollTickChanged,
    );
  }

  @override
  void didUpdateWidget(covariant AgentPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel == widget.viewModel) {
      return;
    }
    oldWidget.viewModel.autoScrollTickListenable.removeListener(
      _handleAutoScrollTickChanged,
    );
    _stickToBottom = true;
    _lastAutoScrollTick = widget.viewModel.autoScrollTick;
    widget.viewModel.autoScrollTickListenable.addListener(
      _handleAutoScrollTickChanged,
    );
  }

  @override
  void dispose() {
    widget.viewModel.autoScrollTickListenable.removeListener(
      _handleAutoScrollTickChanged,
    );
    _inputController.removeListener(_handleInputChanged);
    _scrollController.removeListener(_handleScrollChanged);
    _inputController.dispose();
    _scrollController.dispose();
    _canSendNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ideFrameColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AgentContentAlign(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: ListenableBuilder(
                listenable: widget.viewModel.headerVersionListenable,
                builder: (context, _) {
                  return _AgentHeader(viewModel: widget.viewModel);
                },
              ),
            ),
          ),
          Expanded(
            // 对话、工具调用和审批卡片共用一个滚动流，模拟 Agent 面板的时间线。
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: _agentContentMaxWidth,
                ),
                child: SingleChildScrollView(
                  key: const ValueKey('agent-message-list'),
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  // turn 卡片高度差异很大；改用精确内容高度滚动，避免
                  // SliverList 在滚动过程中重估 maxScrollExtent 导致滚动条跳动。
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _AgentHistoryTurnsSection(
                        viewModel: widget.viewModel,
                        onLoadOlder: _loadOlderTurns,
                        buildTurnSection: _buildTurnSection,
                      ),
                      _AgentLiveTurnSection(
                        viewModel: widget.viewModel,
                        hasLeadingTurn: () => _hasHistoryOrStandbyTurns,
                        buildTurnSection: _buildTurnSection,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _AgentComposerSection(
            viewModel: widget.viewModel,
            inputController: _inputController,
            canSendListenable: _canSendNotifier,
            onSend: _sendMessage,
          ),
        ],
      ),
    );
  }

  bool get _hasHistoryOrStandbyTurns {
    final standby = widget.viewModel.standbyTurnState;
    return (standby?.entries.isNotEmpty ?? false) ||
        widget.viewModel.visibleHistoryTurnStates.isNotEmpty;
  }

  Widget _buildTurnSection(AgentConversationTurnGroup turn, bool showDivider) {
    return _AgentTurnSection(
      key: ValueKey<String>('turn-${turn.id}'),
      turn: turn,
      showDivider: showDivider,
      viewModel: widget.viewModel,
    );
  }

  void _handleInputChanged() {
    final canSend = _inputController.text.trim().isNotEmpty;
    if (canSend == _canSendNotifier.value) {
      return;
    }
    _canSendNotifier.value = canSend;
  }

  void _loadOlderTurns() {
    if (!widget.viewModel.hasOlderTurns) {
      return;
    }
    final controller = _scrollController;
    final hasClients = controller.hasClients;
    final oldPixels = hasClients ? controller.position.pixels : 0.0;
    final oldMaxScrollExtent = hasClients
        ? controller.position.maxScrollExtent
        : 0.0;
    final changed = widget.viewModel.loadOlderTurns();
    if (!changed || !hasClients) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!controller.hasClients) {
        return;
      }
      final delta = controller.position.maxScrollExtent - oldMaxScrollExtent;
      final targetOffset = (oldPixels + delta).clamp(
        0.0,
        controller.position.maxScrollExtent,
      );
      controller.jumpTo(targetOffset);
    });
  }

  void _sendMessage() {
    if (!_canSendNotifier.value || !widget.viewModel.canSubmitMessage) {
      return;
    }
    final text = _inputController.text;
    if (text.trim().isEmpty) {
      return;
    }
    _inputController.clear();
    widget.viewModel.sendMessage(text);
  }

  void _handleAutoScrollTickChanged() {
    final nextTick = widget.viewModel.autoScrollTick;
    if (nextTick == _lastAutoScrollTick) {
      return;
    }
    final shouldScrollToEnd = _shouldStickToBottom();
    _lastAutoScrollTick = nextTick;
    if (shouldScrollToEnd) {
      _scrollToEnd();
    }
  }

  void _handleScrollChanged() {
    _stickToBottom = _shouldStickToBottom();
  }

  bool _shouldStickToBottom() {
    if (!_scrollController.hasClients) {
      return _stickToBottom;
    }
    return _distanceToBottom() <= _autoScrollBottomThreshold;
  }

  double _distanceToBottom() {
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels;
  }

  void _scrollToEnd() {
    // 新消息/工具卡出现后自动滚到底部，但不阻塞当前 build。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }
}

class _AgentHistoryTurnsSection extends StatelessWidget {
  const _AgentHistoryTurnsSection({
    required this.viewModel,
    required this.onLoadOlder,
    required this.buildTurnSection,
  });

  final AgentConversationViewModel viewModel;
  final VoidCallback onLoadOlder;
  final _TurnSectionBuilder buildTurnSection;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel.historyVersionListenable,
      builder: (context, _) {
        final turns = <AgentConversationTurnGroup>[
          if (viewModel.standbyTurnState case final standby?
              when standby.entries.isNotEmpty)
            standby.snapshot(),
          ...viewModel.visibleHistoryTurns,
        ];
        final children = <Widget>[];
        if (viewModel.hasOlderTurns) {
          children.add(
            _AgentLoadOlderTurnsButton(onPressed: onLoadOlder, loading: false),
          );
        }
        var hasRenderedTurn = false;
        for (final turn in turns) {
          children.add(
            buildTurnSection(turn, hasRenderedTurn && !turn.isStandby),
          );
          hasRenderedTurn = true;
        }
        return Column(
          key: const ValueKey('agent-history-turns-section'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
      },
    );
  }
}

class _AgentLiveTurnSection extends StatelessWidget {
  const _AgentLiveTurnSection({
    required this.viewModel,
    required this.hasLeadingTurn,
    required this.buildTurnSection,
  });

  final AgentConversationViewModel viewModel;
  final bool Function() hasLeadingTurn;
  final _TurnSectionBuilder buildTurnSection;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        viewModel.historyVersionListenable,
        viewModel.liveTurnListenable,
      ]),
      builder: (context, _) {
        final turnState = viewModel.liveTurnState;
        if (turnState == null) {
          return const SizedBox.shrink();
        }
        return ListenableBuilder(
          listenable: turnState,
          builder: (context, _) {
            final turn = turnState.snapshot();
            return KeyedSubtree(
              key: const ValueKey('agent-live-turn-section'),
              child: buildTurnSection(
                turn,
                hasLeadingTurn() && !turn.isStandby,
              ),
            );
          },
        );
      },
    );
  }
}

class _AgentTurnSection extends StatelessWidget {
  const _AgentTurnSection({
    required this.turn,
    required this.showDivider,
    required this.viewModel,
    super.key,
  });

  final AgentConversationTurnGroup turn;
  final bool showDivider;
  final AgentConversationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final renderBlocks = buildAgentTimelineRenderBlocks(
      turnId: turn.id,
      entries: turn.entries,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (showDivider) _AgentTurnDivider(turn: turn),
        for (final block in renderBlocks)
          KeyedSubtree(
            key: ValueKey<String>('turn-block-${turn.id}-${block.id}'),
            child: _buildBlock(block),
          ),
      ],
    );
  }

  Widget _buildBlock(AgentTimelineRenderBlock block) {
    return switch (block) {
      AgentTimelineEntryRenderBlock(:final entry) => _buildTimelineEntry(entry),
      AgentTimelineCommandGroupRenderBlock(:final group) =>
        _AgentCommandGroupCard(group: group),
      AgentTimelineFileEditGroupRenderBlock(:final group) =>
        _AgentFileEditGroupCard(group: group),
    };
  }

  Widget _buildTimelineEntry(AgentTimelineEntry entry) {
    final collapseHeavyContent = viewModel.liveTurnState?.id != turn.id;
    return switch (entry) {
      AgentMessageTimelineEntry(:final message) => _AgentMessageEntry(
        message: message,
        collapseHeavyContent: collapseHeavyContent,
      ),
      AgentToolTimelineEntry(:final toolCall) => _AgentToolCallCard(
        toolCall: toolCall,
      ),
      AgentPermissionTimelineEntry(:final request) => _AgentPermissionCard(
        request: request,
        onApprove: () => viewModel.respondToPermission(request, approved: true),
        onDeny: () => viewModel.respondToPermission(request, approved: false),
      ),
      AgentHistoryEventTimelineEntry(:final event) => _AgentHistoryEventCard(
        event: event,
      ),
    };
  }
}

class _AgentComposerSection extends StatelessWidget {
  const _AgentComposerSection({
    required this.viewModel,
    required this.inputController,
    required this.canSendListenable,
    required this.onSend,
  });

  final AgentConversationViewModel viewModel;
  final TextEditingController inputController;
  final ValueListenable<bool> canSendListenable;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return _AgentContentAlign(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: ListenableBuilder(
          listenable: viewModel.composerVersionListenable,
          builder: (context, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: canSendListenable,
              builder: (context, canSend, _) {
                return _AgentComposer(
                  controller: inputController,
                  canSubmit: canSend && viewModel.canSubmitMessage,
                  isTurnRunning: viewModel.isTurnRunning,
                  threadOpenPhase: viewModel.threadOpenPhase,
                  onSend: onSend,
                  onCancel: viewModel.cancelActiveTurn,
                  models: viewModel.models,
                  selectedModel: viewModel.selectedModel,
                  selectedReasoningEffort: viewModel.selectedReasoningEffort,
                  selectedServiceTierId: viewModel.selectedServiceTierId,
                  showReasoningEffort: viewModel.showReasoningEffort,
                  showServiceTier: viewModel.showServiceTier,
                  onSelectModel: (modelId) => viewModel.selectModel(modelId),
                  onSelectReasoningEffort: (effort) =>
                      viewModel.selectReasoningEffort(effort),
                  onSelectServiceTier: (tierId) =>
                      viewModel.selectServiceTier(tierId),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _AgentContentAlign extends StatelessWidget {
  const _AgentContentAlign({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _agentContentMaxWidth),
        child: child,
      ),
    );
  }
}

class _AgentLoadOlderTurnsButton extends StatelessWidget {
  const _AgentLoadOlderTurnsButton({
    required this.onPressed,
    required this.loading,
  });

  final VoidCallback onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('agent-load-older-turns-button'),
          onPressed: loading ? null : onPressed,
          icon: loading
              ? const SizedBox.square(
                  dimension: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                )
              : const Icon(Icons.history_rounded, size: 15),
          label: Text(loading ? 'Loading older turns' : 'Load older turns'),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(fontSize: 11),
          ),
        ),
      ),
    );
  }
}

/// thread 详情头部：左侧标题 + 运行图标，右侧当前 thread 累计 token 用量。
class _AgentHeader extends StatelessWidget {
  const _AgentHeader({required this.viewModel});

  final AgentConversationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokenUsage = viewModel.currentThreadTokenUsage;
    final tokenLabel = _tokenUsageLabel(tokenUsage);
    final tokenTooltip = _tokenUsageTooltip(tokenUsage);
    final threadOpenStatusText = _threadOpenStatusText(viewModel);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      viewModel.currentThreadTitle,
                      key: const ValueKey('agent-header-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (viewModel.showRunningIndicator) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.autorenew_rounded,
                      key: const ValueKey('agent-header-running-icon'),
                      size: 15,
                      color: ideAccentColor,
                    ),
                  ],
                ],
              ),
              if (threadOpenStatusText != null) ...[
                const SizedBox(height: 3),
                Text(
                  threadOpenStatusText,
                  key: const ValueKey('agent-thread-open-status'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color:
                        viewModel.threadOpenPhase ==
                            AgentThreadOpenPhase.openFailed
                        ? ideWarningColor
                        : ideMutedTextColor.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (tokenLabel != null) ...[
          const SizedBox(width: 8),
          Tooltip(
            message: tokenTooltip,
            child: Row(
              key: const ValueKey('agent-header-token'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.bolt_outlined,
                  size: 12,
                  color: ideMutedTextColor.withValues(alpha: 0.65),
                ),
                const SizedBox(width: 3),
                Text(
                  tokenLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: ideMutedTextColor.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 底部输入面板。
///
/// 上半部分是多行输入框，下半部分是操作行：左侧放模型选择、思考按钮和速率按钮，
/// 右侧放发送/取消按钮。provider 运行时发送按钮切换为取消按钮。
class _AgentComposer extends StatelessWidget {
  const _AgentComposer({
    required this.controller,
    required this.canSubmit,
    required this.isTurnRunning,
    required this.threadOpenPhase,
    required this.onSend,
    required this.onCancel,
    required this.models,
    required this.selectedModel,
    required this.selectedReasoningEffort,
    required this.selectedServiceTierId,
    required this.showReasoningEffort,
    required this.showServiceTier,
    required this.onSelectModel,
    required this.onSelectReasoningEffort,
    required this.onSelectServiceTier,
  });

  final TextEditingController controller;
  final bool canSubmit;
  final bool isTurnRunning;
  final AgentThreadOpenPhase threadOpenPhase;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  /// 可选模型列表。
  final List<AgentModelInfo> models;

  /// 当前选中的模型信息。
  final AgentModelInfo? selectedModel;

  /// 当前选中的推理深度档位。
  final String? selectedReasoningEffort;

  /// 当前选中的服务档位 id。
  final String? selectedServiceTierId;

  /// 是否显示思考按钮。
  final bool showReasoningEffort;

  /// 是否显示速率按钮。
  final bool showServiceTier;

  final ValueChanged<String> onSelectModel;
  final ValueChanged<String?> onSelectReasoningEffort;
  final ValueChanged<String?> onSelectServiceTier;

  @override
  Widget build(BuildContext context) {
    final hasDraft = controller.text.trim().isNotEmpty;
    final showSend =
        threadOpenPhase == AgentThreadOpenPhase.idle &&
        (!isTurnRunning || hasDraft);
    final showCancel =
        threadOpenPhase == AgentThreadOpenPhase.idle &&
        isTurnRunning &&
        !hasDraft;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: idePanelColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ideBorderColor.withValues(alpha: 0.72)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 上半部分：多行输入框，默认 3 行，最高 10 行，去掉自带边框。
            TextField(
              key: const ValueKey('agent-message-input'),
              controller: controller,
              minLines: 3,
              maxLines: 10,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) {
                if (canSubmit) {
                  onSend();
                }
              },
              decoration: const InputDecoration(
                hintText: 'Message Agent',
                hintStyle: TextStyle(color: ideMutedTextColor),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 6),
            // 下半部分：操作行，左侧放选择控件，右侧放发送按钮。
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (models.isNotEmpty)
                  _ModelSelectorButton(
                    models: models,
                    selectedModel: selectedModel,
                    onSelect: onSelectModel,
                  ),
                if (showReasoningEffort && selectedModel != null) ...[
                  const SizedBox(width: 6),
                  _ReasoningEffortButton(
                    efforts: selectedModel!.supportedReasoningEfforts,
                    selectedEffort: selectedReasoningEffort,
                    onSelect: onSelectReasoningEffort,
                  ),
                ],
                if (showServiceTier && selectedModel != null) ...[
                  const SizedBox(width: 6),
                  _ServiceTierButton(
                    tiers: selectedModel!.serviceTiers,
                    selectedTierId: selectedServiceTierId,
                    onSelect: onSelectServiceTier,
                  ),
                ],
                const Spacer(),
                if (showCancel)
                  Tooltip(
                    message: 'Cancel',
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: ideBorderColor.withValues(alpha: 0.36),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        key: const ValueKey('agent-cancel-button'),
                        onPressed: onCancel,
                        icon: const Icon(Icons.stop_rounded, size: 18),
                      ),
                    ),
                  )
                else if (showSend)
                  Tooltip(
                    message: 'Send',
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: canSubmit
                            ? ideAccentColor.withValues(alpha: 0.18)
                            : ideBorderColor.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        key: const ValueKey('agent-send-button'),
                        onPressed: canSubmit ? onSend : null,
                        icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                      ),
                    ),
                  )
                else
                  const SizedBox(
                    key: ValueKey('agent-send-unavailable-placeholder'),
                    width: 40,
                    height: 40,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 选择控件通用的紧凑胶囊外观。
class _SelectorChip extends StatelessWidget {
  const _SelectorChip({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ideBorderColor.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ideBorderColor.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: ideMutedTextColor),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: ideMutedTextColor.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 12,
              color: ideMutedTextColor,
            ),
          ],
        ),
      ),
    );
  }
}

/// 模型选择按钮，点击弹出可用模型列表。
class _ModelSelectorButton extends StatelessWidget {
  const _ModelSelectorButton({
    required this.models,
    required this.selectedModel,
    required this.onSelect,
  });

  final List<AgentModelInfo> models;
  final AgentModelInfo? selectedModel;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: const ValueKey('agent-model-selector'),
      tooltip: 'Select model',
      onSelected: onSelect,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      itemBuilder: (context) => [
        for (final model in models)
          PopupMenuItem<String>(
            value: model.id,
            height: 32,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  child: model.id == selectedModel?.id
                      ? Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: ideAccentColor,
                        )
                      : const SizedBox(),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    model.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
      child: _SelectorChip(
        label: selectedModel?.displayName ?? 'Model',
        icon: Icons.auto_awesome_outlined,
      ),
    );
  }
}

/// 推理深度（思考）选择按钮，点击弹出 low/medium/high/xhigh 列表。
class _ReasoningEffortButton extends StatelessWidget {
  const _ReasoningEffortButton({
    required this.efforts,
    required this.selectedEffort,
    required this.onSelect,
  });

  final List<AgentModelReasoningEffort> efforts;
  final String? selectedEffort;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String?>(
      key: const ValueKey('agent-reasoning-effort-selector'),
      tooltip: 'Reasoning effort',
      onSelected: onSelect,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      itemBuilder: (context) => [
        for (final effort in efforts)
          PopupMenuItem<String?>(
            value: effort.effort,
            height: 32,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  child: effort.effort == selectedEffort
                      ? Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: ideAccentColor,
                        )
                      : const SizedBox(),
                ),
                const SizedBox(width: 6),
                Text(
                  effort.description ?? effort.effort,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
      ],
      child: _SelectorChip(
        label: selectedEffort ?? 'Think',
        icon: Icons.psychology_alt_outlined,
      ),
    );
  }
}

/// 服务档位（速率）选择按钮，点击弹出可用档位列表。
class _ServiceTierButton extends StatelessWidget {
  const _ServiceTierButton({
    required this.tiers,
    required this.selectedTierId,
    required this.onSelect,
  });

  final List<AgentModelServiceTier> tiers;
  final String? selectedTierId;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String?>(
      key: const ValueKey('agent-service-tier-selector'),
      tooltip: 'Service tier',
      onSelected: onSelect,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      itemBuilder: (context) => [
        for (final tier in tiers)
          PopupMenuItem<String?>(
            value: tier.id,
            height: 32,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  child: tier.id == selectedTierId
                      ? Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: ideAccentColor,
                        )
                      : const SizedBox(),
                ),
                const SizedBox(width: 6),
                Text(tier.name, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
      ],
      child: _SelectorChip(
        label: _selectedTierName() ?? 'Speed',
        icon: Icons.speed_rounded,
      ),
    );
  }

  String? _selectedTierName() {
    final id = selectedTierId;
    if (id == null) {
      return null;
    }
    for (final tier in tiers) {
      if (tier.id == id) {
        return tier.name;
      }
    }
    return null;
  }
}

/// 单条用户、Agent 或系统消息。
class _AgentMessageEntry extends StatelessWidget {
  const _AgentMessageEntry({
    required this.message,
    required this.collapseHeavyContent,
  });

  final AgentConversationMessage message;
  final bool collapseHeavyContent;

  @override
  Widget build(BuildContext context) {
    if (message.isPlan) {
      return _AgentPlanMessageCard(message: message);
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
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: RepaintBoundary(child: _AgentMarkdownBody(data: markdown)),
      );
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
class _AgentPlanMessageCard extends StatefulWidget {
  const _AgentPlanMessageCard({required this.message});

  final AgentConversationMessage message;

  @override
  State<_AgentPlanMessageCard> createState() => _AgentPlanMessageCardState();
}

class _AgentPlanMessageCardState extends State<_AgentPlanMessageCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: RepaintBoundary(
        child: DecoratedBox(
          key: ValueKey<String>('agent-plan-card-${widget.message.id}'),
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
                        'agent-plan-toggle-${widget.message.id}',
                      ),
                      tooltip: _expanded ? '收起计划' : '展开计划',
                      onPressed: () {
                        setState(() {
                          _expanded = !_expanded;
                        });
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        _expanded
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
                  child: _expanded
                      ? RepaintBoundary(
                          child: Padding(
                            key: ValueKey<String>(
                              'agent-plan-body-${widget.message.id}',
                            ),
                            padding: const EdgeInsets.only(right: 4),
                            child: _AgentMarkdownBody(
                              data: widget.message.text,
                            ),
                          ),
                        )
                      : SizedBox(
                          key: ValueKey<String>(
                            'agent-plan-preview-${widget.message.id}',
                          ),
                          height: 20,
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Text(
                              _planPreviewText(widget.message.text),
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
      ),
    );
  }
}

/// 命令集折叠卡片。
///
/// 连续工具调用和搜索事件会先规约成命令集，在这里统一展示摘要与展开列表。
class _AgentCommandGroupCard extends StatefulWidget {
  const _AgentCommandGroupCard({required this.group});

  final AgentTimelineCommandGroup group;

  @override
  State<_AgentCommandGroupCard> createState() => _AgentCommandGroupCardState();
}

class _AgentCommandGroupCardState extends State<_AgentCommandGroupCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        key: ValueKey<String>('agent-command-group-header-${widget.group.id}'),
        onTap: () {
          setState(() {
            _expanded = !_expanded;
          });
        },
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
                  color: ideAccentColor.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _commandGroupSummary(widget.group),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: ideMutedTextColor.withValues(alpha: 0.9),
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
                  color: ideMutedTextColor.withValues(alpha: 0.55),
                ),
              ],
            ),
            if (_expanded)
              RepaintBoundary(
                child: Padding(
                  key: ValueKey<String>(
                    'agent-command-group-body-${widget.group.id}',
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
                        _AgentCommandGroupItemRow(
                          item: widget.group.items[index],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
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
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: ideMutedTextColor.withValues(alpha: 0.88),
        height: 1.35,
      ),
    );
  }
}

/// 文件编辑组折叠卡片。
///
/// 连续编辑操作会按文件拆分后显示在该组中，每个文件项支持独立展开详情。
class _AgentFileEditGroupCard extends StatefulWidget {
  const _AgentFileEditGroupCard({required this.group});

  final AgentTimelineFileEditGroup group;

  @override
  State<_AgentFileEditGroupCard> createState() =>
      _AgentFileEditGroupCardState();
}

class _AgentFileEditGroupCardState extends State<_AgentFileEditGroupCard> {
  bool _expanded = false;
  final Set<String> _expandedItemIds = <String>{};

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: ValueKey<String>(
              'agent-file-edit-group-header-${widget.group.id}',
            ),
            onTap: () {
              setState(() {
                _expanded = !_expanded;
              });
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.edit_note_rounded,
                  size: 14,
                  color: ideAccentColor.withValues(alpha: 0.7),
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
                        _fileEditGroupSummarySpan(widget.group),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: ideMutedTextColor.withValues(alpha: 0.9),
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
                  color: ideMutedTextColor.withValues(alpha: 0.55),
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
                        expanded: _expandedItemIds.contains(
                          widget.group.items[index].id,
                        ),
                        onToggle: widget.group.items[index].hasDetails
                            ? () {
                                setState(() {
                                  final itemId = widget.group.items[index].id;
                                  if (!_expandedItemIds.add(itemId)) {
                                    _expandedItemIds.remove(itemId);
                                  }
                                });
                              }
                            : null,
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
    required this.expanded,
    this.onToggle,
  });

  final AgentTimelineFileEditItem item;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final canExpand = onToggle != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          key: ValueKey<String>('agent-file-edit-item-row-${item.id}'),
          onTap: onToggle,
          child: Padding(
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
                            color: ideMutedTextColor.withValues(alpha: 0.88),
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
                          _fileEditLineStatsSpan(item),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
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
                          ? ideMutedTextColor.withValues(alpha: 0.55)
                          : ideMutedTextColor.withValues(alpha: 0.25),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded && item.details != null)
          Padding(
            key: ValueKey<String>('agent-file-edit-item-details-${item.id}'),
            padding: const EdgeInsets.only(top: 6, right: 28),
            child: _AgentDiffDetails(item: item),
          ),
      ],
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
                    color: ideMutedTextColor.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  key: ValueKey<String>(
                    'agent-file-edit-item-expand-all-${widget.item.id}',
                  ),
                  onPressed: () {
                    setState(() {
                      _showAll = !_showAll;
                    });
                  },
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
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
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: _agentCodeBlockDecoration(),
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
class _AgentToolCallCard extends StatefulWidget {
  const _AgentToolCallCard({required this.toolCall});

  final AgentToolCall toolCall;

  @override
  State<_AgentToolCallCard> createState() => _AgentToolCallCardState();
}

class _AgentToolCallCardState extends State<_AgentToolCallCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final canExpand =
        widget.toolCall.content != null && widget.toolCall.content!.isNotEmpty;

    // 去掉卡片背景/边框，直接以文本行展示工具调用，保留可点击展开行为。
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        key: ValueKey<String>('agent-tool-header-${widget.toolCall.id}'),
        onTap: canExpand
            ? () {
                setState(() {
                  _expanded = !_expanded;
                });
              }
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _toolIcon(widget.toolCall.kind),
                  size: 14,
                  color: ideAccentColor.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.toolCall.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: ideMutedTextColor.withValues(alpha: 0.88),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.chevron_right_rounded,
                  size: 16,
                  color: canExpand
                      ? ideMutedTextColor.withValues(alpha: 0.55)
                      : ideMutedTextColor.withValues(alpha: 0.25),
                ),
              ],
            ),
            if (_expanded && widget.toolCall.content != null)
              RepaintBoundary(
                child: Padding(
                  key: ValueKey<String>(
                    'agent-tool-body-${widget.toolCall.id}',
                  ),
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    widget.toolCall.content!,
                    style: TextStyle(
                      color: ideMutedTextColor.withValues(alpha: 0.6),
                      fontFamily: 'Menlo',
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ideWarningColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ideWarningColor.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.verified_user_outlined,
                    size: 16,
                    color: ideWarningColor,
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
                      color: ideMutedTextColor.withValues(alpha: 0.6),
                      fontFamily: 'Menlo',
                      fontSize: 11,
                    ),
                  ),
                ),
              if (request.description != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    request.description!,
                    style: const TextStyle(color: ideMutedTextColor),
                  ),
                ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 6,
                children: [
                  TextButton.icon(
                    key: ValueKey('agent-permission-deny-${request.id}'),
                    onPressed: onDeny,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Deny'),
                  ),
                  FilledButton.icon(
                    key: ValueKey('agent-permission-approve-${request.id}'),
                    onPressed: onApprove,
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Approve'),
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
    // request_user_input 携带结构化问答对时，优先渲染问答样式：
    // 第一行问题，下一行回答。
    if (event.qaPairs != null && event.qaPairs!.isNotEmpty) {
      return _AgentUserInputQaList(qaPairs: event.qaPairs!);
    }

    final accent = _historyEventAccent(event.kind);

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
                    style: const TextStyle(color: ideMutedTextColor),
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
                      color: ideMutedTextColor.withValues(alpha: 0.6),
                      fontFamily: 'Menlo',
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
            color: ideMutedTextColor.withValues(alpha: 0.88),
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
              color: ideMutedTextColor.withValues(alpha: 0.6),
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
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
    fontFamily: 'Menlo',
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
