part of '../agent_pane.dart';

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
  });

  final AgentConversationViewModel viewModel;
  final double panelHeight;

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
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
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
                  models: viewModel.models,
                  selectedModel: viewModel.selectedModel,
                  selectedReasoningEffort: viewModel.selectedReasoningEffort,
                  selectedServiceTierId: viewModel.selectedServiceTierId,
                  showReasoningEffort: viewModel.showReasoningEffort,
                  showServiceTier: viewModel.showServiceTier,
                  showPermissionPolicy: viewModel.showPermissionPolicy,
                  permissionPolicyLabel: viewModel.permissionPolicyLabel,
                  permissionPresets: AgentPermissionSelection.presets,
                  selectedPermissionPresetId:
                      viewModel.permissionSelection.matchedPresetId,
                  sessionConfigOptions: viewModel.sessionConfigOptions,
                  onSelectModel: (modelId) => viewModel.selectModel(modelId),
                  onSelectReasoningEffort: (effort) =>
                      viewModel.selectReasoningEffort(effort),
                  onSelectServiceTier: (tierId) =>
                      viewModel.selectServiceTier(tierId),
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
