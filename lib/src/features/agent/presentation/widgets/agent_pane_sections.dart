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
        _AgentCommandGroupCard(group: group, viewModel: viewModel),
      AgentTimelineFileEditGroupRenderBlock(:final group) =>
        _AgentFileEditGroupCard(group: group, viewModel: viewModel),
    };
  }

  Widget _buildTimelineEntry(AgentTimelineEntry entry) {
    final isLiveTurn = viewModel.liveTurnState?.id == turn.id;
    final collapseHeavyContent = !isLiveTurn;
    return switch (entry) {
      AgentMessageTimelineEntry(:final message) => _AgentMessageEntry(
        message: message,
        collapseHeavyContent: collapseHeavyContent,
        useStreamingMarkdown: isLiveTurn,
        viewModel: viewModel,
      ),
      AgentToolTimelineEntry(:final toolCall) => _AgentToolCallCard(
        toolCall: toolCall,
        viewModel: viewModel,
      ),
      AgentPermissionTimelineEntry(:final request) => _AgentPermissionCard(
        request: request,
        autoReview: viewModel.autoReviewForTurn(request.turnId),
        onApproveGuardian: viewModel.latestDeniedAutoReview != null
            ? viewModel.approveGuardianDeniedAction
            : null,
        onRespond:
            ({
              required bool approved,
              bool cancelTurn = false,
              Map<String, List<String>> answers =
                  const <String, List<String>>{},
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
      ),
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
                  canSubmit: canSend && viewModel.canSubmitMessage,
                  isTurnRunning: viewModel.isTurnRunning,
                  threadOpenPhase: viewModel.threadOpenPhase,
                  draftImagePaths: draftImagePaths,
                  onAttachImages: onAttachImages,
                  onRemoveImage: onRemoveImage,
                  onPasteImages: onPasteImages,
                  onSend: onSend,
                  onCancel: viewModel.cancelActiveTurn,
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
                  onSelectModel: (modelId) => viewModel.selectModel(modelId),
                  onSelectReasoningEffort: (effort) =>
                      viewModel.selectReasoningEffort(effort),
                  onSelectServiceTier: (tierId) =>
                      viewModel.selectServiceTier(tierId),
                  onSelectPermissionPreset: viewModel.selectPermissionPreset,
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
        child: ShadButton.ghost(
          key: const ValueKey('agent-load-older-turns-button'),
          onPressed: loading ? null : onPressed,
          size: ShadButtonSize.sm,
          leading: loading
              ? const IdeLoadingIndicator(width: 16, height: 10, barHeight: 3)
              : const Icon(Icons.history_rounded, size: 15),
          textStyle: textStyles.bodySmall,
          child: Text(loading ? 'Loading older turns' : 'Load older turns'),
        ),
      ),
    );
  }
}
