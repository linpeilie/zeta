import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'ide_colors.dart';
import 'ide_spacing.dart';
import 'ide_text_styles.dart';

/// IDE chip 视觉变体，映射到 `shadcn_flutter` 的 [sf.ButtonStyle] 预设。
enum IdeChipVariant {
  /// 默认中性底，适合标签与轻量筛选。
  secondary,

  /// 描边外观，适合未选中的可切换项。
  outline,

  /// 主色实心，适合强调标签。
  primary,

  /// 极轻量，适合工具栏内嵌标签。
  ghost,

  /// 危险/删除语义。
  destructive,
}

/// 统一 IDE 紧凑胶囊标签。
///
/// 交互与结构委托 [sf.Chip] / [sf.ChipButton]，视觉通过 Graphite token、
/// 紧凑 [sf.ChipTheme] padding 与 small/dense 按钮规格收紧；feature 页面
/// 应消费本组件，而不是直接拼装 `sf.Chip` 细节。
///
/// 与 [IdeTab] / [IdeTabs] 的分工：
/// - **Chip**：属性标签、可删除 tag、轻量筛选/状态胶囊；
/// - **Tab**：单选分组与桌面风格选中指示（下划线）。
class IdeChip extends StatelessWidget {
  /// 创建一个紧凑 IDE chip。
  const IdeChip({
    required this.label,
    super.key,
    this.leadingIcon,
    this.trailingIcon,
    this.onPressed,
    this.onDeleted,
    this.selected = false,
    this.enabled = true,
    this.variant = IdeChipVariant.secondary,
    this.semanticLabel,
  });

  /// 芯片上显示的短文本。
  final String label;

  /// 标签前的可选图标。
  final IconData? leadingIcon;

  /// 标签后的可选图标；若同时提供 [onDeleted]，删除按钮优先于本图标。
  final IconData? trailingIcon;

  /// 整颗 chip 被点击时触发；为空时仍可渲染，但交互光标为默认箭头。
  final VoidCallback? onPressed;

  /// 提供后在尾部显示删除按钮（[sf.ChipButton]），点击只触发本回调。
  final VoidCallback? onDeleted;

  /// 是否呈现选中态；选中时默认改用 primary 填充，覆盖 [variant]。
  final bool selected;

  /// 是否允许交互；禁用时忽略 [onPressed] / [onDeleted] 并降低不透明度。
  final bool enabled;

  /// 未选中时的视觉变体。
  final IdeChipVariant variant;

  /// 覆盖默认标签的无障碍名称。
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final style = _resolveStyle(selected: selected, variant: variant);
    final foreground = _resolveForeground(
      colors: colors,
      selected: selected,
      enabled: enabled,
      variant: variant,
    );

    final labelStyle = textStyles.bodySmall.copyWith(
      color: foreground,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      height: 1.1,
    );

    final Widget? leading = leadingIcon == null
        ? null
        : Icon(leadingIcon, size: 12, color: foreground);

    final Widget? trailing = _buildTrailing(
      colors: colors,
      foreground: foreground,
    );

    final chip = sf.ComponentTheme(
      data: const sf.ChipTheme(
        padding: EdgeInsets.symmetric(
          horizontal: IdeSpacing.space8,
          vertical: IdeSpacing.space4,
        ),
      ),
      child: sf.Chip(
        style: style,
        onPressed: enabled && onPressed != null ? onPressed : null,
        leading: leading,
        trailing: trailing,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: labelStyle,
        ),
      ),
    );

    final content = Opacity(opacity: enabled ? 1 : 0.48, child: chip);

    return Semantics(
      button: onPressed != null,
      enabled: enabled && (onPressed != null || onDeleted != null),
      selected: selected,
      label: semanticLabel ?? label,
      // 有删除按钮时保留子树语义，方便读屏聚焦 close 控件。
      excludeSemantics: onDeleted == null,
      child: content,
    );
  }

  Widget? _buildTrailing({
    required IdeColors colors,
    required Color foreground,
  }) {
    if (onDeleted != null) {
      return sf.ChipButton(
        onPressed: enabled
            ? () {
                onDeleted!();
              }
            : null,
        child: Icon(
          Icons.close_rounded,
          size: 12,
          color: enabled ? colors.textSecondary : colors.textTertiary,
        ),
      );
    }
    if (trailingIcon == null) {
      return null;
    }
    return Icon(trailingIcon, size: 12, color: foreground);
  }

  static sf.AbstractButtonStyle _resolveStyle({
    required bool selected,
    required IdeChipVariant variant,
  }) {
    const size = sf.ButtonSize.small;
    const density = sf.ButtonDensity.dense;
    if (selected) {
      return const sf.ButtonStyle.primary(size: size, density: density);
    }
    return switch (variant) {
      IdeChipVariant.secondary => const sf.ButtonStyle.secondary(
        size: size,
        density: density,
      ),
      IdeChipVariant.outline => const sf.ButtonStyle.outline(
        size: size,
        density: density,
      ),
      IdeChipVariant.primary => const sf.ButtonStyle.primary(
        size: size,
        density: density,
      ),
      IdeChipVariant.ghost => const sf.ButtonStyle.ghost(
        size: size,
        density: density,
      ),
      IdeChipVariant.destructive => const sf.ButtonStyle.destructive(
        size: size,
        density: density,
      ),
    };
  }

  static Color _resolveForeground({
    required IdeColors colors,
    required bool selected,
    required bool enabled,
    required IdeChipVariant variant,
  }) {
    if (!enabled) {
      return colors.textTertiary;
    }
    if (selected || variant == IdeChipVariant.primary) {
      // 与 shadcn primary 实心底对应，必须用 onAccent 而非 accentForeground。
      return colors.onAccent;
    }
    if (variant == IdeChipVariant.destructive) {
      // 与 app_theme 中 destructiveForeground 一致。
      return Colors.white;
    }
    return colors.textSecondary;
  }
}
