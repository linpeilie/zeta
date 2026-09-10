import 'package:flutter/material.dart';

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
///
/// 外环直径对齐 [IdeTextStyles.displayLarge] 图标盒（默认 23px）；圆盘和字形
/// 收在环内，空隙露出卡片底。启用/禁用只换色、不改几何。
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
    final textStyles = IdeTextStyles.of(context);
    final enabled = onPressed != null;
    final backgroundColor = filled
        ? colors.accent
        : colors.border.withValues(alpha: enabled ? 0.36 : 0.2);
    final foregroundColor = filled
        ? colors.onAccent
        : enabled
        ? colors.textSecondary
        : colors.textSecondary.withValues(alpha: 0.72);
    final ringSize = IdeMetrics.controlIconBoxFor(textStyles.displayLarge);
    const inset =
        IdeMetrics.submitButtonRingWidth + IdeMetrics.submitButtonRingGap;
    final discSize = (ringSize - 2 * inset).clamp(0, ringSize).toDouble();

    return IdeTooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        excludeSemantics: true,
        child: SizedBox.square(
          dimension: ringSize,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: backgroundColor,
                width: IdeMetrics.submitButtonRingWidth,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(inset),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: backgroundColor,
                  shape: BoxShape.circle,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: buttonKey,
                    customBorder: const CircleBorder(),
                    onTap: onPressed,
                    child: Center(
                      child: IdeIconBox(
                        icon,
                        style: TextStyle(fontSize: discSize, height: 1),
                        color: foregroundColor,
                      ),
                    ),
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
