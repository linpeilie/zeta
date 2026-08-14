import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'ide_colors.dart';
import 'ide_metrics.dart';
import 'ide_text_styles.dart';

/// IDE 紧凑按钮视觉变体，映射到 `shadcn_flutter` 的 [sf.ButtonStyle] 预设。
enum IdeButtonVariant {
  /// 描边按钮，适合工具栏次要操作与筛选触发器。
  outline,

  /// 中性底，适合非主路径操作。
  secondary,

  /// 主色实心，适合页面主行动点。
  primary,

  /// 极轻量，适合内嵌工具操作。
  ghost,

  /// 危险/破坏性操作。
  destructive,
}

/// 统一 IDE 紧凑按钮。
///
/// 默认 `ButtonSize.small` + `ButtonDensity.dense` + [IdeTextStyles.bodySmall]，
/// 并把文案垂直居中，避免 feature 直接拼装 [sf.OutlineButton] 时出现：
/// - 字号偏大（shadcn `typography.small` 14 vs IDE bodySmall 11）
/// - 固定 [IdeMetrics.toolbarHeight] 后文案顶对齐
///
/// 与 [IdeChip] 的分工：
/// - **Button**：动作触发（刷新、打开、确认）与带图标的筛选触发器；
/// - **Chip**：属性标签、可删除 tag、轻量状态胶囊。
class IdeButton extends StatelessWidget {
  /// 创建一个紧凑 IDE 按钮。
  const IdeButton({
    required this.label,
    super.key,
    this.onPressed,
    this.leadingIcon,
    this.trailingIcon,
    this.enabled = true,
    this.variant = IdeButtonVariant.outline,
    this.height,
    this.width,
    this.maxLines = 1,
    this.semanticLabel,
  });

  /// 固定为工具条高度的按钮（[IdeMetrics.toolbarHeight]）。
  const IdeButton.toolbar({
    required this.label,
    super.key,
    this.onPressed,
    this.leadingIcon,
    this.trailingIcon,
    this.enabled = true,
    this.variant = IdeButtonVariant.outline,
    this.width,
    this.maxLines = 1,
    this.semanticLabel,
  }) : height = IdeMetrics.toolbarHeight;

  /// 按钮文案。
  final String label;

  /// 点击回调；为 `null` 时按钮禁用。
  final VoidCallback? onPressed;

  /// 文案前可选图标。
  final IconData? leadingIcon;

  /// 文案后可选图标（如下拉箭头）。
  final IconData? trailingIcon;

  /// 是否允许交互；与 [onPressed] 同时为真时才可点。
  final bool enabled;

  /// 视觉变体。
  final IdeButtonVariant variant;

  /// 外层固定高度；工具栏场景通常为 [IdeMetrics.toolbarHeight]。
  final double? height;

  /// 外层固定宽度；为空时由内容决定。
  final double? width;

  /// 文案最大行数。
  final int maxLines;

  /// 覆盖默认文案的无障碍名称。
  final String? semanticLabel;

  static const double _leadingIconSize = 15;
  static const double _trailingIconSize = 16;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final isEnabled = enabled && onPressed != null;
    final foreground = _resolveForeground(
      colors: colors,
      enabled: isEnabled,
      variant: variant,
    );
    // 实心底必须与文字同色，避免「允许」勾号落在灰字/蓝底上。
    final iconColor = switch (variant) {
      IdeButtonVariant.primary || IdeButtonVariant.destructive => foreground,
      IdeButtonVariant.outline ||
      IdeButtonVariant.secondary ||
      IdeButtonVariant.ghost =>
        isEnabled ? colors.textSecondary : colors.textTertiary,
    };

    final button = sf.Button(
      onPressed: isEnabled ? onPressed : null,
      enabled: isEnabled,
      style: _resolveStyle(variant),
      // 有 leading 时 shadcn 内部 Row 默认顶对齐，alignment 负责垂直居中。
      alignment: Alignment.centerLeft,
      leading: leadingIcon == null
          ? null
          : Icon(leadingIcon, size: _leadingIconSize, color: iconColor),
      trailing: trailingIcon == null
          ? null
          : Icon(trailingIcon, size: _trailingIconSize, color: iconColor),
      child: Text(
        label,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: textStyles.bodySmall.copyWith(color: foreground),
      ),
    );

    final content = height == null && width == null
        ? button
        : SizedBox(height: height, width: width, child: button);

    return Semantics(
      button: true,
      enabled: isEnabled,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: content,
    );
  }

  static sf.AbstractButtonStyle _resolveStyle(IdeButtonVariant variant) {
    const size = sf.ButtonSize.normal;
    const density = sf.ButtonDensity.dense;
    return switch (variant) {
      IdeButtonVariant.outline => const sf.ButtonStyle.outline(
        size: size,
        density: density,
      ),
      IdeButtonVariant.secondary => const sf.ButtonStyle.secondary(
        size: size,
        density: density,
      ),
      IdeButtonVariant.primary => const sf.ButtonStyle.primary(
        size: size,
        density: density,
      ),
      IdeButtonVariant.ghost => const sf.ButtonStyle.ghost(
        size: size,
        density: density,
      ),
      IdeButtonVariant.destructive => const sf.ButtonStyle.destructive(
        size: size,
        density: density,
      ),
    };
  }

  static Color _resolveForeground({
    required IdeColors colors,
    required bool enabled,
    required IdeButtonVariant variant,
  }) {
    if (!enabled) {
      return colors.textTertiary;
    }
    return switch (variant) {
      IdeButtonVariant.primary => colors.onAccent,
      // 与 app_theme 中 destructiveForeground 一致。
      IdeButtonVariant.destructive => Colors.white,
      IdeButtonVariant.outline ||
      IdeButtonVariant.secondary ||
      IdeButtonVariant.ghost => colors.textPrimary,
    };
  }
}
