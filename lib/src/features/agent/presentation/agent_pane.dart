import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:highlight/highlight.dart' show Node, highlight;
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/features/agent/application/agent_conversation_mode_controller.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';
import 'package:zeta/src/ui/core/ide_image_preview.dart';
import 'package:zeta_ui/zeta_ui.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/features/agent/presentation/conversation_slice/agent_conversation_slice_providers.dart';
import 'package:zeta/src/features/agent/presentation/conversation_slice/agent_region_builder.dart';
import 'package:zeta/src/features/agent/presentation/agent_presentation_l10n.dart';
import 'package:zeta/src/ui/localization/app_localizations_x.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_region_state.dart';
import 'package:zeta/src/features/agent/presentation/agent_markdown_cache.dart';
import 'package:zeta/src/features/agent/presentation/agent_plan_revision_drafts.dart';
import 'package:zeta/src/features/agent/presentation/composer_document.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_navigation.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_extent_descriptor.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_grouping.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_projection.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_projection_cache.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_model_config_ui_state.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_file_change_evidence_card.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_provider_icon.dart';

part 'widgets/agent_pane_cards.dart';
part 'widgets/agent_pane_composer.dart';
part 'widgets/agent_pane_context_panel.dart';
part 'widgets/agent_pane_header.dart';
part 'widgets/agent_pane_messages.dart';
part 'widgets/agent_pane_plan_panel.dart';
part 'widgets/composer_selector_popover.dart';
part 'widgets/agent_model_config.dart';
part 'widgets/agent_mode_selector.dart';
part 'widgets/agent_skill_picker.dart';
part 'widgets/agent_slash_command_picker.dart';
part 'widgets/agent_mention_file_picker.dart';
part 'widgets/agent_pane_sections.dart';
part 'widgets/agent_pane_styles.dart';
part 'widgets/agent_pane_navigation_rail.dart';

/// Agent 主列宽度档位：只影响 page padding 等布局语义，不随每像素宽度重建。
enum _AgentPaneWidthClass { compact, regular }

_AgentPaneWidthClass _selectAgentPaneWidthClass(BoxConstraints constraints) {
  return constraints.maxWidth < IdeMetrics.stackedRowBreakpoint
      ? _AgentPaneWidthClass.compact
      : _AgentPaneWidthClass.regular;
}

/// 中间 Agent 面板。
///
/// 当前文件只保留页面壳、滚动协作与组合关系；实际 header、timeline、
/// composer 以及各类卡片都已拆到独立组件文件。
class AgentPane extends StatefulWidget {
  const AgentPane({
    required this.viewModel,
    this.messageSendShortcut = MessageSendShortcut.enter,
    this.isActive = true,
    super.key,
  });

  final AgentConversationViewModel viewModel;

  /// 当前消息输入框使用的发送快捷键。
  final MessageSendShortcut messageSendShortcut;

  /// 是否为前台 canvas。
  ///
  /// 非前台时时间线不订阅 live 高频 listenable，仅保留 history/expansion
  /// 与 threadSnapshot 侧栏路径。
  final bool isActive;

  /// 测试用：向已挂载的 [AgentPane] 注入草稿图片路径（不走系统文件选择器）。
  @visibleForTesting
  static void debugAddDraftImages(GlobalKey key, List<String> paths) {
    final state = key.currentState;
    if (state is! _AgentPaneState) {
      throw StateError(
        'AgentPane is not mounted for $key (state=${state.runtimeType})',
      );
    }
    state._addDraftImages(paths);
  }

  /// 测试用：读取当前草稿图片路径。
  @visibleForTesting
  static List<String> debugDraftImagePaths(GlobalKey key) {
    final state = key.currentState;
    if (state is! _AgentPaneState) {
      return const <String>[];
    }
    return state._draftImagePaths.value;
  }

  @override
  State<AgentPane> createState() => _AgentPaneState();
}

class _AgentPaneState extends State<AgentPane> {
  static const XTypeGroup _imageTypeGroup = XTypeGroup(
    label: 'Images',
    extensions: <String>['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
  );

  final ComposerDocumentController _inputController =
      ComposerDocumentController();
  late final FocusNode _composerFocusNode;
  late final IdeSmoothScrollController _scrollController;
  final ValueNotifier<bool> _canSendNotifier = ValueNotifier<bool>(false);

  /// 草稿图片路径。必须用 listenable 驱动：body 由 [IdeConstraintBucketBuilder]
  /// 缓存，`setState` 不会重建 composer，仅改 list 会让缩略图「删不掉」。
  final ValueNotifier<List<String>> _draftImagePaths =
      ValueNotifier<List<String>>(const <String>[]);
  final GlobalKey _composerAnchorKey = GlobalKey(
    debugLabel: 'agent-composer-skill-anchor',
  );
  late final _ComposerSelectorPopoverController _skillPopoverController;
  final _SkillPickerListController _skillPickerListController =
      _SkillPickerListController();
  late final _ComposerSelectorPopoverController _slashPopoverController;
  final _SlashMenuListController _slashMenuListController =
      _SlashMenuListController();

  /// 允许下一次 `$` 触发自动打开 skill picker（关闭后需先离开 `$query` 再进入）。
  bool _skillQueryArmed = true;

  /// 防止 `$` 监听与菜单入口并发预热时重复 show。
  bool _skillPickerOpening = false;

  /// 允许下一次 `/` 触发自动打开斜线命令菜单。
  bool _slashQueryArmed = true;

  /// 防止 `/` 监听并发预热时重复 show。
  bool _slashPickerOpening = false;

  late final _ComposerSelectorPopoverController _mentionPopoverController;
  final _MentionFileListController _mentionFileListController =
      _MentionFileListController();

  /// 允许下一次 `@` 触发自动打开 mention picker（关闭后需先离开 @token 再进入）。
  bool _mentionQueryArmed = true;

  /// 防止 `@` 监听与菜单入口并发预热时重复 show。
  bool _mentionPickerOpening = false;

  bool get _skillPickerOpen => _skillPopoverController.isOpen;

  bool get _slashPickerOpen => _slashPopoverController.isOpen;

  bool get _mentionPickerOpen => _mentionPopoverController.isOpen;

  /// 是否具备可展示的 Plan 斜线命令。
  bool get _hasSlashPlanCommand {
    if (!widget.viewModel.canSelectConversationMode) {
      return false;
    }
    return widget.viewModel.conversationModeOptions.any(
      (preset) =>
          preset.id == AgentConversationModeId.plan && preset.isSelectable,
    );
  }

  /// 斜线菜单是否至少有一个分区（命令或 Skills）可展示。
  bool get _canOpenSlashMenu =>
      _hasSlashPlanCommand ||
      widget.viewModel.canCompactCurrentThread ||
      widget.viewModel.canUseSkills;

  late StreamSubscription<AgentUiEffect> _uiEffectSubscription;

  /// 动态高度路径：extent index + follow/free 协调器。
  final IdeVirtualListController _virtualListController =
      IdeVirtualListController();
  late final IdeVirtualScrollCoordinator _scrollCoordinator;
  late final IdeScrollControllerDriver _scrollDriver;

  /// 驱动滚到底部按钮可见性刷新（不触发全页 setState）。
  final ValueNotifier<int> _scrollChromeTick = ValueNotifier<int>(0);

  /// Plan 进度浮层实测高度；写入对话流底部滚动 inset，不缩短 viewport。
  final ValueNotifier<double> _activePlanPanelExtent = ValueNotifier<double>(0);

  /// 最近一次 timeline 末项 ID，供 follow reveal 使用。
  String? _lastTimelineItemId;

  /// Agent 主列最近一次有限高度；供 pending dock 计算 maxHeight。
  ///
  /// 在 width-bucket 的 [selectBucket] 中更新，不进入 bucket 身份，因此纵向
  /// 尺寸变化不会使对话结构缓存失效。结构重建时会读到最新值。
  double _panelHeight = 600;

  /// presentation 层 turn projection 缓存；不随窗口 constraints 失效。
  late final AgentTimelineProjectionCache _projectionCache;

  /// extent descriptor 复用缓存（流式仅重建尾部脏项）。
  final AgentTimelineExtentDescriptorFactory _descriptorFactory =
      AgentTimelineExtentDescriptorFactory();
  AgentMarkdownCache _markdownCache = AgentMarkdownCache();

  /// 计划卡修改输入的草稿宿主；卡片在虚拟列表中被回收时草稿不丢。
  AgentPlanRevisionDraftStore _planRevisionDrafts =
      AgentPlanRevisionDraftStore();
  late Widget Function(BuildContext, _AgentPaneWidthClass)
  _responsiveBodyBuilder;

  @override
  void initState() {
    super.initState();
    _projectionCache = AgentTimelineProjectionCache(
      textCatalog: widget.viewModel.textCatalog,
    );
    _composerFocusNode = FocusNode(
      debugLabel: 'AgentMessageComposer',
      onKeyEvent: _handleComposerKeyEvent,
    );
    _skillPopoverController = _ComposerSelectorPopoverController(
      triggerFocusNode: _composerFocusNode,
      onOpenChanged: _handleSkillPopoverOpenChanged,
    );
    _slashPopoverController = _ComposerSelectorPopoverController(
      triggerFocusNode: _composerFocusNode,
      onOpenChanged: _handleSlashPopoverOpenChanged,
    );
    _mentionPopoverController = _ComposerSelectorPopoverController(
      triggerFocusNode: _composerFocusNode,
      onOpenChanged: _handleMentionPopoverOpenChanged,
    );
    _responsiveBodyBuilder = _createResponsiveBodyBuilder();
    _inputController.addListener(_handleInputChanged);
    _inputController.addListener(_handleSkillQueryChanged);
    _inputController.addListener(_handleSlashQueryChanged);
    _inputController.addListener(_handleMentionQueryChanged);
    _scrollController = IdeSmoothScrollController(
      smoothScrollingEnabled: false,
    );
    _scrollDriver = IdeScrollControllerDriver(_scrollController);
    _scrollCoordinator = IdeVirtualScrollCoordinator(driver: _scrollDriver)
      ..onModeChanged = _notifyScrollChrome;
    _scrollController.addListener(_handleScrollChanged);
    _uiEffectSubscription = widget.viewModel.uiEffects.listen(_handleUiEffect);
  }

  @override
  void didUpdateWidget(covariant AgentPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel == widget.viewModel) {
      return;
    }
    unawaited(_uiEffectSubscription.cancel());
    // view model 真正替换时才使档位 child 失效；普通 resize 父重建继续复用。
    _responsiveBodyBuilder = _createResponsiveBodyBuilder();
    _projectionCache.clear();
    _descriptorFactory.clearCache();
    final previousMarkdownCache = _markdownCache;
    _markdownCache = AgentMarkdownCache();
    // 换会话即换计划草稿：旧控制器仍被上一帧的卡片引用，延后一帧释放。
    final previousPlanDrafts = _planRevisionDrafts;
    _planRevisionDrafts = AgentPlanRevisionDraftStore();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      previousMarkdownCache.dispose();
      previousPlanDrafts.dispose();
    });
    // 新会话清空高度缓存，回到 follow 末尾。
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
    // 重置 coordinator：重新 attach driver 并请求 follow。
    unawaited(_scrollCoordinator.requestFollowEnd(animated: false));
    _uiEffectSubscription = widget.viewModel.uiEffects.listen(_handleUiEffect);
  }

  @override
  void dispose() {
    unawaited(_uiEffectSubscription.cancel());
    _inputController.removeListener(_handleInputChanged);
    _inputController.removeListener(_handleSkillQueryChanged);
    _inputController.removeListener(_handleSlashQueryChanged);
    _inputController.removeListener(_handleMentionQueryChanged);
    _scrollController.removeListener(_handleScrollChanged);
    _scrollCoordinator.onModeChanged = null;
    _skillPopoverController.dispose();
    _skillPickerListController.dispose();
    _slashPopoverController.dispose();
    _slashMenuListController.dispose();
    _mentionPopoverController.dispose();
    _mentionFileListController.dispose();
    _inputController.dispose();
    _composerFocusNode.dispose();
    _scrollController.dispose();
    _canSendNotifier.dispose();
    _draftImagePaths.dispose();
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
            // 仅在 Compact/Regular 档位变化时重建对话结构；panelHeight 不进 bucket。
            child: IdeConstraintBucketBuilder<_AgentPaneWidthClass>(
              key: const ValueKey('agent-pane-width-bucket'),
              selectBucket: _selectWidthBucketAndTrackHeight,
              builder: _responsiveBodyBuilder,
            ),
          ),
          // 头栏「上下文」菜单触发的详情面板，默认隐藏。
          ValueListenableBuilder<bool>(
            valueListenable: widget.viewModel.contextPanelVisible,
            builder: (context, visible, _) {
              if (!visible) {
                return const SizedBox.shrink();
              }
              return _AgentContextPanel(viewModel: widget.viewModel);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AgentContentAlign(
          child: Padding(
            padding: pagePadding,
            child: AgentRegionBuilder<AgentHeaderState>(
              viewModel: widget.viewModel,
              selector: agentConversationHeaderProvider.call,
              legacyListenable: widget.viewModel.headerStateListenable,
              builder: (context, state) {
                return _AgentHeader(viewModel: widget.viewModel, state: state);
              },
            ),
          ),
        ),
        Expanded(
          child: AgentRegionBuilder<AgentConversationHistoryState>(
            viewModel: widget.viewModel,
            selector: agentConversationHistoryProvider.call,
            legacyListenable: widget.viewModel.historyStateListenable,
            builder: (context, historyState) => ListenableBuilder(
              // live turn 刻意不进切片（§2.7）：每个 token 触发一次切片发布会
              // 直接撞穿帧预算，它继续走局部重建路径。
              listenable: widget.viewModel.liveTurnListenable,
              builder: (context, _) {
                final liveTurnState = widget.viewModel.liveTurnState;
                final hasConversation =
                    historyState.visibleTurns.isNotEmpty ||
                    liveTurnState != null;
                final isLoadingHistory = historyState.isLoading;
                // 加载历史时输入框固定底部（与已有对话一致），空草稿仍居中。
                final pinFooterToBottom = hasConversation || isLoadingHistory;
                return _AgentConversationLayout(
                  pinFooterToBottom: pinFooterToBottom,
                  reduceMotion: MediaQuery.disableAnimationsOf(context),
                  timeline: isLoadingHistory
                      ? _AgentThreadHistoryLoading(
                          providerId: historyState.providerId,
                          providerKind: historyState.providerKind,
                          providerName: historyState.providerName,
                        )
                      : _AgentConversationTimeline(
                          viewModel: widget.viewModel,
                          isActive: widget.isActive,
                          scrollController: _scrollController,
                          pagePadding: pagePadding,
                          floatingPanelExtent: _activePlanPanelExtent,
                          projectionCache: _projectionCache,
                          descriptorFactory: _descriptorFactory,
                          markdownCache: _markdownCache,
                          planRevisionDrafts: _planRevisionDrafts,
                          virtualListController: _virtualListController,
                          scrollCoordinator: _scrollCoordinator,
                          scrollChromeTick: _scrollChromeTick,
                          onLastItemIdChanged: (id) {
                            _lastTimelineItemId = id;
                          },
                          onScrollToEndPressed: _requestScrollToEndFromButton,
                        ),
                  floatingPanel: _AgentActivePlanSection(
                    viewModel: widget.viewModel,
                    pagePadding: pagePadding,
                    onExtentChanged: _handleActivePlanPanelExtentChanged,
                  ),
                  footer: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // panelHeight 由 selectBucket 旁路缓存，不进入 bucket 身份。
                      _AgentPendingInteractionSection(
                        viewModel: widget.viewModel,
                        panelHeight: _panelHeight,
                        pagePadding: pagePadding,
                      ),
                      AgentRegionBuilder<AgentComposerState>(
                        viewModel: widget.viewModel,
                        selector: agentConversationComposerProvider.call,
                        legacyListenable:
                            widget.viewModel.composerStateListenable,
                        builder: (context, composerState) =>
                            AgentRegionBuilder<AgentPendingInteractionState>(
                              viewModel: widget.viewModel,
                              selector:
                                  agentConversationPendingInteractionProvider
                                      .call,
                              legacyListenable: widget
                                  .viewModel
                                  .pendingInteractionStateListenable,
                              builder: (context, pendingState) =>
                                  ValueListenableBuilder<List<String>>(
                                    valueListenable: _draftImagePaths,
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
                                            // 提问卡 / 权限卡占用底部交互时隐藏 Composer，
                                            // 与 pending dock 互斥，避免双焦点与误发送。
                                            _AgentComposerSection(
                                              key: const ValueKey(
                                                'agent-composer-section',
                                              ),
                                              anchorKey: _composerAnchorKey,
                                              viewModel: widget.viewModel,
                                              state: composerState,
                                              inputController: _inputController,
                                              composerFocusNode:
                                                  _composerFocusNode,
                                              canSendListenable:
                                                  _canSendNotifier,
                                              draftImagePaths: draftImagePaths,
                                              pagePadding: pagePadding,
                                              onAttachImages: _pickImages,
                                              onRemoveImage: _removeDraftImage,
                                              onSend: _sendMessage,
                                              onOpenMentionPicker:
                                                  _openMentionPickerFromMenu,
                                              onInsertSkill:
                                                  _openSkillPickerFromMenu,
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

  /// 派生宽度档位，并旁路记录主列高度供 pending dock 使用。
  ///
  /// [IdeConstraintBucketBuilder] 每次 layout 都会调用 selectBucket，即使最终
  /// 返回缓存 child；因此高度可以持续刷新，而不把高度并入 bucket 身份。
  _AgentPaneWidthClass _selectWidthBucketAndTrackHeight(
    BoxConstraints constraints,
  ) {
    final height = constraints.maxHeight;
    if (height.isFinite && height > 0) {
      _panelHeight = height;
    }
    return _selectAgentPaneWidthClass(constraints);
  }

  void _handleInputChanged() {
    _syncCanSend();
  }

  void _handleSkillQueryChanged() {
    if (!widget.viewModel.canUseSkills) {
      return;
    }
    final query = _inputController.activeSkillQuery;
    if (query == null) {
      if (_skillPickerOpen) {
        _skillPopoverController.dismiss();
      }
      _skillQueryArmed = true;
      return;
    }
    if (_skillPickerOpen) {
      return;
    }
    if (!_skillQueryArmed) {
      return;
    }
    // `$` 与 `/`/`@` 互斥：进入 skill 触发时关闭斜线菜单与 mention picker。
    if (_slashPickerOpen) {
      _slashPopoverController.dismiss();
    }
    if (_mentionPickerOpen) {
      _mentionPopoverController.dismiss();
    }
    _skillQueryArmed = false;
    unawaited(_showSkillPicker());
  }

  void _handleSkillPopoverOpenChanged() {
    if (!_skillPickerOpen) {
      _skillPickerListController.reset();
      if (_inputController.activeSkillQuery == null) {
        _skillQueryArmed = true;
      }
    }
  }

  void _handleSlashQueryChanged() {
    if (!_canOpenSlashMenu) {
      return;
    }
    final query = _inputController.activeSlashQuery;
    if (query == null) {
      if (_slashPickerOpen) {
        _slashPopoverController.dismiss();
      }
      _slashQueryArmed = true;
      return;
    }
    if (_slashPickerOpen) {
      return;
    }
    if (!_slashQueryArmed) {
      return;
    }
    // `/` 与 `$`/`@` 互斥：进入斜线触发时关闭 skill picker 与 mention picker。
    if (_skillPickerOpen) {
      _skillPopoverController.dismiss();
    }
    if (_mentionPickerOpen) {
      _mentionPopoverController.dismiss();
    }
    _slashQueryArmed = false;
    unawaited(_showSlashCommandPicker());
  }

  void _handleSlashPopoverOpenChanged() {
    if (!_slashPickerOpen) {
      _slashMenuListController.reset();
      if (_inputController.activeSlashQuery == null) {
        _slashQueryArmed = true;
      }
    }
  }

  void _handleMentionQueryChanged() {
    if (!widget.viewModel.canMentionResources) {
      return;
    }
    final query = _inputController.activeMentionQuery;
    if (query == null) {
      if (_mentionPickerOpen) {
        _mentionPopoverController.dismiss();
      }
      _mentionQueryArmed = true;
      return;
    }
    if (_mentionPickerOpen) {
      return;
    }
    if (!_mentionQueryArmed) {
      return;
    }
    // `@` 与 `$`/`/` 互斥：进入 mention 触发时关闭 skill/slash picker。
    if (_skillPickerOpen) {
      _skillPopoverController.dismiss();
    }
    if (_slashPickerOpen) {
      _slashPopoverController.dismiss();
    }
    _mentionQueryArmed = false;
    unawaited(_showMentionFilePicker());
  }

  void _handleMentionPopoverOpenChanged() {
    if (!_mentionPickerOpen) {
      _mentionFileListController.reset();
      if (_inputController.activeMentionQuery == null) {
        _mentionQueryArmed = true;
      }
    }
  }

  void _syncCanSend() {
    final canSend =
        _inputController.hasContent || _draftImagePaths.value.isNotEmpty;
    if (canSend == _canSendNotifier.value) {
      return;
    }
    _canSendNotifier.value = canSend;
  }

  KeyEventResult _handleComposerKeyEvent(FocusNode node, KeyEvent event) {
    if (!node.hasPrimaryFocus || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (_slashPickerOpen) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _slashPopoverController.dismiss();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _slashMenuListController.move(1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _slashMenuListController.move(-1);
        return KeyEventResult.handled;
      }
      final isEnter =
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter;
      if (isEnter) {
        final composing = _inputController.value.composing;
        if (composing.isValid && !composing.isCollapsed) {
          return KeyEventResult.ignored;
        }
        final item = _slashMenuListController.highlighted;
        if (item != null) {
          _activateSlashMenuItem(item);
        }
        return KeyEventResult.handled;
      }
    }

    if (_skillPickerOpen) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _skillPopoverController.dismiss();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _skillPickerListController.move(1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _skillPickerListController.move(-1);
        return KeyEventResult.handled;
      }
      final isEnter =
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter;
      if (isEnter) {
        final composing = _inputController.value.composing;
        if (composing.isValid && !composing.isCollapsed) {
          return KeyEventResult.ignored;
        }
        final skill = _skillPickerListController.highlighted;
        if (skill != null) {
          _selectSkillFromPicker(skill);
        }
        return KeyEventResult.handled;
      }
    }

    if (_mentionPickerOpen) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _mentionPopoverController.dismiss();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _mentionFileListController.move(1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _mentionFileListController.move(-1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.tab) {
        final file = _mentionFileListController.highlighted;
        if (file != null) {
          _selectMentionFromPicker(file);
        }
        return KeyEventResult.handled;
      }
      final isEnter =
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter;
      if (isEnter) {
        final composing = _inputController.value.composing;
        if (composing.isValid && !composing.isCollapsed) {
          return KeyEventResult.ignored;
        }
        final file = _mentionFileListController.highlighted;
        if (file != null) {
          _selectMentionFromPicker(file);
        }
        return KeyEventResult.handled;
      }
    }

    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (isEnter) {
      final composing = _inputController.value.composing;
      if (composing.isValid && !composing.isCollapsed) {
        // Enter 应先交给输入法确认组合文本，不能在候选仍激活时误发。
        return KeyEventResult.ignored;
      }
      if (_matchesMessageSendShortcut(Theme.of(context).platform)) {
        if (_canSendNotifier.value && widget.viewModel.canSubmitMessage) {
          _sendMessage();
        }
      } else {
        _insertComposerNewline();
      }
      return KeyEventResult.handled;
    }

    final isPaste =
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyV;
    if (!isPaste) {
      return KeyEventResult.ignored;
    }
    // 拦截默认粘贴：优先图片，否则手动插入文本，避免图文重复粘贴。
    unawaited(_pasteImagesFromClipboard());
    return KeyEventResult.handled;
  }

  bool _matchesMessageSendShortcut(TargetPlatform platform) {
    final keyboard = HardwareKeyboard.instance;
    final controlPressed = keyboard.isControlPressed;
    final metaPressed = keyboard.isMetaPressed;
    final shiftPressed = keyboard.isShiftPressed;
    final altPressed = keyboard.isAltPressed;
    return switch (widget.messageSendShortcut) {
      MessageSendShortcut.enter =>
        !controlPressed && !metaPressed && !shiftPressed && !altPressed,
      MessageSendShortcut.primaryModifierEnter =>
        !shiftPressed &&
            !altPressed &&
            (platform == TargetPlatform.macOS
                ? metaPressed && !controlPressed
                : controlPressed && !metaPressed),
    };
  }

  void _insertComposerNewline() {
    final value = _inputController.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final nextText = value.text.replaceRange(start, end, '\n');
    _inputController.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + 1),
      composing: TextRange.empty,
    );
  }

  Future<void> _pickImages() async {
    if (!widget.viewModel.canAttachImages) {
      return;
    }
    final files = await openFiles(
      acceptedTypeGroups: <XTypeGroup>[_imageTypeGroup],
    );
    if (files.isEmpty || !mounted) {
      return;
    }
    _addDraftImages(files.map((file) => file.path));
  }

  /// Ctrl/Cmd+V：优先粘贴剪贴板图片；无图时回退插入纯文本。
  Future<bool> _pasteImagesFromClipboard() async {
    if (widget.viewModel.canAttachImages) {
      final imageBytes = await Pasteboard.image;
      if (imageBytes != null && imageBytes.isNotEmpty) {
        final path = await _persistClipboardImage(imageBytes);
        if (!mounted) {
          return true;
        }
        _addDraftImages(<String>[path]);
        return true;
      }

      final files = await Pasteboard.files();
      final imagePaths = files
          .where(_looksLikeImagePath)
          .toList(growable: false);
      if (imagePaths.isNotEmpty) {
        if (!mounted) {
          return true;
        }
        _addDraftImages(imagePaths);
        return true;
      }
    }

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty || !mounted) {
      return false;
    }
    final selection = _inputController.selection;
    final value = _inputController.text;
    final start = selection.isValid ? selection.start : value.length;
    final end = selection.isValid ? selection.end : value.length;
    final next = value.replaceRange(start, end, text);
    _inputController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    return true;
  }

  void _addDraftImages(Iterable<String> paths) {
    final next = List<String>.of(_draftImagePaths.value);
    var changed = false;
    for (final path in paths) {
      final trimmed = path.trim();
      if (trimmed.isEmpty || next.contains(trimmed)) {
        continue;
      }
      next.add(trimmed);
      changed = true;
    }
    if (!changed) {
      return;
    }
    // 赋新 list 以触发 ValueNotifier；勿依赖 setState（body 被 bucket 缓存）。
    _draftImagePaths.value = List<String>.unmodifiable(next);
    _syncCanSend();
  }

  void _removeDraftImage(String path) {
    final current = _draftImagePaths.value;
    if (!current.contains(path)) {
      return;
    }
    _draftImagePaths.value = List<String>.unmodifiable(
      current.where((item) => item != path),
    );
    _syncCanSend();
  }

  Future<String> _persistClipboardImage(Uint8List bytes) async {
    final root = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}zeta-agent-images',
    );
    await root.create(recursive: true);
    final file = File(
      '${root.path}${Platform.pathSeparator}'
      'paste-${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  bool _looksLikeImagePath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp');
  }

  void _sendMessage() {
    if (!_canSendNotifier.value || !widget.viewModel.canSubmitMessage) {
      return;
    }
    final serialized = _inputController.serialize();
    final images = List<String>.of(_draftImagePaths.value);
    final mentions = serialized.mentions;
    if (serialized.text.trim().isEmpty &&
        images.isEmpty &&
        mentions.isEmpty &&
        serialized.skills.isEmpty) {
      return;
    }
    _inputController.clear();
    if (_draftImagePaths.value.isNotEmpty) {
      _draftImagePaths.value = const <String>[];
    }
    _syncCanSend();
    widget.viewModel.sendMessage(
      serialized.text,
      localImagePaths: images,
      mentions: mentions,
      skills: serialized.skills,
    );
  }

  void _insertSkill(AgentSkillMetadata skill) {
    if (!widget.viewModel.canUseSkills) {
      return;
    }
    _inputController.insertSkill(skill);
    _syncCanSend();
    _composerFocusNode.requestFocus();
  }

  void _selectSkillFromPicker(AgentSkillMetadata skill) {
    _skillPopoverController.dismiss();
    _insertSkill(skill);
  }

  void _activateSlashMenuItem(_SlashMenuItem item) {
    switch (item) {
      case final _SlashCommandMenuItem command:
        _selectSlashCommand(command.id);
      case final _SlashSkillMenuItem skill:
        _selectSkillFromSlashMenu(skill.skill);
    }
  }

  /// 选中斜线命令：移除 `/query` 并执行对应动作。
  void _selectSlashCommand(_SlashCommandId id) {
    _slashPopoverController.dismiss();
    _inputController.consumeActiveSlashQuery();
    switch (id) {
      case _SlashCommandId.plan:
        if (widget.viewModel.selectedConversationMode !=
            AgentConversationModeId.plan) {
          widget.viewModel.selectConversationMode(AgentConversationModeId.plan);
        }
      case _SlashCommandId.compact:
        unawaited(widget.viewModel.compactCurrentThread());
    }
    _composerFocusNode.requestFocus();
  }

  void _selectSkillFromSlashMenu(AgentSkillMetadata skill) {
    _slashPopoverController.dismiss();
    _insertSkill(skill);
  }

  /// More actions → Insert skill：确保进入 `$query` 后再弹出列表。
  void _openSkillPickerFromMenu() {
    if (!widget.viewModel.canUseSkills ||
        _skillPickerOpen ||
        _skillPickerOpening) {
      return;
    }
    // 先解除 `$` 自动打开，避免插入触发与本次 show 并发。
    _skillQueryArmed = false;
    if (_slashPickerOpen) {
      _slashPopoverController.dismiss();
    }
    _ensureSkillQueryTrigger();
    unawaited(_showSkillPicker());
  }

  /// 在光标处写入 `$` 触发片段（必要时补前导空格）。
  void _ensureSkillQueryTrigger() {
    if (_inputController.activeSkillQuery != null) {
      return;
    }
    final text = _inputController.text;
    final selection = _inputController.selection;
    final cursor = selection.isValid
        ? selection.extentOffset.clamp(0, text.length)
        : text.length;
    final start = selection.isValid
        ? selection.baseOffset.clamp(0, text.length)
        : cursor;
    final left = math.min(start, cursor);
    final right = math.max(start, cursor);
    final before = text.substring(0, left);
    final after = text.substring(right);
    final needsSpace = before.isNotEmpty && !RegExp(r'\s$').hasMatch(before);
    final insert = needsSpace ? r' $' : r'$';
    _inputController.value = TextEditingValue(
      text: '$before$insert$after',
      selection: TextSelection.collapsed(offset: before.length + insert.length),
      composing: TextRange.empty,
    );
  }

  Future<void> _showSkillPicker() async {
    if (!widget.viewModel.canUseSkills ||
        _skillPickerOpen ||
        _skillPickerOpening ||
        !mounted) {
      return;
    }
    if (_composerAnchorKey.currentContext == null) {
      return;
    }
    _skillPickerOpening = true;
    try {
      // 打开前尽量预热 skills/list，避免空列表误导。
      try {
        await widget.viewModel.ensureSkillsCatalog();
      } catch (_) {
        // 目录失败时仍展示 picker，由空态提示用户。
      }
      if (!mounted || _skillPickerOpen) {
        return;
      }
      final openContext = _composerAnchorKey.currentContext;
      if (openContext == null || !openContext.mounted) {
        return;
      }
      _skillPopoverController.show(
        context: openContext,
        preferredWidth: _agentSkillPickerPreferredWidth,
        preferredMaxHeight: _agentSkillPickerPreferredMaxHeight,
        key: const ValueKey('agent-skill-picker-overlay'),
        builder: (context, layout) => _AgentSkillPickerPopover(
          width: layout.width,
          maxHeight: layout.maxHeight,
          documentController: _inputController,
          listController: _skillPickerListController,
          candidatesFor: (query) =>
              widget.viewModel.skillCandidates(query: query),
          onSelect: _selectSkillFromPicker,
          onRequestClose: _skillPopoverController.dismiss,
        ),
      );
    } finally {
      _skillPickerOpening = false;
    }
  }

  Future<void> _showSlashCommandPicker() async {
    if (!_canOpenSlashMenu ||
        _slashPickerOpen ||
        _slashPickerOpening ||
        !mounted) {
      return;
    }
    if (_composerAnchorKey.currentContext == null) {
      return;
    }
    _slashPickerOpening = true;
    try {
      // Skills 分区存在时尽量预热目录，避免空列表误导。
      if (widget.viewModel.canUseSkills) {
        try {
          await widget.viewModel.ensureSkillsCatalog();
        } catch (_) {
          // 目录失败时仍展示菜单；Skills 可为空，命令仍可用。
        }
      }
      if (!mounted || _slashPickerOpen) {
        return;
      }
      final openContext = _composerAnchorKey.currentContext;
      if (openContext == null || !openContext.mounted) {
        return;
      }
      _slashPopoverController.show(
        context: openContext,
        preferredWidth: _agentSlashCommandPickerPreferredWidth,
        preferredMaxHeight: _agentSlashCommandPickerPreferredMaxHeight,
        key: const ValueKey('agent-slash-command-picker-overlay'),
        builder: (context, layout) => _AgentSlashCommandPickerPopover(
          width: layout.width,
          maxHeight: layout.maxHeight,
          documentController: _inputController,
          listController: _slashMenuListController,
          showPlanCommand: _hasSlashPlanCommand,
          showCompactCommand: widget.viewModel.canCompactCurrentThread,
          planSelected:
              widget.viewModel.selectedConversationMode ==
              AgentConversationModeId.plan,
          skillCandidatesFor: (query) => widget.viewModel.canUseSkills
              ? widget.viewModel.skillCandidates(query: query)
              : const <AgentSkillMetadata>[],
          onSelectCommand: _selectSlashCommand,
          onSelectSkill: _selectSkillFromSlashMenu,
          onRequestClose: _slashPopoverController.dismiss,
        ),
      );
    } finally {
      _slashPickerOpening = false;
    }
  }

  /// 选中 @-mention 候选后插入并关闭弹层。
  void _selectMentionFromPicker(WorkspaceNode file) {
    _mentionPopoverController.dismiss();
    _insertMention(file);
  }

  Future<void> _showMentionFilePicker() async {
    if (!widget.viewModel.canMentionResources ||
        _mentionPickerOpen ||
        _mentionPickerOpening ||
        !mounted) {
      return;
    }
    if (_composerAnchorKey.currentContext == null) {
      return;
    }
    _mentionPickerOpening = true;
    try {
      if (!mounted || _mentionPickerOpen) {
        return;
      }
      final openContext = _composerAnchorKey.currentContext;
      if (openContext == null || !openContext.mounted) {
        return;
      }
      _mentionPopoverController.show(
        context: openContext,
        preferredWidth: _agentMentionFilePickerPreferredWidth,
        preferredMaxHeight: _agentMentionFilePickerPreferredMaxHeight,
        key: const ValueKey('agent-mention-picker-overlay'),
        builder: (context, layout) => _AgentMentionFilePickerPopover(
          width: layout.width,
          maxHeight: layout.maxHeight,
          documentController: _inputController,
          listController: _mentionFileListController,
          candidatesFor: (query) =>
              widget.viewModel.mentionCandidateFiles(query: query),
          filesListenable: widget.viewModel.workspaceFilesListenable,
          isIndexReady: () => widget.viewModel.isWorkspaceFileIndexReady,
          onSelect: _selectMentionFromPicker,
          onRequestClose: _mentionPopoverController.dismiss,
        ),
      );
    } finally {
      _mentionPickerOpening = false;
    }
  }

  /// More actions → Mention file：确保进入 `@query` 后再弹出列表。
  void _openMentionPickerFromMenu() {
    if (!widget.viewModel.canMentionResources ||
        _mentionPickerOpen ||
        _mentionPickerOpening) {
      return;
    }
    // 先解除 `@` 自动打开，避免插入触发与本次 show 并发。
    _mentionQueryArmed = false;
    if (_slashPickerOpen) {
      _slashPopoverController.dismiss();
    }
    if (_skillPickerOpen) {
      _skillPopoverController.dismiss();
    }
    _ensureMentionQueryTrigger();
    unawaited(_showMentionFilePicker());
  }

  /// 在光标处写入 `@` 触发片段（必要时补前导空格）。
  void _ensureMentionQueryTrigger() {
    if (_inputController.activeMentionQuery != null) {
      return;
    }
    final text = _inputController.text;
    final selection = _inputController.selection;
    final cursor = selection.isValid
        ? selection.extentOffset.clamp(0, text.length)
        : text.length;
    final start = selection.isValid
        ? selection.baseOffset.clamp(0, text.length)
        : cursor;
    final left = math.min(start, cursor);
    final right = math.max(start, cursor);
    final before = text.substring(0, left);
    final after = text.substring(right);
    final needsSpace = before.isNotEmpty && !RegExp(r'\s$').hasMatch(before);
    final insert = needsSpace ? ' @' : '@';
    _inputController.value = TextEditingValue(
      text: '$before$insert$after',
      selection: TextSelection.collapsed(offset: before.length + insert.length),
      composing: TextRange.empty,
    );
  }

  /// 从工作区文件列表插入 @mention（原子 chip；光标在有效 @-token 内时替换该片段）。
  void _insertMention(WorkspaceNode file) {
    if (!widget.viewModel.canMentionResources) {
      return;
    }
    _inputController.insertMention(name: file.name, path: file.path);
    _syncCanSend();
    _composerFocusNode.requestFocus();
  }

  void _handleUiEffect(AgentUiEffect effect) {
    if (!widget.isActive || effect is! AgentRequestAutoScroll) {
      return;
    }
    _scrollCoordinator.notifyContentChanged(lastItemId: _lastTimelineItemId);
    _notifyScrollChrome();
  }

  void _handleScrollChanged() {
    // 用户意图主要由 ScrollNotification 分发；此处刷新 chrome。
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

class _AgentReadOnlyNotice extends StatelessWidget {
  const _AgentReadOnlyNotice({required this.pagePadding});

  final EdgeInsets pagePadding;

  @override
  Widget build(BuildContext context) {
    final textStyles = IdeTextStyles.of(context);
    final colors = IdeColors.of(context);
    return _AgentContentAlign(
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
