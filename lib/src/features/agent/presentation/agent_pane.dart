import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/features/agent/application/agent_conversation_mode_controller.dart';
import 'package:zeta/src/features/agent/application/agent_ui_update_request.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';
import 'package:zeta/src/ui/core/ide_tabs.dart';
import 'package:zeta/src/ui/core/ide_collapsible_card.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_context_menu.dart';
import 'package:zeta/src/ui/core/ide_dialog.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_motion.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_popover.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_status_card.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/layout/ide_constraint_bucket_builder.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/ui/core/surfaces/ide_surface.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_ui_state.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_extent_descriptor.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_grouping.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_projection.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_projection_cache.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_virtualization_flag.dart';
import 'package:zeta/src/features/agent/presentation/model_config_ui_state.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_provider_icon.dart';
import 'package:zeta/src/ui/core/virtualization/ide_dynamic_sliver_list.dart';
import 'package:zeta/src/ui/core/virtualization/ide_virtual_item.dart';
import 'package:zeta/src/ui/core/virtualization/ide_virtual_list_controller.dart';
import 'package:zeta/src/ui/core/virtualization/ide_virtual_scroll_coordinator.dart';
import 'package:zeta/src/ui/core/virtualization/ide_virtual_scrollbar.dart';

part 'widgets/agent_pane_cards.dart';
part 'widgets/agent_pane_composer.dart';
part 'widgets/agent_pane_context_panel.dart';
part 'widgets/agent_pane_header.dart';
part 'widgets/agent_pane_messages.dart';
part 'widgets/agent_pane_plan_panel.dart';
part 'widgets/composer_selector_popover.dart';
part 'widgets/agent_model_config.dart';
part 'widgets/agent_mode_selector.dart';
part 'widgets/agent_pane_sections.dart';
part 'widgets/agent_pane_styles.dart';

const int _diffPreviewLineCount = 24;

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

  @override
  State<AgentPane> createState() => _AgentPaneState();
}

class _AgentPaneState extends State<AgentPane> {
  static const double _autoScrollBottomThreshold = 48;
  static const XTypeGroup _imageTypeGroup = XTypeGroup(
    label: 'Images',
    extensions: <String>['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
  );

  final TextEditingController _inputController = TextEditingController();
  late final FocusNode _composerFocusNode;
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _canSendNotifier = ValueNotifier<bool>(false);
  final List<String> _draftImagePaths = <String>[];
  final List<({String name, String path})> _draftMentions =
      <({String name, String path})>[];

  /// 旧路径 stick-to-bottom；flag 开启时由 coordinator 接管。
  ///
  /// **保留策略（阶段 5）**：至少一个发布周期内不要删除；关闭
  /// `kUseAnchoredDynamicTimelineSliver` 时仍依赖此字段与
  /// [_scrollToEndLegacy] 完成回退。
  bool _stickToBottom = true;
  late StreamSubscription<AgentUiEffect> _uiEffectSubscription;

  /// 动态高度路径：extent index + follow/free 协调器（flag 开启时使用）。
  final IdeVirtualListController _virtualListController =
      IdeVirtualListController();
  late final IdeVirtualScrollCoordinator _scrollCoordinator;
  late final IdeScrollControllerDriver _scrollDriver;

  /// 驱动滚到底部按钮可见性刷新（不触发全页 setState）。
  final ValueNotifier<int> _scrollChromeTick = ValueNotifier<int>(0);

  /// 最近一次 timeline 末项 ID，供 follow reveal 使用。
  String? _lastTimelineItemId;

  /// Agent 主列最近一次有限高度；供 pending dock 计算 maxHeight。
  ///
  /// 在 width-bucket 的 [selectBucket] 中更新，不进入 bucket 身份，因此纵向
  /// 尺寸变化不会使对话结构缓存失效。结构重建时会读到最新值。
  double _panelHeight = 600;

  /// presentation 层 turn projection 缓存；不随窗口 constraints 失效。
  final AgentTimelineProjectionCache _projectionCache =
      AgentTimelineProjectionCache();

  /// extent descriptor 复用缓存（流式仅重建尾部脏项）。
  final AgentTimelineExtentDescriptorFactory _descriptorFactory =
      AgentTimelineExtentDescriptorFactory();
  late Widget Function(BuildContext, _AgentPaneWidthClass)
  _responsiveBodyBuilder;

  @override
  void initState() {
    super.initState();
    _composerFocusNode = FocusNode(
      debugLabel: 'AgentMessageComposer',
      onKeyEvent: _handleComposerKeyEvent,
    );
    _responsiveBodyBuilder = _createResponsiveBodyBuilder();
    _inputController.addListener(_handleInputChanged);
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
    _stickToBottom = true;
    _lastTimelineItemId = null;
    // 重置 coordinator：重新 attach driver 并请求 follow。
    unawaited(_scrollCoordinator.requestFollowEnd(animated: false));
    _uiEffectSubscription = widget.viewModel.uiEffects.listen(_handleUiEffect);
  }

  @override
  void dispose() {
    unawaited(_uiEffectSubscription.cancel());
    _inputController.removeListener(_handleInputChanged);
    _scrollController.removeListener(_handleScrollChanged);
    _scrollCoordinator.onModeChanged = null;
    _inputController.dispose();
    _composerFocusNode.dispose();
    _scrollController.dispose();
    _canSendNotifier.dispose();
    _scrollChromeTick.dispose();
    _projectionCache.clear();
    _descriptorFactory.clearCache();
    super.dispose();
  }

  void _notifyScrollChrome() {
    _scrollChromeTick.value += 1;
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
            child: ValueListenableBuilder<AgentHeaderState>(
              valueListenable: widget.viewModel.headerStateListenable,
              builder: (context, state, _) {
                return _AgentHeader(
                  viewModel: widget.viewModel,
                  state: state,
                  isActive: widget.isActive,
                );
              },
            ),
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: Listenable.merge(<Listenable>[
              widget.viewModel.historyStateListenable,
              widget.viewModel.liveTurnListenable,
            ]),
            builder: (context, _) {
              final historyState = widget.viewModel.historyState;
              final liveTurnState = widget.viewModel.liveTurnState;
              final hasConversation =
                  historyState.visibleTurns.isNotEmpty || liveTurnState != null;
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
                        projectionCache: _projectionCache,
                        descriptorFactory: _descriptorFactory,
                        virtualListController: _virtualListController,
                        scrollCoordinator: _scrollCoordinator,
                        scrollChromeTick: _scrollChromeTick,
                        onLastItemIdChanged: (id) {
                          _lastTimelineItemId = id;
                        },
                        onScrollToEndPressed: _requestScrollToEndFromButton,
                        useAnchoredDynamicSliver:
                            kUseAnchoredDynamicTimelineSliver,
                      ),
                floatingPanel: _AgentActivePlanSection(
                  viewModel: widget.viewModel,
                  pagePadding: pagePadding,
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
                      onPlanRevisionRequested: _composerFocusNode.requestFocus,
                    ),
                    ListenableBuilder(
                      listenable: Listenable.merge(<Listenable>[
                        widget.viewModel.composerStateListenable,
                        widget.viewModel.pendingInteractionStateListenable,
                      ]),
                      builder: (context, _) {
                        final composerState = widget.viewModel.composerState;
                        final pendingState =
                            widget.viewModel.pendingInteractionState;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (composerState.unavailableProviderReason
                                case final reason?)
                              _AgentProviderUnavailableNotice(
                                reason: reason,
                                pagePadding: pagePadding,
                              ),
                            if (composerState.isReadOnly)
                              _AgentReadOnlyNotice(pagePadding: pagePadding)
                            else if (!pendingState.blocksComposer)
                              // 提问卡 / 权限卡占用底部交互时隐藏 Composer，
                              // 与 pending dock 互斥，避免双焦点与误发送。
                              _AgentComposerSection(
                                key: const ValueKey('agent-composer-section'),
                                viewModel: widget.viewModel,
                                state: composerState,
                                inputController: _inputController,
                                composerFocusNode: _composerFocusNode,
                                canSendListenable: _canSendNotifier,
                                draftImagePaths: List<String>.unmodifiable(
                                  _draftImagePaths,
                                ),
                                pagePadding: pagePadding,
                                onAttachImages: _pickImages,
                                onRemoveImage: _removeDraftImage,
                                onSend: _sendMessage,
                                onInsertMention: _insertMention,
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              );
            },
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

  void _syncCanSend() {
    final canSend =
        _inputController.text.trim().isNotEmpty || _draftImagePaths.isNotEmpty;
    if (canSend == _canSendNotifier.value) {
      return;
    }
    _canSendNotifier.value = canSend;
  }

  KeyEventResult _handleComposerKeyEvent(FocusNode node, KeyEvent event) {
    if (!node.hasPrimaryFocus || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
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
    var changed = false;
    for (final path in paths) {
      final trimmed = path.trim();
      if (trimmed.isEmpty || _draftImagePaths.contains(trimmed)) {
        continue;
      }
      _draftImagePaths.add(trimmed);
      changed = true;
    }
    if (!changed) {
      return;
    }
    setState(() {});
    _syncCanSend();
  }

  void _removeDraftImage(String path) {
    if (!_draftImagePaths.remove(path)) {
      return;
    }
    setState(() {});
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
    final text = _inputController.text;
    final images = List<String>.from(_draftImagePaths);
    final mentions = List<({String name, String path})>.from(_draftMentions);
    if (text.trim().isEmpty && images.isEmpty && mentions.isEmpty) {
      return;
    }
    _inputController.clear();
    if (_draftImagePaths.isNotEmpty || _draftMentions.isNotEmpty) {
      setState(() {
        _draftImagePaths.clear();
        _draftMentions.clear();
      });
    }
    _syncCanSend();
    widget.viewModel.sendMessage(
      text,
      localImagePaths: images,
      mentions: mentions,
    );
  }

  /// 从工作区文件列表插入 @mention。
  void _insertMention(WorkspaceNode file) {
    if (!widget.viewModel.canMentionResources) {
      return;
    }
    final mention = (name: file.name, path: file.path);
    final text = _inputController.text;
    final selection = _inputController.selection;
    final atIndex = text.lastIndexOf(
      '@',
      selection.start > 0 ? selection.start - 1 : 0,
    );
    String nextText;
    int cursor;
    if (atIndex >= 0 &&
        (atIndex == 0 || text[atIndex - 1].trim().isEmpty) &&
        !text
            .substring(atIndex + 1, selection.start.clamp(0, text.length))
            .contains(' ')) {
      // 替换当前 @query 片段。
      nextText =
          '${text.substring(0, atIndex)}@${file.name} ${text.substring(selection.start.clamp(0, text.length))}';
      cursor = atIndex + file.name.length + 2;
    } else {
      final insertAt = selection.start.clamp(0, text.length);
      nextText =
          '${text.substring(0, insertAt)}@${file.name} ${text.substring(insertAt)}';
      cursor = insertAt + file.name.length + 2;
    }
    _inputController
      ..text = nextText
      ..selection = TextSelection.collapsed(offset: cursor);
    setState(() {
      if (!_draftMentions.any((item) => item.path == file.path)) {
        _draftMentions.add(mention);
      }
    });
    _syncCanSend();
  }

  void _handleUiEffect(AgentUiEffect effect) {
    if (!widget.isActive || effect is! AgentRequestAutoScroll) {
      return;
    }
    if (kUseAnchoredDynamicTimelineSliver) {
      // 新路径：只通知 coordinator，由 frame-coalesce 的 jump 完成 follow。
      _scrollCoordinator.onAutoScrollTick(lastItemId: _lastTimelineItemId);
      _notifyScrollChrome();
      return;
    }
    // 旧路径回退。
    if (_shouldStickToBottom()) {
      _scrollToEndLegacy();
    }
  }

  void _handleScrollChanged() {
    if (kUseAnchoredDynamicTimelineSliver) {
      // 用户意图主要由 ScrollNotification 分发；此处刷新 chrome。
      if (!_scrollCoordinator.isProgrammatic) {
        final metrics = _currentScrollMetrics();
        if (metrics != null) {
          _scrollCoordinator.onUserScroll(metrics);
        }
      }
      _notifyScrollChrome();
      return;
    }
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

  /// flag 关闭时的旧 stick-to-bottom 滚底实现。
  ///
  /// 新路径请使用 [_scrollCoordinator.onAutoScrollTick] /
  /// [requestFollowEnd]。本方法保留用于 A/B 回退，勿在 flag 存在期间删除。
  void _scrollToEndLegacy() {
    // 新消息/工具卡出现后自动滚到底部，但不阻塞当前 build。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      if (MediaQuery.disableAnimationsOf(context)) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _requestScrollToEndFromButton() {
    return _scrollCoordinator.requestFollowEnd(
      lastItemId: _lastTimelineItemId,
      animated: !MediaQuery.disableAnimationsOf(context),
    );
  }
}

class _AgentProviderUnavailableNotice extends StatelessWidget {
  const _AgentProviderUnavailableNotice({
    required this.reason,
    required this.pagePadding,
  });

  final String reason;
  final EdgeInsets pagePadding;

  @override
  Widget build(BuildContext context) {
    final textStyles = IdeTextStyles.of(context);
    final colors = IdeColors.of(context);
    return _AgentContentAlign(
      child: Padding(
        padding: pagePadding.copyWith(top: IdeSpacing.space8),
        child: IdeStatusCard(
          key: const ValueKey('agent-provider-unavailable-notice'),
          tone: IdeStatusCardTone.warning,
          title: 'Cursor Agent unavailable',
          margin: EdgeInsets.zero,
          body: Text(
            reason,
            style: textStyles.bodySmall.copyWith(color: colors.textSecondary),
          ),
        ),
      ),
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
          title: '此会话为只读模式',
          margin: EdgeInsets.zero,
          body: Text(
            '该会话所属的 Agent 已被禁用。你仍可查看历史数据，但不能继续发送消息。',
            style: textStyles.bodySmall.copyWith(color: colors.textSecondary),
          ),
        ),
      ),
    );
  }
}
