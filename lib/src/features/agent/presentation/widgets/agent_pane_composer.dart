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
        color: idePanelColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ideBorderColor.withValues(alpha: 0.72)),
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
            // 上半部分：多行输入框，默认 3 行，最高 10 行，去掉自带边框。
            TextField(
              key: const ValueKey('agent-message-input'),
              controller: controller,
              minLines: 3,
              maxLines: 10,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) {
                if (canSubmit) {
                  onSend();
                }
              },
              decoration: const InputDecoration(
                hintText: 'Message Agent',
                hintStyle: TextStyle(color: ideMutedTextColor),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
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
                  Tooltip(
                    message: 'Cancel',
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: ideBorderColor.withValues(alpha: 0.36),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        key: const ValueKey('agent-cancel-button'),
                        onPressed: onCancel,
                        icon: const Icon(Icons.stop_rounded, size: 18),
                      ),
                    ),
                  )
                else if (showSend)
                  Tooltip(
                    message: 'Send',
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: canSubmit
                            ? ideAccentColor.withValues(alpha: 0.18)
                            : ideBorderColor.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        key: const ValueKey('agent-send-button'),
                        onPressed: canSubmit ? onSend : null,
                        icon: const Icon(Icons.arrow_upward_rounded, size: 18),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ideBorderColor.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ideBorderColor.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: ideMutedTextColor),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: ideMutedTextColor.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 12,
              color: ideMutedTextColor,
            ),
          ],
        ),
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
    return PopupMenuButton<String>(
      key: const ValueKey('agent-model-selector'),
      tooltip: 'Select model',
      onSelected: onSelect,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      itemBuilder: (context) => [
        for (final model in models)
          PopupMenuItem<String>(
            value: model.id,
            height: 32,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  child: model.id == selectedModel?.id
                      ? Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: ideAccentColor,
                        )
                      : const SizedBox(),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    model.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
      child: _SelectorChip(
        label: selectedModel?.displayName ?? 'Model',
        icon: Icons.auto_awesome_outlined,
      ),
    );
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
    return PopupMenuButton<String?>(
      key: const ValueKey('agent-reasoning-effort-selector'),
      tooltip: 'Reasoning effort',
      onSelected: onSelect,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      itemBuilder: (context) => [
        for (final effort in efforts)
          PopupMenuItem<String?>(
            value: effort.effort,
            height: 32,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  child: effort.effort == selectedEffort
                      ? Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: ideAccentColor,
                        )
                      : const SizedBox(),
                ),
                const SizedBox(width: 6),
                Text(
                  effort.description ?? effort.effort,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
      ],
      child: _SelectorChip(
        label: selectedEffort ?? 'Think',
        icon: Icons.psychology_alt_outlined,
      ),
    );
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
    return PopupMenuButton<String?>(
      key: const ValueKey('agent-service-tier-selector'),
      tooltip: 'Service tier',
      onSelected: onSelect,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      itemBuilder: (context) => [
        for (final tier in tiers)
          PopupMenuItem<String?>(
            value: tier.id,
            height: 32,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  child: tier.id == selectedTierId
                      ? Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: ideAccentColor,
                        )
                      : const SizedBox(),
                ),
                const SizedBox(width: 6),
                Text(tier.name, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
      ],
      child: _SelectorChip(
        label: _selectedTierName() ?? 'Speed',
        icon: Icons.speed_rounded,
      ),
    );
  }

  String? _selectedTierName() {
    final id = selectedTierId;
    if (id == null) {
      return null;
    }
    for (final tier in tiers) {
      if (tier.id == id) {
        return tier.name;
      }
    }
    return null;
  }
}
