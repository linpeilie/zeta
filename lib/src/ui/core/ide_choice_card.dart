import 'package:flutter/material.dart';

import 'ide_colors.dart';
import 'ide_effects.dart';
import 'ide_spacing.dart';
import 'ide_text_styles.dart';
import 'pane_widgets.dart';

/// 卡片式单选组中的一个选项描述。
///
/// [key] 会透传到对应的 [IdeChoiceCard]，用于测试与列表 diff 的稳定标识。
class IdeChoiceCardOption<T> {
  const IdeChoiceCardOption({
    required this.value,
    required this.label,
    required this.icon,
    this.semanticLabel,
    this.key,
  });

  final T value;
  final String label;
  final IconData icon;
  final String? semanticLabel;
  final Key? key;
}

/// 图标 + 标题的选项卡片（Choice Card）。
///
/// 用于 2–4 个互斥选项的单选场景（如设置项）：图标居左上、标题在下，
/// 选中态使用 accent 边框 + primaryMuted 底色，hover/focus/disabled
/// 反馈由 [PaneInteractiveSurface] 提供。
class IdeChoiceCard extends StatelessWidget {
  const IdeChoiceCard({
    required this.label,
    required this.icon,
    super.key,
    this.selected = false,
    this.enabled = true,
    this.onPressed,
    this.semanticLabel,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback? onPressed;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final iconColor = !enabled
        ? colors.textTertiary
        : selected
        ? colors.accent
        : colors.textSecondary;
    final labelColor = !enabled
        ? colors.textTertiary
        : selected
        ? colors.accent
        : colors.textPrimary;
    return PaneInteractiveSurface(
      onPressed: enabled ? onPressed : null,
      enabled: enabled,
      selected: selected,
      button: true,
      semanticLabel: semanticLabel ?? label,
      alignment: Alignment.topLeft,
      padding: IdeSpacing.all12,
      borderRadius: IdeRadius.allMedium,
      borderColor: colors.border,
      selectedBorderColor: colors.accent,
      selectedBackgroundColor: colors.primaryMuted,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(height: IdeSpacing.space12),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyles.bodyMedium.copyWith(
              color: labelColor,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// 等宽选项卡片单选组。
///
/// 以 [Wrap] 排列固定宽度的 [IdeChoiceCard]，窄容器下自动换行；
/// 点击任一卡片回调 [onChanged]（重复点击当前值也会回调，由调用方去重）。
class IdeChoiceCardGroup<T> extends StatelessWidget {
  const IdeChoiceCardGroup({
    required this.options,
    required this.value,
    required this.onChanged,
    super.key,
    this.cardWidth = 150,
    this.enabled = true,
  });

  final List<IdeChoiceCardOption<T>> options;

  /// 当前选中的值；不在 [options] 内时无卡片呈现选中态。
  final T value;
  final ValueChanged<T> onChanged;

  /// 单张卡片宽度，保证组内卡片等宽。
  final double cardWidth;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: IdeSpacing.space8,
      runSpacing: IdeSpacing.space8,
      children: [
        for (final option in options)
          SizedBox(
            width: cardWidth,
            child: IdeChoiceCard(
              key: option.key,
              label: option.label,
              icon: option.icon,
              selected: option.value == value,
              enabled: enabled,
              semanticLabel: option.semanticLabel,
              onPressed: () => onChanged(option.value),
            ),
          ),
      ],
    );
  }
}
