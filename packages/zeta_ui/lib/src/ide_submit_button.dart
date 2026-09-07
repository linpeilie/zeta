import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'ide_colors.dart';
import 'ide_icon_box.dart';
import 'ide_metrics.dart';
import 'ide_text_styles.dart';
import 'pane_widgets.dart';

/// 圆形提交按钮。
///
/// [filled] 用于发送等主行动，[filled] 为 false 时用于停止等中性行动；回调为空
/// 时自动切换到禁用态。背景、前景与 hover 行为均由 Graphite 语义色统一解析，
/// 调用方只提供动作图标与文案。
class IdeSubmitButton extends StatelessWidget {
  /// 创建发送/停止按钮。
  const IdeSubmitButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    super.key,
    this.buttonKey,
    this.filled = false,
  });

  /// 动作图标。
  final IconData icon;

  /// 点击回调；为空时按钮禁用。
  final VoidCallback? onPressed;

  /// Tooltip 与无障碍动作名称。
  final String tooltip;

  /// 内层可点击节点的 key。
  ///
  /// 外层 [key] 通常交给 `AnimatedSwitcher` 区分状态；需要稳定定位实际按钮时
  /// 使用本字段。
  final Key? buttonKey;

  /// 是否使用 accent 实心主行动样式。
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final enabled = onPressed != null;
    final backgroundColor = filled
        ? colors.accent
        : colors.border.withValues(alpha: enabled ? 0.36 : 0.2);
    final foregroundColor = filled
        ? colors.onAccent
        : enabled
        ? colors.textSecondary
        : colors.textSecondary.withValues(alpha: 0.72);

    return IdeTooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: IdeMetrics.controlMinHeightCompact,
            minHeight: IdeMetrics.controlMinHeightCompact,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
            ),
            child: ClipOval(
              child: sf.ComponentTheme<sf.FocusOutlineTheme>(
                data: const sf.FocusOutlineTheme(
                  border: Border.fromBorderSide(BorderSide.none),
                ),
                child: sf.IconButton.ghost(
                  key: buttonKey,
                  onPressed: onPressed,
                  size: sf.ButtonSize.small,
                  density: sf.ButtonDensity.iconDense,
                  shape: sf.ButtonShape.circle,
                  disableTransition: filled,
                  // 提交动作是 Composer 中最强的单图标行动，沿用原 22px 视觉尺寸；
                  // displayLarge 的默认行盒为 23px，同时让它随 UI 字号自然缩放。
                  icon: IdeIconBox(
                    icon,
                    style: IdeTextStyles.of(context).displayLarge,
                    color: foregroundColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
