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
    final shadTheme = ShadTheme.of(context);
    final colorScheme = shadTheme.colorScheme;
    final inputTextStyle = shadTheme.textTheme.p.copyWith(
      color: colorScheme.foreground,
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border.withValues(alpha: 0.72)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ShadTextarea(
              key: const ValueKey('agent-message-input'),
              controller: controller,
              placeholder: Text(
                'Message Agent',
                style: shadTheme.textTheme.p.copyWith(color: colors.mutedText),
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
            const SizedBox(height: 6),
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
                  const SizedBox(width: 6),
                  _ReasoningEffortButton(
                    efforts: selectedModel!.supportedReasoningEfforts,
                    selectedEffort: selectedReasoningEffort,
                    onSelect: onSelectReasoningEffort,
                  ),
                ],
                if (showServiceTier && selectedModel != null) ...[
                  const SizedBox(width: 6),
                  _ServiceTierButton(
                    tiers: selectedModel!.serviceTiers,
                    selectedTierId: selectedServiceTierId,
                    onSelect: onSelectServiceTier,
                  ),
                ],
                const Spacer(),
                if (showCancel)
                  IdeTooltip(
                    message: 'Cancel',
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.border.withValues(alpha: 0.36),
                        shape: BoxShape.circle,
                      ),
                      child: ClipOval(
                        child: ShadIconButton.ghost(
                          key: const ValueKey('agent-cancel-button'),
                          onPressed: onCancel,
                          width: 32,
                          height: 32,
                          padding: EdgeInsets.zero,
                          foregroundColor: colors.mutedText,
                          icon: const Icon(Icons.stop_rounded, size: 18),
                        ),
                      ),
                    ),
                  )
                else if (showSend)
                  IdeTooltip(
                    message: 'Send',
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: canSubmit
                            ? colors.accent.withValues(alpha: 0.18)
                            : colors.border.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: ClipOval(
                        child: ShadIconButton.ghost(
                          key: const ValueKey('agent-send-button'),
                          onPressed: canSubmit ? onSend : null,
                          width: 32,
                          height: 32,
                          padding: EdgeInsets.zero,
                          foregroundColor: canSubmit
                              ? colors.accent
                              : colors.mutedText.withValues(alpha: 0.72),
                          icon: const Icon(
                            Icons.arrow_upward_rounded,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(
                    key: ValueKey('agent-send-unavailable-placeholder'),
                    width: 40,
                    height: 40,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 选择控件通用的紧凑胶囊外观。
class _SelectorChip extends StatelessWidget {
  const _SelectorChip({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ShadTheme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.muted.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.border.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: colorScheme.mutedForeground),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: colorScheme.mutedForeground.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 12,
              color: colorScheme.mutedForeground,
            ),
          ],
        ),
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
        placeholder: _SelectorChip(label: placeholderLabel, icon: icon),
        selectedOptionBuilder: (context, value) =>
            _SelectorChip(label: labelBuilder(value), icon: icon),
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
              style: const TextStyle(fontSize: 12),
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
              style: const TextStyle(fontSize: 12),
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
            child: Text(tier.name, style: const TextStyle(fontSize: 12)),
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
