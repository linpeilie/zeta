part of '../agent_pane.dart';

/// 底部输入面板。
///
/// 上半部分是多行输入框，下半部分是操作行：左侧通过“更多操作”菜单承载文件、
/// 图片和 Plan 快捷入口，并渐进展示模型、思考程度和 Fast，右侧放发送/取消按钮。
class _AgentComposer extends StatelessWidget {
  const _AgentComposer({
    required this.controller,
    required this.focusNode,
    required this.canSubmit,
    required this.isTurnRunning,
    required this.threadOpenPhase,
    required this.currentWindowTokenUsage,
    required this.draftImagePaths,
    required this.onAttachImages,
    required this.onRemoveImage,
    required this.onSend,
    required this.onCancel,
    required this.showImageAttachment,
    required this.showResourceMention,
    required this.conversationModeStatus,
    required this.conversationModeOptions,
    required this.selectedConversationMode,
    required this.conversationModeAppliesToNextTurn,
    required this.conversationModeStatusMessage,
    required this.conversationModeContextId,
    required this.onSelectConversationMode,
    required this.showModelSelection,
    required this.modelConfigState,
    required this.showPermissionPolicy,
    required this.permissionPolicyLabel,
    required this.permissionPresets,
    required this.selectedPermissionPresetId,
    required this.sessionConfigOptions,
    required this.onSelectModel,
    required this.onSelectReasoningEffort,
    required this.onSelectFastEnabled,
    required this.onResolveModelCompatibility,
    required this.onRetryModelConfiguration,
    required this.onCloseModelConfiguration,
    required this.onSelectPermissionPreset,
    required this.onSelectSessionConfigOption,
    required this.mentionCandidates,
    required this.onInsertMention,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool canSubmit;
  final bool isTurnRunning;
  final AgentThreadOpenPhase threadOpenPhase;
  final AgentTokenUsage? currentWindowTokenUsage;
  final List<String> draftImagePaths;
  final VoidCallback onAttachImages;
  final ValueChanged<String> onRemoveImage;
  final VoidCallback onSend;
  final VoidCallback onCancel;
  final bool showImageAttachment;
  final bool showResourceMention;

  /// 当前 Provider 的模式目录状态；不可用时不占用 Composer 布局。
  final AgentModeSelectorStatus conversationModeStatus;

  /// Provider 中立的可选模式目录。
  final List<AgentConversationModePreset> conversationModeOptions;

  /// 用户为下一新 turn 选择的模式。
  final AgentConversationModeId? selectedConversationMode;

  /// 当前选择是否只在下一新 turn 生效。
  final bool conversationModeAppliesToNextTurn;

  /// 加载、错误或只读模式的简短提示。
  final String? conversationModeStatusMessage;

  /// Provider/thread 切换时用于关闭旧模式浮层的稳定上下文标识。
  final Object conversationModeContextId;

  /// 用户选择模式后的单次回调。
  final ValueChanged<AgentConversationModeId> onSelectConversationMode;

  final bool showModelSelection;

  final AgentModelConfigUiState modelConfigState;

  /// 是否显示审批/沙箱策略按钮。
  final bool showPermissionPolicy;

  /// 策略按钮展示文案。
  final String permissionPolicyLabel;

  /// 可选策略预设。
  final List<AgentPermissionPreset> permissionPresets;

  /// 当前匹配的预设 id。
  final String? selectedPermissionPresetId;

  /// 当前 session 由 provider 动态下发的配置项。
  final List<AgentSessionConfigOption> sessionConfigOptions;

  final Future<bool> Function(String modelId) onSelectModel;
  final Future<bool> Function(String? effort) onSelectReasoningEffort;
  final Future<bool> Function(bool enabled) onSelectFastEnabled;
  final Future<bool> Function() onResolveModelCompatibility;
  final Future<bool> Function() onRetryModelConfiguration;
  final VoidCallback onCloseModelConfiguration;
  final ValueChanged<AgentPermissionPreset> onSelectPermissionPreset;
  final void Function(String configId, Object value)
  onSelectSessionConfigOption;

  /// @mention 候选文件查询。
  final List<WorkspaceNode> Function({String query}) mentionCandidates;

  /// 选中 mention 文件后的回调。
  final ValueChanged<WorkspaceNode> onInsertMention;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final inputTextStyle = textStyles.bodyMedium.copyWith(
      color: colors.textPrimary,
    );
    final lineHeight =
        (inputTextStyle.fontSize ?? 12) * (inputTextStyle.height ?? 1.35);
    final minTextAreaHeight = lineHeight * 3;
    final maxTextAreaHeight = lineHeight * 10;
    final hasDraft =
        controller.text.trim().isNotEmpty || draftImagePaths.isNotEmpty;
    final showSend =
        threadOpenPhase == AgentThreadOpenPhase.idle &&
        (!isTurnRunning || (hasDraft && canSubmit));
    final showCancel =
        threadOpenPhase == AgentThreadOpenPhase.idle &&
        isTurnRunning &&
        !showSend;
    final contextWindowTokenTooltip = _contextWindowTokenUsageTooltip(
      currentWindowTokenUsage,
    );
    final contextWindowTokenProgress = _contextWindowTokenUsageProgressValue(
      currentWindowTokenUsage,
    );
    final selectorControls = <Widget>[];
    void addSelector(Widget control) {
      if (selectorControls.isNotEmpty) {
        selectorControls.add(const SizedBox(width: IdeSpacing.space6));
      }
      selectorControls.add(control);
    }

    if (conversationModeStatus != AgentModeSelectorStatus.unavailable) {
      addSelector(
        AgentModeSelector(
          status: conversationModeStatus,
          presets: conversationModeOptions,
          selectedMode: selectedConversationMode,
          appliesToNextTurn: conversationModeAppliesToNextTurn,
          statusMessage: conversationModeStatusMessage,
          contextId: conversationModeContextId,
          onChanged: onSelectConversationMode,
        ),
      );
    }
    for (final option in sessionConfigOptions) {
      addSelector(
        _SessionConfigOptionControl(
          option: option,
          onSelect: (value) => onSelectSessionConfigOption(option.id, value),
        ),
      );
    }
    if (showModelSelection &&
        (modelConfigState.models.isNotEmpty || modelConfigState.isRefreshing)) {
      addSelector(
        _AgentModelConfig(
          state: modelConfigState,
          onSelectModel: onSelectModel,
          onSelectReasoningEffort: onSelectReasoningEffort,
          onSelectFastEnabled: onSelectFastEnabled,
          onResolveCompatibility: onResolveModelCompatibility,
          onRetrySave: onRetryModelConfiguration,
          onPopoverClosed: onCloseModelConfiguration,
        ),
      );
    }
    if (showPermissionPolicy) {
      addSelector(
        _PermissionPolicyButton(
          label: permissionPolicyLabel,
          presets: permissionPresets,
          selectedPresetId: selectedPermissionPresetId,
          onSelect: onSelectPermissionPreset,
        ),
      );
    }
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) {
        final brightness = sf.Theme.of(context).brightness;
        final isFocused = focusNode.hasFocus;
        // 焦点是键盘状态而非高度：用无方向的 ring，而不是下坠投影。
        final cardBorder = isFocused ? colors.focusRing : colors.border;
        final focusRing = isFocused
            ? IdeEffects.focusRing(brightness, accent: colors.focusRing)
            : const <BoxShadow>[];

        final composer = AnimatedContainer(
          key: const ValueKey('agent-composer-focus-ring'),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : IdeMotion.durationNormal,
          curve: IdeMotion.curveDefault,
          decoration: BoxDecoration(
            borderRadius: IdeRadius.allMedium,
            boxShadow: focusRing,
          ),
          child: PanelCard(
            color: colors.panel,
            borderColor: cardBorder,
            borderRadius: IdeRadius.allMedium,
            showBorder: true,
            child: Padding(
              padding: IdeSpacing.composerPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (draftImagePaths.isNotEmpty) ...[
                    _ComposerImageDraftStrip(
                      paths: draftImagePaths,
                      onRemove: onRemoveImage,
                    ),
                    const SizedBox(height: IdeSpacing.space8),
                  ],
                  Stack(
                    children: [
                      ListenableBuilder(
                        listenable: controller,
                        builder: (context, _) {
                          // key 挂在外层：sf.TextArea.copyWith 会把同一 key
                          // 传给内部 TextField，直接挂在 TextArea 上会导致测试
                          // find.byKey 命中两个 widget。
                          return KeyedSubtree(
                            key: const ValueKey('agent-message-input'),
                            // 关掉 TextArea 默认 FocusOutline，避免焦点环割裂卡片。
                            child: sf.ComponentTheme<sf.FocusOutlineTheme>(
                              data: const sf.FocusOutlineTheme(
                                border: Border.fromBorderSide(BorderSide.none),
                              ),
                              child: sf.TextArea(
                                controller: controller,
                                focusNode: focusNode,
                                placeholder: Text(
                                  'Message Agent',
                                  style: textStyles.bodyMedium.copyWith(
                                    color: colors.textTertiary,
                                  ),
                                ),
                                style: inputTextStyle,
                                padding: EdgeInsets.zero,
                                // 显式 decoration：底色跟 PanelCard 一致，无独立边框。
                                decoration: BoxDecoration(
                                  color: colors.panel,
                                  border: const Border.fromBorderSide(
                                    BorderSide.none,
                                  ),
                                  borderRadius: BorderRadius.zero,
                                ),
                                initialHeight: _textAreaHeight(
                                  controller.text,
                                  lineHeight,
                                  minTextAreaHeight,
                                  maxTextAreaHeight,
                                ),
                                minHeight: minTextAreaHeight,
                                maxHeight: maxTextAreaHeight,
                              ),
                            ),
                          );
                        },
                      ),
                      // `sf.TextArea` 当前总会绘制右下拖拽角；composer 不支持手动缩放，
                      // 这里用面板底色遮掉，避免视觉回归。
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: ColoredBox(
                            color: colors.panel,
                            child: const SizedBox(width: 12, height: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: IdeSpacing.space6),
                  // 工具栏始终保持单行；空间不足时裁切右侧选择器，不移动已有控件。
                  Builder(
                    builder: (context) {
                      final moreActions = _buildMoreActions(context);
                      final submitAction = _buildSubmitAction(
                        context,
                        showCancel: showCancel,
                        showSend: showSend,
                      );
                      final tokenUsage = contextWindowTokenProgress == null
                          ? null
                          : Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: IdeSpacing.space8,
                              ),
                              child: _ComposerContextWindowUsage(
                                tooltip: contextWindowTokenTooltip,
                                progress: contextWindowTokenProgress,
                              ),
                            );

                      return Row(
                        key: const ValueKey('agent-composer-toolbar'),
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          moreActions,
                          if (selectorControls.isNotEmpty) ...[
                            const SizedBox(width: IdeSpacing.space4),
                            Expanded(
                              child: SizedBox(
                                height: 28,
                                child: ClipRect(
                                  key: const ValueKey(
                                    'agent-composer-selectors',
                                  ),
                                  child: OverflowBox(
                                    alignment: Alignment.centerLeft,
                                    maxWidth: double.infinity,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: selectorControls,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ] else
                            const Spacer(),
                          if (tokenUsage case final Widget usage) usage,
                          submitAction,
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
        return _ComposerRunningGlowBorder(
          active: isTurnRunning,
          color: colors.focusRing,
          brightness: brightness,
          child: composer,
        );
      },
    );
  }

  Widget _buildMoreActions(BuildContext context) {
    final showPlan =
        conversationModeStatus == AgentModeSelectorStatus.ready &&
        conversationModeOptions.any(
          (preset) =>
              preset.id == AgentConversationModeId.plan && preset.isSelectable,
        );
    return _ComposerMoreActionsButton(
      showPlan: showPlan,
      planSelected: selectedConversationMode == AgentConversationModeId.plan,
      showMentionFile: showResourceMention,
      showAttachImage: showImageAttachment,
      contextId: conversationModeContextId,
      onSelectPlan: () =>
          onSelectConversationMode(AgentConversationModeId.plan),
      onMentionFile: () => _showMentionPicker(context),
      onAttachImage: onAttachImages,
    );
  }

  Widget _buildSubmitAction(
    BuildContext context, {
    required bool showCancel,
    required bool showSend,
  }) {
    final colors = IdeColors.of(context);
    return AnimatedSwitcher(
      duration: IdeMotion.durationNormal,
      switchInCurve: IdeMotion.curveDefault,
      switchOutCurve: IdeMotion.curveDefault,
      layoutBuilder: (currentChild, previousChildren) =>
          currentChild ?? const SizedBox.shrink(),
      child: showCancel
          ? _ComposerActionButton(
              key: const ValueKey('agent-cancel-button-state'),
              tooltip: 'Cancel',
              backgroundColor: colors.border.withValues(alpha: 0.36),
              foregroundColor: colors.textSecondary,
              buttonKey: const ValueKey('agent-cancel-button'),
              icon: const Icon(Icons.stop_rounded, size: 22),
              onPressed: onCancel,
            )
          : showSend
          ? _ComposerActionButton(
              key: const ValueKey('agent-send-button-state'),
              tooltip: 'Send',
              // 可发送时使用实心 accent，作为界面最强的行动锚点；不可发送时退回弱化中性底。
              backgroundColor: canSubmit
                  ? colors.accent
                  : colors.border.withValues(alpha: 0.2),
              foregroundColor: canSubmit
                  ? Colors.white
                  : colors.textSecondary.withValues(alpha: 0.72),
              filled: canSubmit,
              buttonKey: const ValueKey('agent-send-button'),
              icon: const Icon(Icons.arrow_upward_rounded, size: 22),
              onPressed: canSubmit ? onSend : null,
            )
          : const SizedBox(
              key: ValueKey('agent-send-unavailable-placeholder'),
              width: 40,
              height: 40,
            ),
    );
  }

  double _textAreaHeight(
    String text,
    double lineHeight,
    double minHeight,
    double maxHeight,
  ) {
    final lineCount = text.trim().isEmpty ? 3 : LineSplitter.split(text).length;
    final visibleLines = lineCount.clamp(3, 10);
    final desiredHeight = (visibleLines * lineHeight) + 8;
    return desiredHeight.clamp(minHeight, maxHeight).toDouble();
  }

  Future<void> _showMentionPicker(BuildContext context) async {
    final files = mentionCandidates();
    if (files.isEmpty) {
      return;
    }
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    await showIdeDialog<void>(
      context: context,
      builder: (dialogContext) {
        return IdeDialog(
          title: const Text('Mention file'),
          content: SizedBox(
            width: 360,
            height: 280,
            child: ListView.builder(
              itemCount: files.length,
              itemBuilder: (context, index) {
                final file = files[index];
                return PaneInteractiveSurface(
                  key: ValueKey('agent-mention-option-${file.path}'),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    onInsertMention(file);
                  },
                  child: Padding(
                    padding: IdeSpacing.all8,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textStyles.bodyMedium.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          file.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textStyles.bodySmall.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Composer 左下角的能力感知“更多操作”菜单。
class _ComposerMoreActionsButton extends StatefulWidget {
  const _ComposerMoreActionsButton({
    required this.showPlan,
    required this.planSelected,
    required this.showMentionFile,
    required this.showAttachImage,
    required this.contextId,
    required this.onSelectPlan,
    required this.onMentionFile,
    required this.onAttachImage,
  });

  final bool showPlan;
  final bool planSelected;
  final bool showMentionFile;
  final bool showAttachImage;
  final Object contextId;
  final VoidCallback onSelectPlan;
  final VoidCallback onMentionFile;
  final VoidCallback onAttachImage;

  @override
  State<_ComposerMoreActionsButton> createState() =>
      _ComposerMoreActionsButtonState();
}

class _ComposerMoreActionsButtonState
    extends State<_ComposerMoreActionsButton> {
  static const double _preferredWidth = 196;
  static const double _maxHeight = 240;

  final FocusNode _triggerFocusNode = FocusNode(
    debugLabel: 'agent-more-actions-trigger',
  );
  IdePopoverHandle<void>? _popoverEntry;

  bool get _hasActions =>
      widget.showPlan || widget.showMentionFile || widget.showAttachImage;

  @override
  void didUpdateWidget(covariant _ComposerMoreActionsButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shouldDismiss =
        _popoverEntry != null &&
        (oldWidget.contextId != widget.contextId ||
            oldWidget.showPlan != widget.showPlan ||
            oldWidget.planSelected != widget.planSelected ||
            oldWidget.showMentionFile != widget.showMentionFile ||
            oldWidget.showAttachImage != widget.showAttachImage);
    if (!shouldDismiss) {
      return;
    }
    final entry = _popoverEntry;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_popoverEntry, entry)) {
        entry?.dismiss();
      }
    });
  }

  @override
  void dispose() {
    _popoverEntry?.dismiss();
    _triggerFocusNode.dispose();
    super.dispose();
  }

  void _togglePopover() {
    final entry = _popoverEntry;
    if (entry != null) {
      entry.dismiss();
      return;
    }
    _showPopover();
  }

  void _showPopover() {
    if (_popoverEntry != null || !_hasActions) {
      return;
    }
    final mediaQuery = MediaQuery.of(context);
    final viewport = mediaQuery.size;
    final renderBox = context.findRenderObject() as RenderBox?;
    final origin = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final availableHeight = origin.dy - IdeSpacing.space6 - IdeSpacing.space12;
    final width = math.max(
      1.0,
      math.min(_preferredWidth, viewport.width - IdeSpacing.space12 * 2),
    );
    final maxHeight = math.max(1.0, math.min(_maxHeight, availableHeight));
    final reduceMotion = mediaQuery.disableAnimations;

    final entry = showIdePopover<void>(
      context: context,
      alignment: Alignment.bottomLeft,
      anchorAlignment: Alignment.topLeft,
      widthConstraint: IdePopoverConstraint.intrinsic,
      heightConstraint: IdePopoverConstraint.flexible,
      key: const ValueKey('agent-more-actions-popover'),
      offset: const Offset(0, -IdeSpacing.space6),
      margin: const EdgeInsets.all(IdeSpacing.space12),
      allowInvertVertical: false,
      showDuration: reduceMotion
          ? const Duration(milliseconds: 80)
          : IdeMotion.durationFast,
      dismissDuration: reduceMotion
          ? const Duration(milliseconds: 80)
          : IdeMotion.durationFast,
      builder: (context) => SizedBox(
        width: width,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: IdeContextMenu(
              minWidth: width,
              closeOnActivate: false,
              actions: _buildActions(),
            ),
          ),
        ),
      ),
    );
    _popoverEntry = entry;
    setState(() {});
    unawaited(
      entry.future.whenComplete(() {
        if (!mounted || !identical(_popoverEntry, entry)) {
          return;
        }
        _popoverEntry = null;
        setState(() {});
        if (_hasActions) {
          _triggerFocusNode.requestFocus();
        }
      }),
    );
  }

  void _activateAction(VoidCallback action) {
    final entry = _popoverEntry;
    if (entry == null) {
      action();
      return;
    }
    entry.dismiss();
    unawaited(entry.future.whenComplete(action));
  }

  List<IdeContextMenuAction> _buildActions() {
    return <IdeContextMenuAction>[
      if (widget.showPlan)
        IdeContextMenuAction(
          key: const ValueKey('agent-more-actions-plan'),
          label: 'Plan',
          leadingIcon: widget.planSelected
              ? Icons.check_rounded
              : Icons.alt_route_rounded,
          semanticLabel: widget.planSelected ? 'Plan, selected' : 'Plan',
          onPressed: () => _activateAction(() {
            if (!widget.planSelected) {
              widget.onSelectPlan();
            }
          }),
        ),
      if (widget.showMentionFile)
        IdeContextMenuAction(
          key: const ValueKey('agent-mention-file-button'),
          label: 'Mention file',
          leadingIcon: Icons.alternate_email_rounded,
          dividerAbove: widget.showPlan,
          onPressed: () => _activateAction(widget.onMentionFile),
        ),
      if (widget.showAttachImage)
        IdeContextMenuAction(
          key: const ValueKey('agent-attach-image-button'),
          label: 'Attach image',
          leadingIcon: Icons.image_outlined,
          dividerAbove: widget.showPlan && !widget.showMentionFile,
          onPressed: () => _activateAction(widget.onAttachImage),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasActions) {
      return const SizedBox.shrink();
    }
    final colors = IdeColors.of(context);
    final open = _popoverEntry != null;
    return _ComposerSelectorTrigger(
      surfaceKey: const ValueKey('agent-more-actions-button'),
      tooltip: 'More actions',
      semanticLabel: open ? 'More actions, expanded' : 'More actions',
      open: open,
      focusNode: _triggerFocusNode,
      onPressed: _togglePopover,
      child: Icon(Icons.add_rounded, size: 18, color: colors.textSecondary),
    );
  }
}

/// 当前回合运行时覆盖在 Composer 外卡上的单色扫光边框。
///
/// 装饰层不参与布局、命中测试或语义树；系统要求减少动态效果时保留静态提示，
/// 但停止旋转。
class _ComposerRunningGlowBorder extends StatefulWidget {
  const _ComposerRunningGlowBorder({
    required this.active,
    required this.color,
    required this.brightness,
    required this.child,
  });

  final bool active;
  final Color color;
  final Brightness brightness;
  final Widget child;

  @override
  State<_ComposerRunningGlowBorder> createState() =>
      _ComposerRunningGlowBorderState();
}

class _ComposerRunningGlowBorderState extends State<_ComposerRunningGlowBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: IdeMotion.durationRunningGlow,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion != reduceMotion) {
      _reduceMotion = reduceMotion;
    }
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _ComposerRunningGlowBorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (widget.active && !_reduceMotion) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
      return;
    }
    _controller
      ..stop()
      ..value = 0;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      key: const ValueKey('agent-composer-running-glow-animation'),
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            child!,
            if (widget.active)
              Positioned.fill(
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: RepaintBoundary(
                      key: const ValueKey(
                        'agent-composer-running-glow-repaint-boundary',
                      ),
                      child: CustomPaint(
                        key: const ValueKey('agent-composer-running-glow'),
                        painter: _ComposerRunningGlowPainter(
                          progress: _controller.value,
                          color: widget.color,
                          brightness: widget.brightness,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _ComposerRunningGlowPainter extends CustomPainter {
  const _ComposerRunningGlowPainter({
    required this.progress,
    required this.color,
    required this.brightness,
  });

  final double progress;
  final Color color;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    const edgeStrokeWidth = 1.5;
    final rect = (Offset.zero & size).deflate(edgeStrokeWidth / 2);
    final border = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(IdeRadius.medium - edgeStrokeWidth / 2),
    );
    final transparent = color.withValues(alpha: 0);
    final shader = SweepGradient(
      transform: GradientRotation((progress * math.pi * 2) - (math.pi / 2)),
      colors: <Color>[
        transparent,
        transparent,
        color.withValues(alpha: 0.12),
        color.withValues(alpha: 0.94),
        color.withValues(alpha: 0.24),
        transparent,
        transparent,
      ],
      stops: const <double>[0, 0.64, 0.74, 0.82, 0.9, 0.97, 1],
    ).createShader(rect);
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = brightness == Brightness.dark ? 4 : 3
      ..shader = shader
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        brightness == Brightness.dark ? 5 : 4,
      );
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = edgeStrokeWidth
      ..shader = shader;

    canvas
      ..drawRRect(border, glowPaint)
      ..drawRRect(border, edgePaint);
  }

  @override
  bool shouldRepaint(covariant _ComposerRunningGlowPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.brightness != brightness;
  }
}

class _ComposerContextWindowUsage extends StatelessWidget {
  const _ComposerContextWindowUsage({
    required this.tooltip,
    required this.progress,
  });

  final String tooltip;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final progressColor =
        progress >= AgentConversationViewModel.contextCompactThreshold
        ? colors.warning
        : colors.accent;
    return IdeTooltip(
      message: tooltip,
      child: Semantics(
        label: 'Context window token usage',
        value: '${(progress * 100).round()}%',
        child: Row(
          key: const ValueKey('agent-composer-token-usage'),
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                key: const ValueKey('agent-composer-token-progress'),
                value: progress,
                strokeWidth: 2.2,
                backgroundColor: colors.border.withValues(alpha: 0.32),
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 输入框上方的本地图片草稿缩略图条。
class _ComposerImageDraftStrip extends StatelessWidget {
  const _ComposerImageDraftStrip({required this.paths, required this.onRemove});

  final List<String> paths;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return SizedBox(
      height: 64,
      child: ListView.separated(
        key: const ValueKey('agent-composer-image-drafts'),
        scrollDirection: Axis.horizontal,
        itemCount: paths.length,
        separatorBuilder: (_, _) => const SizedBox(width: IdeSpacing.space8),
        itemBuilder: (context, index) {
          final path = paths[index];
          return Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: IdeRadius.allSmall,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceElevated,
                    border: Border.all(color: colors.borderSubtle),
                    borderRadius: IdeRadius.allSmall,
                  ),
                  child: Image.file(
                    File(path),
                    key: ValueKey<String>('agent-composer-image-$path'),
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => SizedBox(
                      width: 64,
                      height: 64,
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 18,
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: -4,
                right: -4,
                child: sf.IconButton.ghost(
                  key: ValueKey<String>('agent-composer-remove-image-$path'),
                  onPressed: () => onRemove(path),
                  size: sf.ButtonSize.xSmall,
                  density: sf.ButtonDensity.iconDense,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SelectorSelect<T extends Object> extends StatefulWidget {
  const _SelectorSelect({
    required this.selectorKey,
    required this.tooltip,
    required this.placeholderLabel,
    required this.icon,
    required this.value,
    required this.labelBuilder,
    required this.options,
    required this.onChanged,
  });

  final Key selectorKey;
  final String tooltip;
  final String placeholderLabel;
  final IconData icon;
  final T? value;
  final String Function(T value) labelBuilder;
  final List<Widget> options;
  final ValueChanged<T> onChanged;

  @override
  State<_SelectorSelect<T>> createState() => _SelectorSelectState<T>();
}

class _SelectorSelectState<T extends Object> extends State<_SelectorSelect<T>> {
  final FocusNode _triggerFocusNode = FocusNode(
    debugLabel: 'agent-session-selector-trigger',
  );
  late final _ComposerSelectorPopoverController _popoverController;

  @override
  void initState() {
    super.initState();
    _popoverController = _ComposerSelectorPopoverController(
      triggerFocusNode: _triggerFocusNode,
      onOpenChanged: () {
        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  @override
  void didUpdateWidget(covariant _SelectorSelect<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_popoverController.isOpen &&
        (oldWidget.value != widget.value || widget.options.isEmpty)) {
      final entry = _popoverController.handle;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _popoverController.dismiss(entry);
        }
      });
    }
  }

  @override
  void dispose() {
    _popoverController.dispose();
    _triggerFocusNode.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    if (!_popoverController.isOpen && widget.options.isEmpty) {
      return;
    }
    _popoverController.toggle(
      context: context,
      preferredWidth: 280,
      preferredMaxHeight: 320,
      builder: (context, layout) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: layout.width,
            maxHeight: layout.maxHeight,
          ),
          child: _ComposerSelectPopup<T>(
            value: widget.value,
            items: widget.options,
            onChanged: (value, selected) {
              if (!selected) {
                return false;
              }
              widget.onChanged(value);
              return true;
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.value == null
        ? widget.placeholderLabel
        : widget.labelBuilder(widget.value as T);
    return IdeTooltip(
      message: widget.tooltip,
      child: IdeTab(
        key: widget.selectorKey,
        focusNode: _triggerFocusNode,
        label: label,
        leadingIcon: widget.icon,
        selected: _popoverController.isOpen,
        enabled: widget.options.isNotEmpty,
        onPressed: _toggleMenu,
        semanticLabel: widget.tooltip,
      ),
    );
  }
}

/// Provider 动态下发的 session 配置控件。
class _SessionConfigOptionControl extends StatelessWidget {
  const _SessionConfigOptionControl({
    required this.option,
    required this.onSelect,
  });

  final AgentSessionConfigOption option;
  final ValueChanged<Object> onSelect;

  @override
  Widget build(BuildContext context) {
    if (option.kind == AgentSessionConfigOptionKind.boolean) {
      final selected = option.currentValue == true;
      return IdeTooltip(
        message: option.description ?? option.name,
        child: IdeTab(
          key: ValueKey<String>('agent-session-config-${option.id}'),
          label: '${option.name}: ${selected ? 'On' : 'Off'}',
          leadingIcon: _sessionConfigIcon(option.category),
          trailingIcon: null,
          selected: selected,
          onPressed: () => onSelect(!selected),
          semanticLabel: option.name,
        ),
      );
    }
    return _SelectorSelect<Object>(
      selectorKey: ValueKey<String>('agent-session-config-${option.id}'),
      tooltip: option.description ?? option.name,
      placeholderLabel: option.name,
      icon: _sessionConfigIcon(option.category),
      value: option.currentValue,
      labelBuilder: _valueLabel,
      onChanged: onSelect,
      options: <Widget>[
        for (final value in option.values)
          sf.SelectItemButton<Object>(
            key: ValueKey<String>(
              'agent-session-config-${option.id}-option-${value.id}',
            ),
            value: value.id,
            child: Text(
              value.label,
              overflow: TextOverflow.ellipsis,
              style: IdeTextStyles.of(context).bodyMedium,
            ),
          ),
      ],
    );
  }

  String _valueLabel(Object value) {
    for (final candidate in option.values) {
      if (candidate.id == value) {
        return candidate.label;
      }
    }
    return value.toString();
  }
}

IconData _sessionConfigIcon(String? category) {
  return switch (category) {
    'model' => Icons.auto_awesome_outlined,
    'mode' => Icons.tune_rounded,
    'thought_level' => Icons.psychology_alt_outlined,
    'model_config' => Icons.settings_suggest_outlined,
    _ => Icons.tune_rounded,
  };
}

/// 审批/沙箱策略预设选择按钮。
class _PermissionPolicyButton extends StatefulWidget {
  const _PermissionPolicyButton({
    required this.label,
    required this.presets,
    required this.selectedPresetId,
    required this.onSelect,
  });

  final String label;
  final List<AgentPermissionPreset> presets;
  final String? selectedPresetId;
  final ValueChanged<AgentPermissionPreset> onSelect;

  @override
  State<_PermissionPolicyButton> createState() =>
      _PermissionPolicyButtonState();
}

class _PermissionPolicyButtonState extends State<_PermissionPolicyButton> {
  final FocusNode _triggerFocusNode = FocusNode(
    debugLabel: 'agent-permission-policy-trigger',
  );
  late final _ComposerSelectorPopoverController _popoverController;

  @override
  void initState() {
    super.initState();
    _popoverController = _ComposerSelectorPopoverController(
      triggerFocusNode: _triggerFocusNode,
      onOpenChanged: () {
        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  @override
  void didUpdateWidget(covariant _PermissionPolicyButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_popoverController.isOpen &&
        (oldWidget.selectedPresetId != widget.selectedPresetId ||
            widget.presets.isEmpty)) {
      final entry = _popoverController.handle;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _popoverController.dismiss(entry);
        }
      });
    }
  }

  @override
  void dispose() {
    _popoverController.dispose();
    _triggerFocusNode.dispose();
    super.dispose();
  }

  void _togglePopover() {
    if (!_popoverController.isOpen && widget.presets.isEmpty) {
      return;
    }
    _popoverController.toggle(
      context: context,
      preferredWidth: _composerSelectorPopoverPreferredWidth,
      preferredMaxHeight: _composerSelectorPopoverMaxHeight,
      builder: (context, layout) => _PermissionPolicyPopover(
        width: layout.width,
        maxHeight: layout.maxHeight,
        presets: widget.presets,
        selectedPresetId: widget.selectedPresetId,
        onSelect: _selectPreset,
      ),
    );
  }

  void _selectPreset(AgentPermissionPreset preset) {
    widget.onSelect(preset);
  }

  String get _displayLabel {
    for (final preset in widget.presets) {
      if (preset.id == widget.selectedPresetId) {
        return preset.label;
      }
    }
    return widget.label;
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final open = _popoverController.isOpen;
    final displayLabel = _displayLabel;
    return _ComposerSelectorTrigger(
      surfaceKey: const ValueKey('agent-permission-policy-selector'),
      tooltip: 'Approval & sandbox',
      semanticLabel: '$displayLabel，审批与沙箱',
      open: open,
      focusNode: _triggerFocusNode,
      onPressed: widget.presets.isEmpty ? null : _togglePopover,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_outlined, size: 14, color: colors.textSecondary),
          const SizedBox(width: IdeSpacing.space6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              displayLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyles.bodySmall.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: IdeSpacing.space4),
          AnimatedRotation(
            turns: open ? 0.5 : 0,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : IdeMotion.durationNormal,
            curve: IdeMotion.curveDefault,
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 13,
              color: colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionPolicyPopover extends StatelessWidget {
  const _PermissionPolicyPopover({
    required this.width,
    required this.maxHeight,
    required this.presets,
    required this.selectedPresetId,
    required this.onSelect,
  });

  final double width;
  final double maxHeight;
  final List<AgentPermissionPreset> presets;
  final String? selectedPresetId;
  final ValueChanged<AgentPermissionPreset> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final selectedPreset = presets
        .where((preset) => preset.id == selectedPresetId)
        .firstOrNull;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '审批与沙箱',
      child: SizedBox(
        key: const ValueKey('agent-permission-policy-popover'),
        width: width,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: _ComposerSelectorPanel(
            child: _ComposerSelectPopup<AgentPermissionPreset>(
              value: selectedPreset,
              onChanged: (preset, selected) {
                // 保持旧行为：点击当前预设也先通知业务层，再由 Select 关层。
                onSelect(preset);
                return true;
              },
              items: <Widget>[
                SizedBox(
                  height: 28,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: IdeSpacing.space8,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '审批与沙箱',
                        style: textStyles.bodySmall.copyWith(
                          color: colors.textTertiary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: colors.borderSubtle.withValues(alpha: 0.6),
                ),
                for (final preset in presets)
                  sf.SelectItemButton<AgentPermissionPreset>(
                    key: ValueKey<String>(
                      'agent-permission-preset-${preset.id}',
                    ),
                    value: preset,
                    child: Semantics(
                      label:
                          '${preset.label}，'
                          '${AgentPermissionSelection.approvalPolicyDisplayLabel(preset.approvalPolicy)}'
                          '${preset.id == selectedPresetId ? '，已选择' : ''}',
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            preset.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textStyles.bodySmall.copyWith(
                              color: colors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            AgentPermissionSelection.approvalPolicyDisplayLabel(
                              preset.approvalPolicy,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textStyles.bodySmall.copyWith(
                              color: colors.textTertiary,
                              fontSize: 12,
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
      ),
    );
  }
}

class _ComposerActionButton extends StatelessWidget {
  const _ComposerActionButton({
    required this.tooltip,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.buttonKey,
    required this.icon,
    required this.onPressed,
    this.filled = false,
    super.key,
  });

  final String tooltip;
  final Color backgroundColor;
  final Color foregroundColor;
  final Key buttonKey;
  final Widget icon;
  final VoidCallback? onPressed;

  /// 实心样式：hover 时保持前景色不变，仅叠加白色提亮。
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return IdeTooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
        ),
        child: ClipOval(
          child: sf.IconButton.ghost(
            key: buttonKey,
            onPressed: onPressed,
            size: sf.ButtonSize.small,
            density: sf.ButtonDensity.iconDense,
            shape: sf.ButtonShape.circle,
            disableTransition: filled,
            icon: IconTheme.merge(
              data: IconThemeData(color: foregroundColor),
              child: icon,
            ),
          ),
        ),
      ),
    );
  }
}
