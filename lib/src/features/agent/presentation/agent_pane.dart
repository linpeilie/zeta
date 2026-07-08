import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/core/ide_chip.dart';
import 'package:zeta/src/ui/core/ide_collapsible_card.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_motion.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_status_card.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_grouping.dart';

part 'widgets/agent_pane_cards.dart';
part 'widgets/agent_pane_composer.dart';
part 'widgets/agent_pane_header.dart';
part 'widgets/agent_pane_messages.dart';
part 'widgets/agent_pane_sections.dart';
part 'widgets/agent_pane_styles.dart';

const double _agentContentMaxWidth = 920;
const int _markdownCollapseLineThreshold = 12;
const int _markdownCollapseLengthThreshold = 420;
const int _diffPreviewLineCount = 24;

typedef _TurnSectionBuilder =
    Widget Function(AgentConversationTurnGroup turn, bool showDivider);

/// 中间 Agent 面板。
///
/// 当前文件只保留页面壳、滚动协作与组合关系；实际 header、timeline、
/// composer 以及各类卡片都已拆到独立组件文件。
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
      color: IdeColors.of(context).frame,
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
