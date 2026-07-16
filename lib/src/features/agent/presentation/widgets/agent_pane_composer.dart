part of '../agent_pane.dart';

/// 底部输入面板。
///
/// 上半部分是多行输入框，下半部分是操作行：左侧通过一个模型配置入口渐进
/// 展示模型、思考程度和 Fast，右侧放发送/取消按钮。
class _AgentComposer extends StatelessWidget {
  static const double _compactToolbarBreakpoint = 560;

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
    required this.onPasteImages,
    required this.onSend,
    required this.onCancel,
    required this.showImageAttachment,
    required this.showResourceMention,
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
  final Future<bool> Function() onPasteImages;
  final VoidCallback onSend;
  final VoidCallback onCancel;
  final bool showImageAttachment;
  final bool showResourceMention;
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
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }
        final isPaste =
            (HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed) &&
            event.logicalKey == LogicalKeyboardKey.keyV;
        if (!isPaste) {
          return KeyEventResult.ignored;
        }
        // 拦截默认粘贴：优先图片，否则手动插入文本，避免图文重复粘贴。
        onPasteImages();
        return KeyEventResult.handled;
      },
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final brightness = sf.Theme.of(context).brightness;
          final isFocused = focusNode.hasFocus;
          // 焦点是键盘状态而非高度：用无方向的 ring，而不是下坠投影。
          final cardBorder = isFocused ? colors.focusRing : colors.border;
          final focusRing = isFocused
              ? IdeEffects.focusRing(brightness, accent: colors.focusRing)
              : const <BoxShadow>[];

          return AnimatedContainer(
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
                                  border: Border.fromBorderSide(
                                    BorderSide.none,
                                  ),
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
                                  onSubmitted: (_) {
                                    if (canSubmit) {
                                      onSend();
                                    }
                                  },
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
                    // 宽窗保持一行工具栏；空间不足时，将低频选择器收进可横滑的第二行。
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final attachmentActions = _buildAttachmentActions(
                          context,
                        );
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
                        final useCompactToolbar =
                            constraints.maxWidth < _compactToolbarBreakpoint;

                        if (useCompactToolbar) {
                          return Column(
                            key: const ValueKey(
                              'agent-composer-compact-toolbar',
                            ),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  attachmentActions,
                                  const Spacer(),
                                  if (tokenUsage case final Widget usage) usage,
                                  submitAction,
                                ],
                              ),
                              if (selectorControls.isNotEmpty) ...[
                                const SizedBox(height: IdeSpacing.space6),
                                SingleChildScrollView(
                                  key: const ValueKey(
                                    'agent-composer-selector-scroll',
                                  ),
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: selectorControls,
                                  ),
                                ),
                              ],
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            attachmentActions,
                            if (selectorControls.isNotEmpty) ...[
                              const SizedBox(width: IdeSpacing.space4),
                              ...selectorControls,
                            ],
                            const Spacer(),
                            if (tokenUsage case final Widget usage)
                              Flexible(
                                fit: FlexFit.loose,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: usage,
                                ),
                              ),
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
        },
      ),
    );
  }

  Widget _buildAttachmentActions(BuildContext context) {
    final colors = IdeColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showResourceMention)
          IdeTooltip(
            message: 'Mention file',
            child: sf.IconButton.ghost(
              key: const ValueKey('agent-mention-file-button'),
              onPressed: () => _showMentionPicker(context),
              size: sf.ButtonSize.small,
              density: sf.ButtonDensity.iconDense,
              icon: Icon(
                Icons.alternate_email_rounded,
                size: 16,
                color: colors.textSecondary,
              ),
            ),
          ),
        if (showResourceMention && showImageAttachment)
          const SizedBox(width: IdeSpacing.space4),
        if (showImageAttachment)
          IdeTooltip(
            message: 'Attach image',
            child: sf.IconButton.ghost(
              key: const ValueKey('agent-attach-image-button'),
              onPressed: onAttachImages,
              size: sf.ButtonSize.small,
              density: sf.ButtonDensity.iconDense,
              icon: Icon(
                Icons.image_outlined,
                size: 16,
                color: colors.textSecondary,
              ),
            ),
          ),
      ],
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
  IdePopoverHandle<void>? _popoverEntry;

  @override
  void dispose() {
    _popoverEntry?.dismiss();
    super.dispose();
  }

  void _toggleMenu() {
    if (_popoverEntry != null) {
      _dismissMenu();
      return;
    }
    _showMenu();
  }

  void _showMenu() {
    if (_popoverEntry != null || widget.options.isEmpty) {
      return;
    }
    final entry = showIdePopover<void>(
      context: context,
      alignment: Alignment.topLeft,
      anchorAlignment: Alignment.bottomLeft,
      widthConstraint: IdePopoverConstraint.intrinsic,
      offset: const Offset(0, 6),
      builder: (context) {
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280, maxHeight: 320),
          child: sf.Data.inherit(
            data: sf.SelectData(
              autoClose: true,
              hasSelection: widget.value != null,
              enabled: true,
              isSelected: (value) => value == widget.value,
              onChanged: (value, selected) {
                if (!selected || value is! T) {
                  return false;
                }
                widget.onChanged(value);
                return true;
              },
            ),
            child: sf.SelectPopup.noVirtualization(
              items: sf.SelectItemList(children: widget.options),
            ),
          ),
        );
      },
    );
    _popoverEntry = entry;
    setState(() {});
    entry.future.whenComplete(() {
      if (!mounted || !identical(_popoverEntry, entry)) {
        return;
      }
      setState(() {
        _popoverEntry = null;
      });
    });
  }

  void _dismissMenu() {
    final entry = _popoverEntry;
    if (entry == null) {
      return;
    }
    _popoverEntry = null;
    setState(() {});
    entry.dismiss();
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
        label: label,
        leadingIcon: widget.icon,
        selected: _popoverEntry != null,
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
  IdePopoverHandle<void>? _popoverEntry;

  @override
  void dispose() {
    _popoverEntry?.dismiss();
    _triggerFocusNode.dispose();
    super.dispose();
  }

  void _togglePopover() {
    if (_popoverEntry != null) {
      _popoverEntry!.dismiss();
      return;
    }
    _showPopover();
  }

  void _showPopover() {
    if (_popoverEntry != null || widget.presets.isEmpty) {
      return;
    }
    final mediaQuery = MediaQuery.of(context);
    final viewport = mediaQuery.size;
    final renderBox = context.findRenderObject() as RenderBox?;
    final origin = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final triggerHeight = renderBox?.size.height ?? 28;
    final spaceAbove = origin.dy;
    final spaceBelow = viewport.height - origin.dy - triggerHeight;
    final openAbove = spaceAbove > spaceBelow && spaceBelow < 180;
    final availablePopoverHeight =
        (openAbove ? spaceAbove : spaceBelow) -
        IdeSpacing.space6 -
        IdeSpacing.space12;
    final width = math.max(
      1.0,
      math.min(_composerSelectorPopoverPreferredWidth, viewport.width - 24),
    );
    final maxHeight = math.max(
      1.0,
      math.min(_composerSelectorPopoverMaxHeight, availablePopoverHeight),
    );
    final reduceMotion = mediaQuery.disableAnimations;

    final entry = showIdePopover<void>(
      context: context,
      alignment: openAbove ? Alignment.bottomLeft : Alignment.topLeft,
      anchorAlignment: openAbove ? Alignment.topLeft : Alignment.bottomLeft,
      widthConstraint: IdePopoverConstraint.intrinsic,
      heightConstraint: IdePopoverConstraint.flexible,
      offset: Offset(0, openAbove ? -6 : 6),
      margin: const EdgeInsets.all(IdeSpacing.space12),
      allowInvertVertical: false,
      showDuration: reduceMotion
          ? const Duration(milliseconds: 80)
          : IdeMotion.durationFast,
      dismissDuration: reduceMotion
          ? const Duration(milliseconds: 80)
          : IdeMotion.durationFast,
      builder: (context) => _PermissionPolicyPopover(
        width: width,
        maxHeight: maxHeight,
        presets: widget.presets,
        selectedPresetId: widget.selectedPresetId,
        onSelect: _selectPreset,
        onDismiss: () => _popoverEntry?.dismiss(),
      ),
    );
    _popoverEntry = entry;
    setState(() {});
    entry.future.whenComplete(() {
      if (!mounted || !identical(_popoverEntry, entry)) {
        return;
      }
      _popoverEntry = null;
      setState(() {});
      _triggerFocusNode.requestFocus();
    });
  }

  void _selectPreset(AgentPermissionPreset preset) {
    widget.onSelect(preset);
    _popoverEntry?.dismiss();
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
    final open = _popoverEntry != null;
    final displayLabel = _displayLabel;
    return _ComposerSelectorTrigger(
      surfaceKey: const ValueKey('agent-permission-policy-selector'),
      tooltip: 'Approval & sandbox',
      semanticLabel: '$displayLabel，工作目录权限',
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
    required this.onDismiss,
  });

  final double width;
  final double maxHeight;
  final List<AgentPermissionPreset> presets;
  final String? selectedPresetId;
  final ValueChanged<AgentPermissionPreset> onSelect;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          onDismiss();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: '工作目录权限',
        child: SizedBox(
          key: const ValueKey('agent-permission-policy-popover'),
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: _ComposerSelectorPanel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 28,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: IdeSpacing.space8,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '工作目录权限',
                          style: IdeTextStyles.of(context).bodySmall.copyWith(
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
                  Flexible(
                    child: ListView.builder(
                      key: const ValueKey('agent-permission-policy-list'),
                      shrinkWrap: true,
                      padding: IdeSpacing.all4,
                      itemCount: presets.length,
                      itemBuilder: (context, index) {
                        final preset = presets[index];
                        return _PermissionPolicyOption(
                          preset: preset,
                          selected: preset.id == selectedPresetId,
                          onPressed: () => onSelect(preset),
                        );
                      },
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

class _PermissionPolicyOption extends StatelessWidget {
  const _PermissionPolicyOption({
    required this.preset,
    required this.selected,
    required this.onPressed,
  });

  final AgentPermissionPreset preset;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return PaneInteractiveSurface(
      key: ValueKey<String>('agent-permission-preset-${preset.id}'),
      onPressed: onPressed,
      selected: selected,
      autofocus: selected,
      height: _composerSelectorRowHeight,
      padding: const EdgeInsets.symmetric(horizontal: IdeSpacing.space8),
      borderRadius: IdeRadius.allSmall,
      selectedBackgroundColor: colors.border.withValues(alpha: 0.2),
      focusBorderColor: colors.focusRing,
      semanticLabel: '${preset.label}${selected ? '，已选择' : ''}',
      child: Row(
        children: [
          SizedBox(
            width: 14,
            child: selected
                ? Icon(Icons.check_rounded, size: 14, color: colors.accent)
                : null,
          ),
          const SizedBox(width: IdeSpacing.space6),
          Expanded(
            child: Text(
              preset.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: IdeTextStyles.of(context).bodySmall.copyWith(
                color: colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
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
