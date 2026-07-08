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
    required this.onSend,
    required this.onCancel,
    required this.models,
    required this.selectedModel,
    required this.selectedReasoningEffort,
    required this.selectedServiceTierId,
    required this.showReasoningEffort,
    required this.showServiceTier,
    required this.onSelectModel,
    required this.onSelectReasoningEffort,
    required this.onSelectServiceTier,
  });

  final TextEditingController controller;
  final bool canSubmit;
  final bool isTurnRunning;
  final AgentThreadOpenPhase threadOpenPhase;
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

  final ValueChanged<String> onSelectModel;
  final ValueChanged<String?> onSelectReasoningEffort;
  final ValueChanged<String?> onSelectServiceTier;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final inputTextStyle = textStyles.bodyMedium.copyWith(
      color: colors.textPrimary,
    );
    final lineHeight =
        (inputTextStyle.fontSize ?? 12) * (inputTextStyle.height ?? 1.35);
    final hasDraft = controller.text.trim().isNotEmpty;
    final showSend =
        threadOpenPhase == AgentThreadOpenPhase.idle &&
        (!isTurnRunning || hasDraft);
    final showCancel =
        threadOpenPhase == AgentThreadOpenPhase.idle &&
        isTurnRunning &&
        !hasDraft;
    return Focus(
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
