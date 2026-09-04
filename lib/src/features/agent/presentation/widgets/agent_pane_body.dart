import 'package:flutter/material.dart';

import 'package:zeta_ui/zeta_ui.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_region_state.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_runtime_controller.dart';
import 'package:zeta/src/features/agent/presentation/agent_flutter_listenable_adapter.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_extent_descriptor.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_projection_cache.dart';
import 'package:zeta/src/features/agent/presentation/composer_document.dart';
import 'package:zeta/src/features/agent/presentation/conversation_slice/agent_conversation_slice_providers.dart';
import 'package:zeta/src/features/agent/presentation/conversation_slice/agent_region_builder.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_renderer.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_renderer_registry.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_pane_header.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_pane_plan_panel.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_pane_sections.dart';
import 'package:zeta/src/ui/localization/app_localizations_x.dart';

/// Agent 主列对话结构：header、时间线、Plan 浮层、pending dock 与 Composer。
class AgentPaneBody extends StatelessWidget {
  const AgentPaneBody({
    required this.controller,
    required this.isActive,
    required this.pagePadding,
    required this.scrollController,
    required this.floatingPanelExtent,
    required this.projectionCache,
    required this.descriptorFactory,
    required this.renderContext,
    required this.rendererRegistry,
    required this.virtualListController,
    required this.scrollCoordinator,
    required this.scrollChromeTick,
    required this.onLastItemIdChanged,
    required this.onScrollToEndPressed,
    required this.onActivePlanExtentChanged,
    required this.panelHeight,
    required this.composerAnchorKey,
    required this.inputController,
    required this.composerFocusNode,
    required this.canSendListenable,
    required this.draftImagePathsListenable,
    required this.onAttachImages,
    required this.onRemoveImage,
    required this.onSend,
    required this.onOpenMentionPicker,
    required this.onInsertSkill,
    required this.onToggleContextPanel,
    super.key,
  });

  final AgentConversationRuntimeController controller;
  final bool isActive;
  final EdgeInsets pagePadding;
  final ScrollController scrollController;
  final ValueNotifier<double> floatingPanelExtent;
  final AgentTimelineProjectionCache projectionCache;
  final AgentTimelineExtentDescriptorFactory descriptorFactory;
  final AgentTimelineRenderContext renderContext;
  final AgentTimelineRendererRegistry rendererRegistry;
  final IdeVirtualListController virtualListController;
  final IdeVirtualScrollCoordinator scrollCoordinator;
  final ValueNotifier<int> scrollChromeTick;
  final ValueChanged<String?> onLastItemIdChanged;
  final Future<void> Function() onScrollToEndPressed;
  final ValueChanged<double> onActivePlanExtentChanged;
  final double panelHeight;
  final Key composerAnchorKey;
  final ComposerDocumentController inputController;
  final FocusNode composerFocusNode;
  final ValueNotifier<bool> canSendListenable;
  final ValueNotifier<List<String>> draftImagePathsListenable;
  final VoidCallback onAttachImages;
  final ValueChanged<String> onRemoveImage;
  final VoidCallback onSend;
  final VoidCallback onOpenMentionPicker;
  final VoidCallback onInsertSkill;
  final VoidCallback onToggleContextPanel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AgentContentAlign(
          child: Padding(
            padding: pagePadding,
            child: AgentRegionBuilder<AgentHeaderState>(
              bindingKey: controller.conversationBinding.key,
              selector: agentConversationHeaderProvider.call,
              builder: (context, state) {
                return AgentHeader(
                  controller: controller,
                  state: state,
                  onToggleContextPanel: onToggleContextPanel,
                );
              },
            ),
          ),
        ),
        Expanded(
          child: AgentRegionBuilder<AgentConversationHistoryState>(
            bindingKey: controller.conversationBinding.key,
            selector: agentConversationHistoryProvider.call,
            builder: (context, historyState) => ListenableBuilder(
              listenable: controller.flutterLiveTurnListenable,
              builder: (context, _) {
                final liveTurnState = controller.liveTurnState;
                final hasConversation =
                    historyState.visibleTurns.isNotEmpty ||
                    liveTurnState != null;
                final isLoadingHistory = historyState.isLoading;
                final pinFooterToBottom = hasConversation || isLoadingHistory;
                return AgentConversationLayout(
                  pinFooterToBottom: pinFooterToBottom,
                  reduceMotion: MediaQuery.disableAnimationsOf(context),
                  timeline: isLoadingHistory
                      ? AgentThreadHistoryLoading(
                          providerId: historyState.providerId,
                          providerName: historyState.providerName,
                        )
                      : AgentConversationTimeline(
                          controller: controller,
                          isActive: isActive,
                          scrollController: scrollController,
                          pagePadding: pagePadding,
                          floatingPanelExtent: floatingPanelExtent,
                          projectionCache: projectionCache,
                          descriptorFactory: descriptorFactory,
                          renderContext: renderContext,
                          rendererRegistry: rendererRegistry,
                          virtualListController: virtualListController,
                          scrollCoordinator: scrollCoordinator,
                          scrollChromeTick: scrollChromeTick,
                          onLastItemIdChanged: onLastItemIdChanged,
                          onScrollToEndPressed: onScrollToEndPressed,
                        ),
                  floatingPanel: AgentActivePlanSection(
                    controller: controller,
                    pagePadding: pagePadding,
                    onExtentChanged: onActivePlanExtentChanged,
                  ),
                  footer: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AgentPendingInteractionSection(
                        controller: controller,
                        panelHeight: panelHeight,
                        pagePadding: pagePadding,
                      ),
                      AgentRegionBuilder<AgentComposerState>(
                        bindingKey: controller.conversationBinding.key,
                        selector: agentConversationComposerProvider.call,
                        builder: (context, composerState) =>
                            AgentRegionBuilder<AgentPendingInteractionState>(
                              bindingKey: controller.conversationBinding.key,
                              selector:
                                  agentConversationPendingInteractionProvider
                                      .call,
                              builder: (context, pendingState) =>
                                  ValueListenableBuilder<List<String>>(
                                    valueListenable: draftImagePathsListenable,
                                    builder: (context, draftImagePaths, _) {
                                      return Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          if (composerState.isReadOnly)
                                            _AgentReadOnlyNotice(
                                              pagePadding: pagePadding,
                                            )
                                          else if (!pendingState.blocksComposer)
                                            AgentComposerSection(
                                              key: const ValueKey(
                                                'agent-composer-section',
                                              ),
                                              anchorKey: composerAnchorKey,
                                              controller: controller,
                                              state: composerState,
                                              inputController: inputController,
                                              composerFocusNode:
                                                  composerFocusNode,
                                              canSendListenable:
                                                  canSendListenable,
                                              draftImagePaths: draftImagePaths,
                                              pagePadding: pagePadding,
                                              onAttachImages: onAttachImages,
                                              onRemoveImage: onRemoveImage,
                                              onSend: onSend,
                                              onOpenMentionPicker:
                                                  onOpenMentionPicker,
                                              onInsertSkill: onInsertSkill,
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                            ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _AgentReadOnlyNotice extends StatelessWidget {
  const _AgentReadOnlyNotice({required this.pagePadding});

  final EdgeInsets pagePadding;

  @override
  Widget build(BuildContext context) {
    final textStyles = IdeTextStyles.of(context);
    final colors = IdeColors.of(context);
    return AgentContentAlign(
      child: Padding(
        padding: pagePadding.copyWith(top: IdeSpacing.space8),
        child: IdeStatusCard(
          key: const ValueKey('agent-read-only-notice'),
          tone: IdeStatusCardTone.warning,
          title: context.l10n.agentReadonlyTitle,
          margin: EdgeInsets.zero,
          body: Text(
            context.l10n.agentReadonlyBody,
            style: textStyles.bodySmall.copyWith(color: colors.textSecondary),
          ),
        ),
      ),
    );
  }
}
