part of '../agent_pane.dart';

/// 对话时间线与 Composer 的统一布局壳。
///
/// Footer 始终是同一棵带稳定 Key 的子树；空会话时靠近 Canvas 视觉中心，
/// 首个 turn 出现后落到底部。时间线按 Footer 实际高度让位，避免覆盖审批 Dock。
class _AgentConversationLayout extends StatefulWidget {
  const _AgentConversationLayout({
    required this.hasConversation,
    required this.reduceMotion,
    required this.timeline,
    required this.footer,
  });

  final bool hasConversation;
  final bool reduceMotion;
  final Widget timeline;
  final Widget footer;

  @override
  State<_AgentConversationLayout> createState() =>
      _AgentConversationLayoutState();
}

class _AgentConversationLayoutState extends State<_AgentConversationLayout> {
  static const Alignment _newConversationAlignment = Alignment(0, -0.12);

  final GlobalKey _footerMeasureKey = GlobalKey(
    debugLabel: 'agent-conversation-footer-measure',
  );
  double _footerHeight = 0;
  bool _measurementScheduled = false;

  @override
  Widget build(BuildContext context) {
    _scheduleFooterMeasurement();
    final duration = widget.reduceMotion
        ? Duration.zero
        : IdeMotion.durationSlow;
    final targetAlignment = widget.hasConversation
        ? Alignment.bottomCenter
        : _newConversationAlignment;

    return Stack(
      key: const ValueKey('agent-conversation-layout'),
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          ignoring: !widget.hasConversation,
          child: AnimatedOpacity(
            key: const ValueKey('agent-conversation-timeline'),
            opacity: widget.hasConversation ? 1 : 0,
            duration: duration,
            curve: IdeMotion.curveDefault,
            child: AnimatedPadding(
              duration: duration,
              curve: IdeMotion.curveDefault,
              padding: EdgeInsets.only(
                bottom: widget.hasConversation ? _footerHeight : 0,
              ),
              child: widget.timeline,
            ),
          ),
        ),
        AnimatedAlign(
          key: const ValueKey('agent-composer-alignment'),
          alignment: targetAlignment,
          duration: duration,
          curve: IdeMotion.curveDefault,
          child: NotificationListener<SizeChangedLayoutNotification>(
            onNotification: (_) {
              _scheduleFooterMeasurement();
              return false;
            },
            child: SizeChangedLayoutNotifier(
              child: SizedBox(
                key: _footerMeasureKey,
                width: double.infinity,
                child: widget.footer,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _scheduleFooterMeasurement() {
    if (_measurementScheduled) {
      return;
    }
    _measurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (!mounted) {
        return;
      }
      final renderObject = _footerMeasureKey.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) {
        return;
      }
      final nextHeight = renderObject.size.height;
      if ((nextHeight - _footerHeight).abs() < 0.5) {
        return;
      }
      setState(() {
        _footerHeight = nextHeight;
      });
    });
  }
}

/// 共享 920px 内容轴的可滚动对话区。
class _AgentConversationTimeline extends StatelessWidget {
  const _AgentConversationTimeline({
    required this.viewModel,
    required this.scrollController,
    required this.pagePadding,
    required this.onLoadOlder,
    required this.buildTurnSection,
  });

  final AgentConversationViewModel viewModel;
  final ScrollController scrollController;
  final EdgeInsets pagePadding;
  final VoidCallback onLoadOlder;
  final _TurnSectionBuilder buildTurnSection;

  @override
  Widget build(BuildContext context) {
    return _AgentContentAlign(
      child: SingleChildScrollView(
        key: const ValueKey('agent-message-list'),
        controller: scrollController,
        padding: pagePadding,
        // turn 卡片高度差异很大；精确内容高度可避免滚动条反复重估。
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AgentHistoryTurnsSection(
              viewModel: viewModel,
              onLoadOlder: onLoadOlder,
              buildTurnSection: buildTurnSection,
            ),
            _AgentLiveTurnSection(
              viewModel: viewModel,
              buildTurnSection: buildTurnSection,
            ),
          ],
        ),
      ),
    );
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
        for (final turn in turns) {
          children.add(buildTurnSection(turn));
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
    required this.buildTurnSection,
  });

  final AgentConversationViewModel viewModel;
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
              child: buildTurnSection(turn),
            );
          },
        );
      },
    );
  }
}

/// 固定在 Composer 上方的待处理交互区。
///
/// 权限、用户提问和计划审批都从独立 pending 列表读取，不依赖时间线 entry。
class _AgentPendingInteractionSection extends StatelessWidget {
  const _AgentPendingInteractionSection({
    required this.viewModel,
    required this.panelHeight,
    required this.pagePadding,
  });

  final AgentConversationViewModel viewModel;
  final double panelHeight;
  final EdgeInsets pagePadding;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        viewModel.historyVersionListenable,
        viewModel.composerVersionListenable,
        viewModel.pendingInteractionVersionListenable,
      ]),
      builder: (context, _) => _buildDock(context),
    );
  }

  Widget _buildDock(BuildContext context) {
    final permissionRequests = viewModel.permissionRequests;
    final planApprovalRequests = viewModel.planApprovalRequests;
    if (viewModel.isReadOnly ||
        (permissionRequests.isEmpty && planApprovalRequests.isEmpty)) {
      return const SizedBox.shrink();
    }

    final maxHeight = math.min<double>(360, panelHeight * 0.35);
    return _AgentContentAlign(
      child: Padding(
        padding: pagePadding.copyWith(top: IdeSpacing.space8, bottom: 0),
        child: ConstrainedBox(
          key: const ValueKey('agent-pending-interaction-dock'),
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            key: const ValueKey('agent-pending-interaction-scroll'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (var index = 0; index < permissionRequests.length; index++)
                  Padding(
                    key: ValueKey(
                      'agent-pending-permission-${permissionRequests[index].id}',
                    ),
                    padding: EdgeInsets.only(
                      bottom:
                          index < permissionRequests.length - 1 ||
                              planApprovalRequests.isNotEmpty
                          ? IdeSpacing.space8
                          : 0,
                    ),
                    child: _buildPermissionCard(permissionRequests[index]),
                  ),
                for (
                  var index = 0;
                  index < planApprovalRequests.length;
                  index++
                )
                  Padding(
                    key: ValueKey(
                      'agent-pending-plan-${planApprovalRequests[index].id}',
                    ),
                    padding: EdgeInsets.only(
                      bottom: index < planApprovalRequests.length - 1
                          ? IdeSpacing.space8
                          : 0,
                    ),
                    child: _AgentPlanApprovalCard(
                      request: planApprovalRequests[index],
                      onRespond: (kind) => viewModel.respondToPlanApproval(
                        planApprovalRequests[index],
                        kind,
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

  Widget _buildPermissionCard(AgentPermissionRequest request) {
    return _AgentPermissionCard(
      request: request,
      autoReview: viewModel.autoReviewForTurn(request.turnId),
      onApproveGuardian: viewModel.latestDeniedAutoReview != null
          ? viewModel.approveGuardianDeniedAction
          : null,
      onRespond:
          ({
            required bool approved,
            bool cancelTurn = false,
            Map<String, List<String>> answers = const <String, List<String>>{},
            AgentCommandApprovalDecisionKind? commandDecision,
            List<String> execpolicyAmendment = const <String>[],
          }) => viewModel.respondToPermission(
            request,
            approved: approved,
            cancelTurn: cancelTurn,
            answers: answers,
            commandDecision: commandDecision,
            execpolicyAmendment: execpolicyAmendment,
          ),
    );
  }
}

class _AgentTurnSection extends StatelessWidget {
  const _AgentTurnSection({
    required this.turn,
    required this.viewModel,
    super.key,
  });

  final AgentConversationTurnGroup turn;
  final AgentConversationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final renderBlocks = buildAgentTimelineRenderBlocks(
      turnId: turn.id,
      entries: turn.entries,
    );
    final isLiveRunning =
        !turn.isStandby && turn.status == AgentHistoryTurnStatus.running;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final block in renderBlocks)
          KeyedSubtree(
            key: ValueKey<String>('turn-block-${turn.id}-${block.id}'),
            child: _buildBlock(block),
          ),
        // 对话流内进行中状态（与 header 同源；Grok/Codex 通用）。
        if (isLiveRunning) _AgentLiveActivityStatus(viewModel: viewModel),
        // 每个非 standby turn 末尾展示耗时与本 turn token 用量。
        if (!turn.isStandby) _AgentTurnFooter(turn: turn),
      ],
    );
  }

  Widget _buildBlock(AgentTimelineRenderBlock block) {
    return switch (block) {
      AgentTimelineEntryRenderBlock(:final entry) => _buildTimelineEntry(entry),
      AgentTimelineCommandGroupRenderBlock(:final group) =>
        _AgentCommandGroupCard(group: group, viewModel: viewModel),
      AgentTimelineFileEditGroupRenderBlock(:final group) =>
        _AgentFileEditGroupCard(group: group, viewModel: viewModel),
    };
  }

  Widget _buildTimelineEntry(AgentTimelineEntry entry) {
    final isLiveTurn = viewModel.liveTurnState?.id == turn.id;
    return switch (entry) {
      AgentMessageTimelineEntry(:final message) => _AgentMessageEntry(
        message: message,
        // 历史与 live 的普通 Markdown 正文均不折叠；plan / 完成汇总等特殊卡自有样式。
        collapseHeavyContent: false,
        useStreamingMarkdown: isLiveTurn,
        viewModel: viewModel,
      ),
      AgentToolTimelineEntry(:final toolCall) => _AgentToolCallCard(
        toolCall: toolCall,
        viewModel: viewModel,
      ),
      // pending 交互只在 Composer 上方的 dock 渲染，避免时间线出现重复卡片。
      AgentPermissionTimelineEntry() => const SizedBox.shrink(),
      AgentPlanApprovalTimelineEntry() => const SizedBox.shrink(),
      // 正常路径会在 grouping 中转成文件编辑组；此处仅作兜底。
      AgentTurnDiffTimelineEntry() => const SizedBox.shrink(),
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
    required this.composerFocusNode,
    required this.canSendListenable,
    required this.draftImagePaths,
    required this.onAttachImages,
    required this.onRemoveImage,
    required this.onPasteImages,
    required this.onSend,
    required this.onInsertMention,
    required this.pagePadding,
    super.key,
  });

  final AgentConversationViewModel viewModel;
  final TextEditingController inputController;
  final FocusNode composerFocusNode;
  final ValueListenable<bool> canSendListenable;
  final List<String> draftImagePaths;
  final VoidCallback onAttachImages;
  final ValueChanged<String> onRemoveImage;
  final Future<bool> Function() onPasteImages;
  final VoidCallback onSend;
  final ValueChanged<WorkspaceNode> onInsertMention;
  final EdgeInsets pagePadding;

  @override
  Widget build(BuildContext context) {
    return _AgentContentAlign(
      child: Padding(
        padding: pagePadding.copyWith(top: IdeSpacing.space8),
        child: ListenableBuilder(
          listenable: viewModel.composerVersionListenable,
          builder: (context, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: canSendListenable,
              builder: (context, canSend, _) {
                return _AgentComposer(
                  controller: inputController,
                  focusNode: composerFocusNode,
                  canSubmit: canSend && viewModel.canSubmitMessage,
                  isTurnRunning: viewModel.isTurnRunning,
                  threadOpenPhase: viewModel.threadOpenPhase,
                  currentWindowTokenUsage:
                      viewModel.currentThreadLastTokenUsage,
                  draftImagePaths: draftImagePaths,
                  onAttachImages: onAttachImages,
                  onRemoveImage: onRemoveImage,
                  onPasteImages: onPasteImages,
                  onSend: onSend,
                  onCancel: viewModel.cancelActiveTurn,
                  showImageAttachment: viewModel.canAttachImages,
                  showResourceMention: viewModel.canMentionResources,
                  showModelSelection: viewModel.showModelSelection,
                  modelConfigState: viewModel.modelConfigUiState,
                  showPermissionPolicy: viewModel.showPermissionPolicy,
                  permissionPolicyLabel: viewModel.permissionPolicyLabel,
                  permissionPresets: AgentPermissionSelection.presets,
                  selectedPermissionPresetId:
                      viewModel.permissionSelection.matchedPresetId,
                  sessionConfigOptions: viewModel.sessionConfigOptions,
                  onSelectModel: viewModel.selectModel,
                  onSelectReasoningEffort: viewModel.selectReasoningEffort,
                  onSelectFastEnabled: viewModel.selectFastEnabled,
                  onResolveModelCompatibility:
                      viewModel.resolveModelCompatibilityConflict,
                  onRetryModelConfiguration:
                      viewModel.retryModelConfigurationSave,
                  onCloseModelConfiguration:
                      viewModel.clearModelConfigurationTransientState,
                  onSelectPermissionPreset: viewModel.selectPermissionPreset,
                  onSelectSessionConfigOption:
                      viewModel.selectSessionConfigOption,
                  mentionCandidates: viewModel.mentionCandidateFiles,
                  onInsertMention: onInsertMention,
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
        constraints: const BoxConstraints(maxWidth: IdeMetrics.contentMaxWidth),
        child: SizedBox(width: double.infinity, child: child),
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
    final textStyles = IdeTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: sf.GhostButton(
          key: const ValueKey('agent-load-older-turns-button'),
          onPressed: loading ? null : onPressed,
          size: sf.ButtonSize.small,
          leading: loading
              ? const IdeLoadingIndicator(width: 16, height: 10, barHeight: 3)
              : const Icon(Icons.history_rounded, size: 15),
          child: Text(
            loading ? 'Loading older turns' : 'Load older turns',
            style: textStyles.bodySmall,
          ),
        ),
      ),
    );
  }
}
