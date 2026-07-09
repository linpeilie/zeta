part of '../agent_pane.dart';

/// 底部输入面板。
///
/// 上半部分是多行输入框，下半部分是操作行：左侧放模型选择、思考按钮和速率按钮，
/// 右侧放发送/取消按钮。provider 运行时发送按钮切换为取消按钮。
class _AgentComposer extends StatelessWidget {
  const _AgentComposer({
    required this.controller,
    required this.canSubmit,
    required this.isTurnRunning,
    required this.threadOpenPhase,
    required this.draftImagePaths,
    required this.onAttachImages,
    required this.onRemoveImage,
    required this.onPasteImages,
    required this.onSend,
    required this.onCancel,
    required this.models,
    required this.selectedModel,
    required this.selectedReasoningEffort,
    required this.selectedServiceTierId,
    required this.showReasoningEffort,
    required this.showServiceTier,
    required this.showPermissionPolicy,
    required this.permissionPolicyLabel,
    required this.permissionPresets,
    required this.selectedPermissionPresetId,
    required this.onSelectModel,
    required this.onSelectReasoningEffort,
    required this.onSelectServiceTier,
    required this.onSelectPermissionPreset,
    required this.mentionCandidates,
    required this.onInsertMention,
  });

  final TextEditingController controller;
  final bool canSubmit;
  final bool isTurnRunning;
  final AgentThreadOpenPhase threadOpenPhase;
  final List<String> draftImagePaths;
  final VoidCallback onAttachImages;
  final ValueChanged<String> onRemoveImage;
  final Future<bool> Function() onPasteImages;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  /// 可选模型列表。
  final List<AgentModelInfo> models;

  /// 当前选中的模型信息。
  final AgentModelInfo? selectedModel;

  /// 当前选中的推理深度档位。
  final String? selectedReasoningEffort;

  /// 当前选中的服务档位 id。
  final String? selectedServiceTierId;

  /// 是否显示思考按钮。
  final bool showReasoningEffort;

  /// 是否显示速率按钮。
  final bool showServiceTier;

  /// 是否显示审批/沙箱策略按钮。
  final bool showPermissionPolicy;

  /// 策略按钮展示文案。
  final String permissionPolicyLabel;

  /// 可选策略预设。
  final List<AgentPermissionPreset> permissionPresets;

  /// 当前匹配的预设 id。
  final String? selectedPermissionPresetId;

  final ValueChanged<String> onSelectModel;
  final ValueChanged<String?> onSelectReasoningEffort;
  final ValueChanged<String?> onSelectServiceTier;
  final ValueChanged<AgentPermissionPreset> onSelectPermissionPreset;

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
    final hasDraft =
        controller.text.trim().isNotEmpty || draftImagePaths.isNotEmpty;
    final showSend =
        threadOpenPhase == AgentThreadOpenPhase.idle &&
        (!isTurnRunning || hasDraft);
    final showCancel =
        threadOpenPhase == AgentThreadOpenPhase.idle &&
        isTurnRunning &&
        !hasDraft;
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
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          final brightness = ShadTheme.of(context).brightness;
          final focusBorder = isFocused
              ? colors.accent.withValues(alpha: 0.64)
              : colors.border.withValues(alpha: 0.6);
          final shadow = isFocused
              ? IdeEffects.composerFocusShadow(
                  brightness,
                  accent: colors.accent,
                )
              : IdeEffects.composerRestShadow(brightness);

          return AnimatedContainer(
            duration: IdeMotion.durationNormal,
            curve: IdeMotion.curveDefault,
            decoration: BoxDecoration(
              borderRadius: IdeRadius.allComposer,
              boxShadow: shadow,
            ),
            child: PanelCard(
              color: colors.panel,
              borderColor: focusBorder,
              borderRadius: IdeRadius.allComposer,
              showBorder: true,
              child: Padding(
                padding: const EdgeInsets.only(
                  left: IdeSpacing.space16,
                  top: IdeSpacing.space12,
                  right: IdeSpacing.space8,
                  bottom: IdeSpacing.space8,
                ),
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
                    ShadTextarea(
                      key: const ValueKey('agent-message-input'),
                      controller: controller,
                      placeholder: Text(
                        'Message Agent',
                        style: textStyles.bodyMedium.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                      style: inputTextStyle,
                      decoration: ShadDecoration.none,
                      padding: EdgeInsets.zero,
                      inputPadding: EdgeInsets.zero,
                      minHeight: lineHeight * 3,
                      maxHeight: lineHeight * 10,
                      resizable: false,
                      onSubmitted: (_) {
                        if (canSubmit) {
                          onSend();
                        }
                      },
                    ),
                    const SizedBox(height: IdeSpacing.space6),
                    // 下半部分：操作行，左侧放选择控件，右侧放发送按钮。
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        IdeTooltip(
                          message: 'Mention file',
                          child: ShadIconButton.ghost(
                            key: const ValueKey('agent-mention-file-button'),
                            onPressed: () => _showMentionPicker(context),
                            width: 28,
                            height: 28,
                            padding: EdgeInsets.zero,
                            foregroundColor: colors.textSecondary,
                            icon: const Icon(
                              Icons.alternate_email_rounded,
                              size: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: IdeSpacing.space4),
                        IdeTooltip(
                          message: 'Attach image',
                          child: ShadIconButton.ghost(
                            key: const ValueKey('agent-attach-image-button'),
                            onPressed: onAttachImages,
                            width: 28,
                            height: 28,
                            padding: EdgeInsets.zero,
                            foregroundColor: colors.textSecondary,
                            icon: const Icon(Icons.image_outlined, size: 16),
                          ),
                        ),
                        const SizedBox(width: IdeSpacing.space4),
                        if (models.isNotEmpty)
                          _ModelSelectorButton(
                            models: models,
                            selectedModel: selectedModel,
                            onSelect: onSelectModel,
                          ),
                        if (showReasoningEffort && selectedModel != null) ...[
                          const SizedBox(width: IdeSpacing.space6),
                          _ReasoningEffortButton(
                            efforts: selectedModel!.supportedReasoningEfforts,
                            selectedEffort: selectedReasoningEffort,
                            onSelect: onSelectReasoningEffort,
                          ),
                        ],
                        if (showServiceTier && selectedModel != null) ...[
                          const SizedBox(width: IdeSpacing.space6),
                          _ServiceTierButton(
                            tiers: selectedModel!.serviceTiers,
                            selectedTierId: selectedServiceTierId,
                            onSelect: onSelectServiceTier,
                          ),
                        ],
                        if (showPermissionPolicy) ...[
                          const SizedBox(width: IdeSpacing.space6),
                          _PermissionPolicyButton(
                            label: permissionPolicyLabel,
                            presets: permissionPresets,
                            selectedPresetId: selectedPermissionPresetId,
                            onSelect: onSelectPermissionPreset,
                          ),
                        ],
                        const Spacer(),
                        AnimatedSwitcher(
                          duration: IdeMotion.durationNormal,
                          switchInCurve: IdeMotion.curveDefault,
                          switchOutCurve: IdeMotion.curveDefault,
                          layoutBuilder: (currentChild, previousChildren) =>
                              currentChild ?? const SizedBox.shrink(),
                          child: showCancel
                              ? _ComposerActionButton(
                                  key: const ValueKey(
                                    'agent-cancel-button-state',
                                  ),
                                  tooltip: 'Cancel',
                                  backgroundColor: colors.border.withValues(
                                    alpha: 0.36,
                                  ),
                                  foregroundColor: colors.textSecondary,
                                  buttonKey: const ValueKey(
                                    'agent-cancel-button',
                                  ),
                                  icon: const Icon(
                                    Icons.stop_rounded,
                                    size: 18,
                                  ),
                                  onPressed: onCancel,
                                )
                              : showSend
                              ? _ComposerActionButton(
                                  key: const ValueKey(
                                    'agent-send-button-state',
                                  ),
                                  tooltip: 'Send',
                                  // 可发送时使用实心 accent，作为界面最强的
                                  // 行动锚点；不可发送时退回弱化中性底。
                                  backgroundColor: canSubmit
                                      ? colors.accent
                                      : colors.border.withValues(alpha: 0.2),
                                  foregroundColor: canSubmit
                                      ? Colors.white
                                      : colors.textSecondary.withValues(
                                          alpha: 0.72,
                                        ),
                                  filled: canSubmit,
                                  buttonKey: const ValueKey(
                                    'agent-send-button',
                                  ),
                                  icon: const Icon(
                                    Icons.arrow_upward_rounded,
                                    size: 18,
                                  ),
                                  onPressed: canSubmit ? onSend : null,
                                )
                              : const SizedBox(
                                  key: ValueKey(
                                    'agent-send-unavailable-placeholder',
                                  ),
                                  width: 40,
                                  height: 40,
                                ),
                        ),
                      ],
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

  Future<void> _showMentionPicker(BuildContext context) async {
    final files = mentionCandidates();
    if (files.isEmpty) {
      return;
    }
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    await showShadDialog<void>(
      context: context,
      builder: (dialogContext) {
        return ShadDialog(
          title: const Text('Mention file'),
          child: SizedBox(
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
                child: ShadIconButton.ghost(
                  key: ValueKey<String>('agent-composer-remove-image-$path'),
                  onPressed: () => onRemove(path),
                  width: 20,
                  height: 20,
                  padding: EdgeInsets.zero,
                  foregroundColor: colors.textSecondary,
                  hoverBackgroundColor: colors.surfaceOverlay,
                  icon: const Icon(Icons.close_rounded, size: 12),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SelectorSelect<T extends Object> extends StatelessWidget {
  const _SelectorSelect({
    required this.selectorKey,
    required this.tooltip,
    required this.placeholderLabel,
    required this.icon,
    required this.initialValue,
    required this.labelBuilder,
    required this.options,
    required this.onChanged,
  });

  final Key selectorKey;
  final String tooltip;
  final String placeholderLabel;
  final IconData icon;
  final T? initialValue;
  final String Function(T value) labelBuilder;
  final Iterable<Widget> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return IdeTooltip(
      message: tooltip,
      child: ShadSelect<T>(
        key: selectorKey,
        initialValue: initialValue,
        minWidth: 0,
        decoration: ShadDecoration.none,
        padding: EdgeInsets.zero,
        trailing: const SizedBox.shrink(),
        placeholder: IdeChip(label: placeholderLabel, leadingIcon: icon),
        selectedOptionBuilder: (context, value) =>
            IdeChip(label: labelBuilder(value), leadingIcon: icon),
        options: options,
        onChanged: (value) {
          if (value != null) {
            onChanged(value);
          }
        },
      ),
    );
  }
}

/// 模型选择按钮，点击弹出可用模型列表。
class _ModelSelectorButton extends StatelessWidget {
  const _ModelSelectorButton({
    required this.models,
    required this.selectedModel,
    required this.onSelect,
  });

  final List<AgentModelInfo> models;
  final AgentModelInfo? selectedModel;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return _SelectorSelect<String>(
      selectorKey: const ValueKey('agent-model-selector'),
      tooltip: 'Select model',
      placeholderLabel: 'Model',
      icon: Icons.auto_awesome_outlined,
      initialValue: selectedModel?.id,
      labelBuilder: _modelLabel,
      onChanged: onSelect,
      options: [
        for (final model in models)
          ShadOption<String>(
            key: ValueKey<String>('agent-model-option-${model.id}'),
            value: model.id,
            child: Text(
              model.displayName,
              overflow: TextOverflow.ellipsis,
              style: IdeTextStyles.of(context).bodyMedium,
            ),
          ),
      ],
    );
  }

  String _modelLabel(String modelId) {
    for (final model in models) {
      if (model.id == modelId) {
        return model.displayName;
      }
    }
    return selectedModel?.displayName ?? modelId;
  }
}

/// 推理深度（思考）选择按钮，点击弹出 low/medium/high/xhigh 列表。
class _ReasoningEffortButton extends StatelessWidget {
  const _ReasoningEffortButton({
    required this.efforts,
    required this.selectedEffort,
    required this.onSelect,
  });

  final List<AgentModelReasoningEffort> efforts;
  final String? selectedEffort;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return _SelectorSelect<String>(
      selectorKey: const ValueKey('agent-reasoning-effort-selector'),
      tooltip: 'Reasoning effort',
      placeholderLabel: 'Think',
      icon: Icons.psychology_alt_outlined,
      initialValue: selectedEffort,
      labelBuilder: _effortLabel,
      onChanged: (value) => onSelect(value),
      options: [
        for (final effort in efforts)
          ShadOption<String>(
            key: ValueKey<String>('agent-reasoning-option-${effort.effort}'),
            value: effort.effort,
            child: Text(
              effort.description ?? effort.effort,
              style: IdeTextStyles.of(context).bodyMedium,
            ),
          ),
      ],
    );
  }

  String _effortLabel(String effortValue) {
    for (final effort in efforts) {
      if (effort.effort == effortValue) {
        return effort.description ?? effort.effort;
      }
    }
    return selectedEffort ?? effortValue;
  }
}

/// 服务档位（速率）选择按钮，点击弹出可用档位列表。
class _ServiceTierButton extends StatelessWidget {
  const _ServiceTierButton({
    required this.tiers,
    required this.selectedTierId,
    required this.onSelect,
  });

  final List<AgentModelServiceTier> tiers;
  final String? selectedTierId;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return _SelectorSelect<String>(
      selectorKey: const ValueKey('agent-service-tier-selector'),
      tooltip: 'Service tier',
      placeholderLabel: 'Speed',
      icon: Icons.speed_rounded,
      initialValue: selectedTierId,
      labelBuilder: _tierLabel,
      onChanged: (value) => onSelect(value),
      options: [
        for (final tier in tiers)
          ShadOption<String>(
            key: ValueKey<String>('agent-service-tier-option-${tier.id}'),
            value: tier.id,
            child: Text(tier.name, style: IdeTextStyles.of(context).bodyMedium),
          ),
      ],
    );
  }

  String _tierLabel(String id) {
    for (final tier in tiers) {
      if (tier.id == id) {
        return tier.name;
      }
    }
    return id;
  }
}

/// 审批/沙箱策略预设选择按钮。
class _PermissionPolicyButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return _SelectorSelect<String>(
      selectorKey: const ValueKey('agent-permission-policy-selector'),
      tooltip: 'Approval & sandbox',
      placeholderLabel: label,
      icon: Icons.shield_outlined,
      initialValue: selectedPresetId,
      labelBuilder: (id) {
        for (final preset in presets) {
          if (preset.id == id) {
            return preset.label;
          }
        }
        return label;
      },
      onChanged: (value) {
        for (final preset in presets) {
          if (preset.id == value) {
            onSelect(preset);
            return;
          }
        }
      },
      options: [
        for (final preset in presets)
          ShadOption<String>(
            key: ValueKey<String>('agent-permission-preset-${preset.id}'),
            value: preset.id,
            child: Text(
              preset.label,
              style: IdeTextStyles.of(context).bodyMedium,
            ),
          ),
      ],
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
          child: ShadIconButton.ghost(
            key: buttonKey,
            onPressed: onPressed,
            width: 32,
            height: 32,
            padding: EdgeInsets.zero,
            foregroundColor: foregroundColor,
            hoverForegroundColor: filled ? foregroundColor : null,
            hoverBackgroundColor: filled
                ? Colors.white.withValues(alpha: 0.14)
                : null,
            icon: icon,
          ),
        ),
      ),
    );
  }
}
