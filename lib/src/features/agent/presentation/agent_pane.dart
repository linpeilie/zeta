import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_actions.dart';
import 'dart:async';
import 'agent_pane_retention.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta_ui/zeta_ui.dart';
import 'package:zeta/src/features/agent/application/agent_composer_attachment_port.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_runtime_controller.dart';
import 'package:zeta/src/features/agent/presentation/agent_markdown_cache.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane_composer_session.dart';
import 'package:zeta/src/features/agent/presentation/agent_plan_revision_drafts.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_renderer.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_renderer_registry.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_renderers.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_extent_descriptor.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_projection_cache.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_pane_body.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_pane_context_panel.dart';

/// Agent 主列宽度档位：只影响 page padding 等布局语义，不随每像素宽度重建。
enum _AgentPaneWidthClass { compact, regular }

_AgentPaneWidthClass _selectAgentPaneWidthClass(BoxConstraints constraints) {
  return constraints.maxWidth < IdeMetrics.stackedRowBreakpoint
      ? _AgentPaneWidthClass.compact
      : _AgentPaneWidthClass.regular;
}

/// 中间 Agent 面板。
///
/// 当前文件只保留页面壳、滚动协作、上下文面板显隐与 Composer 接线；
/// header、timeline、composer 以及各类卡片都在独立组件文件。
class AgentPane extends ConsumerStatefulWidget {
  const AgentPane({
    required this.controller,
    this.messageSendShortcut = MessageSendShortcut.enter,
    this.isActive = true,
    super.key,
  });

  final AgentConversationRuntimeController controller;

  /// 当前消息输入框使用的发送快捷键。
  final MessageSendShortcut messageSendShortcut;

  /// 是否为前台 canvas。
  ///
  /// 非前台时时间线不订阅 live 高频 listenable，仅保留 history/expansion
  /// 与 threadSnapshot 侧栏路径。
  final bool isActive;

  /// 测试用：走与粘贴相同的暂存端口，把字节写成草稿图。
  @visibleForTesting
  static Future<void> debugPasteClipboardImage(
    GlobalKey key,
    Uint8List bytes,
  ) async {
    final state = key.currentState;
    if (state is! _AgentPaneState) {
      throw StateError(
        'AgentPane is not mounted for $key (state=${state.runtimeType})',
      );
    }
    final path = await state._composer.stageClipboardImage(bytes);
    if (!state.mounted) {
      return;
    }
    state._composer.addDraftImages(<String>[path]);
  }

  @visibleForTesting
  static void debugAddDraftImages(GlobalKey key, List<String> paths) {
    final state = key.currentState;
    if (state is! _AgentPaneState) {
      throw StateError(
        'AgentPane is not mounted for $key (state=${state.runtimeType})',
      );
    }
    state._composer.addDraftImages(paths);
  }

  /// 测试用：读取当前草稿图片路径。
  @visibleForTesting
  static List<String> debugDraftImagePaths(GlobalKey key) {
    final state = key.currentState;
    if (state is! _AgentPaneState) {
      return const <String>[];
    }
    return state._composer.draftImagePaths.value;
  }

  @override
  ConsumerState<AgentPane> createState() => _AgentPaneState();
}

class _AgentPaneState extends ConsumerState<AgentPane> {
  late final AgentPaneComposerSession _composer;
  late final AgentPaneRetention _retention;
  late final IdeSmoothScrollController _scrollController;
  final ValueNotifier<bool> _contextPanelVisible = ValueNotifier<bool>(false);
  late StreamSubscription<AgentUiEffect> _uiEffectSubscription;

  final IdeVirtualListController _virtualListController =
      IdeVirtualListController();
  late final IdeVirtualScrollCoordinator _scrollCoordinator;
  late final IdeScrollControllerDriver _scrollDriver;
  final ValueNotifier<int> _scrollChromeTick = ValueNotifier<int>(0);
  final ValueNotifier<double> _activePlanPanelExtent = ValueNotifier<double>(0);
  String? _lastTimelineItemId;
  double _panelHeight = 600;
  late final AgentTimelineProjectionCache _projectionCache;

  /// 渲染分发表：无状态，整个 Pane 生命周期一份。
  final AgentTimelineRendererRegistry _rendererRegistry =
      buildAgentTimelineRendererRegistry();
  late final AgentTimelineExtentDescriptorFactory _descriptorFactory =
      AgentTimelineExtentDescriptorFactory(registry: _rendererRegistry);
  AgentMarkdownCache _markdownCache = AgentMarkdownCache();
  AgentPlanRevisionDraftStore _planRevisionDrafts =
      AgentPlanRevisionDraftStore();

  /// renderer 的稳定依赖；会话（controller / 缓存）换代时重建。
  late AgentTimelineRenderContext _renderContext;
  late AgentConversationActions _actions;
  late Widget Function(BuildContext, _AgentPaneWidthClass)
  _responsiveBodyBuilder;

  @override
  void initState() {
    super.initState();
    _retention = ref.read(agentPaneRetentionProvider);
    final retained = _retention.take(widget.controller);
    _projectionCache = AgentTimelineProjectionCache(
      textCatalog: widget.controller.textCatalog,
    );
    _actions = ref.read(
      agentConversationActionsProvider(
        widget.controller.conversationBinding.key,
      ),
    );
    _renderContext = _createRenderContext();
    _composer = AgentPaneComposerSession(
      runtime: widget.controller,
      messageSendShortcut: widget.messageSendShortcut,
      isMounted: () => mounted,
      attachments: () => ref.read(agentComposerAttachmentPortProvider),
      submitMessage: _actions.sendMessage,
      actions: _actions,
      hostContext: () => context,
    );
    if (retained != null) _composer.restoreDraft(retained);
    _responsiveBodyBuilder = _createResponsiveBodyBuilder();
    _scrollController = IdeSmoothScrollController(
      initialScrollOffset: retained?.scrollMetrics?.pixels ?? 0,
      smoothScrollingEnabled: false,
    );
    _scrollDriver = IdeScrollControllerDriver(_scrollController);
    _scrollCoordinator = IdeVirtualScrollCoordinator(driver: _scrollDriver)
      ..onModeChanged = _notifyScrollChrome;
    if (retained?.freeScroll == true && retained?.scrollMetrics != null) {
      _scrollCoordinator.onUserScroll(retained!.scrollMetrics!);
    }
    _scrollController.addListener(_handleScrollChanged);
    _uiEffectSubscription = widget.controller.uiEffects.listen(_handleUiEffect);
  }

  @override
  void didUpdateWidget(covariant AgentPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    _composer.messageSendShortcut = widget.messageSendShortcut;
    if (oldWidget.controller == widget.controller) {
      return;
    }
    _hideContextPanel();
    unawaited(_uiEffectSubscription.cancel());
    _actions = ref.read(
      agentConversationActionsProvider(
        widget.controller.conversationBinding.key,
      ),
    );
    _composer.updateRuntime(
      widget.controller,
      actions: _actions,
      submitMessage: _actions.sendMessage,
    );
    _responsiveBodyBuilder = _createResponsiveBodyBuilder();
    _projectionCache.clear();
    _descriptorFactory.clearCache();
    final previousMarkdownCache = _markdownCache;
    _markdownCache = AgentMarkdownCache();
    final previousPlanDrafts = _planRevisionDrafts;
    _planRevisionDrafts = AgentPlanRevisionDraftStore();
    // controller 与两个缓存都换了实例，渲染上下文必须跟着换代。
    _renderContext = _createRenderContext();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      previousMarkdownCache.dispose();
      previousPlanDrafts.dispose();
    });
    _virtualListController.synchronizeNow(
      const <IdeVirtualItemDescriptor>[],
      epoch: const IdeLayoutEpoch(
        crossAxisExtentInPhysicalPixels: 0,
        textScaleKey: 1.0,
        localeKey: 'und',
        typographyEpoch: 0,
      ),
    );
    _lastTimelineItemId = null;
    unawaited(_scrollCoordinator.requestFollowEnd(animated: false));
    _uiEffectSubscription = widget.controller.uiEffects.listen(_handleUiEffect);
  }

  AgentTimelineRenderContext _createRenderContext() {
    return AgentTimelineRenderContext(
      bindingKey: widget.controller.conversationBinding.key,
      controller: widget.controller,
      actions: _actions,
      markdownCache: _markdownCache,
      planRevisionDrafts: _planRevisionDrafts,
    );
  }

  @override
  void deactivate() {
    _retention.save(
      widget.controller,
      AgentPaneRetainedState(
        document: _composer.inputController.snapshot(),
        imagePaths: List.unmodifiable(_composer.draftImagePaths.value),
        stagedPaths: _composer.stagedClipboardPaths,
        scrollMetrics: _scrollController.hasClients
            ? IdeVirtualScrollMetricsSnapshot(
                pixels: _scrollController.offset,
                maxScrollExtent: _scrollController.position.maxScrollExtent,
                viewportDimension: _scrollController.position.viewportDimension,
              )
            : null,
        freeScroll: _scrollCoordinator.mode == IdeVirtualScrollMode.free,
      ),
    );
    super.deactivate();
  }

  @override
  void dispose() {
    unawaited(_uiEffectSubscription.cancel());
    _scrollController.removeListener(_handleScrollChanged);
    _scrollCoordinator.onModeChanged = null;
    _composer.dispose(retainDraft: _retention.accepts(widget.controller));
    _scrollController.dispose();
    _contextPanelVisible.dispose();
    _scrollChromeTick.dispose();
    _activePlanPanelExtent.dispose();
    _projectionCache.clear();
    _descriptorFactory.clearCache();
    _markdownCache.dispose();
    _planRevisionDrafts.dispose();
    super.dispose();
  }

  void _notifyScrollChrome() {
    _scrollChromeTick.value += 1;
  }

  void _handleActivePlanPanelExtentChanged(double extent) {
    if (_activePlanPanelExtent.value == extent) {
      return;
    }
    _activePlanPanelExtent.value = extent;
  }

  @override
  Widget build(BuildContext context) {
    return IdeSurface.canvas(
      key: const ValueKey('agent-canvas'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: IdeConstraintBucketBuilder<_AgentPaneWidthClass>(
              key: const ValueKey('agent-pane-width-bucket'),
              selectBucket: _selectWidthBucketAndTrackHeight,
              builder: _responsiveBodyBuilder,
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _contextPanelVisible,
            builder: (context, visible, _) {
              if (!visible) {
                return const SizedBox.shrink();
              }
              return AgentContextPanel(
                controller: widget.controller,
                onClose: _hideContextPanel,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget Function(BuildContext, _AgentPaneWidthClass)
  _createResponsiveBodyBuilder() => _buildResponsiveBody;

  Widget _buildResponsiveBody(
    BuildContext context,
    _AgentPaneWidthClass widthClass,
  ) {
    final pagePadding = switch (widthClass) {
      _AgentPaneWidthClass.compact => IdeSpacing.pagePaddingCompact,
      _AgentPaneWidthClass.regular => IdeSpacing.pagePadding,
    };
    return AgentPaneBody(
      controller: widget.controller,
      actions: _actions,
      isActive: widget.isActive,
      pagePadding: pagePadding,
      scrollController: _scrollController,
      floatingPanelExtent: _activePlanPanelExtent,
      projectionCache: _projectionCache,
      descriptorFactory: _descriptorFactory,
      renderContext: _renderContext,
      rendererRegistry: _rendererRegistry,
      virtualListController: _virtualListController,
      scrollCoordinator: _scrollCoordinator,
      scrollChromeTick: _scrollChromeTick,
      onLastItemIdChanged: (id) {
        _lastTimelineItemId = id;
      },
      onScrollToEndPressed: _requestScrollToEndFromButton,
      onActivePlanExtentChanged: _handleActivePlanPanelExtentChanged,
      panelHeight: _panelHeight,
      composerAnchorKey: _composer.composerAnchorKey,
      inputController: _composer.inputController,
      composerFocusNode: _composer.focusNode,
      canSendListenable: _composer.canSendNotifier,
      draftImagePathsListenable: _composer.draftImagePaths,
      onAttachImages: _composer.pickImages,
      onRemoveImage: _composer.removeDraftImage,
      onSend: _composer.sendMessage,
      onOpenMentionPicker: _composer.openMentionPickerFromMenu,
      onSelectSkill: _composer.selectSkillFromMenu,
      onToggleContextPanel: _toggleContextPanel,
    );
  }

  _AgentPaneWidthClass _selectWidthBucketAndTrackHeight(
    BoxConstraints constraints,
  ) {
    final height = constraints.maxHeight;
    if (height.isFinite && height > 0) {
      _panelHeight = height;
    }
    return _selectAgentPaneWidthClass(constraints);
  }

  void _toggleContextPanel() {
    _contextPanelVisible.value = !_contextPanelVisible.value;
  }

  void _hideContextPanel() {
    _contextPanelVisible.value = false;
  }

  void _handleUiEffect(AgentUiEffect effect) {
    if (!widget.isActive || effect is! AgentRequestAutoScroll) {
      return;
    }
    _scrollCoordinator.notifyContentChanged(lastItemId: _lastTimelineItemId);
    _notifyScrollChrome();
  }

  void _handleScrollChanged() {
    if (!_scrollCoordinator.isProgrammatic) {
      final metrics = _currentScrollMetrics();
      if (metrics != null) {
        _scrollCoordinator.onUserScroll(metrics);
      }
    }
    _notifyScrollChrome();
  }

  IdeVirtualScrollMetricsSnapshot? _currentScrollMetrics() {
    if (!_scrollController.hasClients) {
      return null;
    }
    final position = _scrollController.position;
    return IdeVirtualScrollMetricsSnapshot(
      pixels: position.pixels,
      maxScrollExtent: position.maxScrollExtent,
      viewportDimension: position.viewportDimension,
    );
  }

  Future<void> _requestScrollToEndFromButton() {
    return _scrollCoordinator.requestFollowEnd(
      lastItemId: _lastTimelineItemId,
      animated: !MediaQuery.disableAnimationsOf(context),
    );
  }
}
