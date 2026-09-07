import 'package:flutter/material.dart';

import 'ide_button.dart';
import 'ide_colors.dart';
import 'ide_icon_box.dart';
import 'ide_motion.dart';
import 'ide_spacing.dart';
import 'pane_widgets.dart';

/// Composer / 工具栏紧凑下拉触发器。
///
/// 与 [IdeButton] 的分工：普通动作走 [IdeButton]；带展开箭头、打开态
/// [IdeButtonVariant.secondary]、键盘焦点走 Graphite 内侧环的选择触发器走这里。
///
/// [buttonKey] 挂在内部 [IdeButton] 上，便于测试按现有 ValueKey 定位，
/// 并用 ancestor [IdeTooltip] 读取提示文案。
class IdeToolbarSelectTrigger extends StatelessWidget {
  const IdeToolbarSelectTrigger({
    super.key,
    required this.label,
    required this.focusNode,
    required this.open,
    required this.child,
    this.semanticLabel,
    this.tooltip,
    this.onPressed,
    this.isLoading = false,
    this.buttonKey,
  });

  /// 无障碍与无富内容时的按钮名称。
  final String label;

  /// 覆盖 [label] 的无障碍名称。
  final String? semanticLabel;

  /// 悬停提示；为空或空白时不包 [IdeTooltip]。
  final String? tooltip;

  /// 弹层触发器焦点；关闭弹层后由 [IdePopoverController] 恢复。
  final FocusNode focusNode;

  /// 弹层是否打开；打开时触发器使用 secondary 变体。
  final bool open;

  /// 点击回调；为 `null` 时按钮禁用。
  final VoidCallback? onPressed;

  /// 为 true 时用忙碌指示器替换展开箭头。
  final bool isLoading;

  /// 展开箭头左侧的触发器内容（图标、文案、状态）。
  final Widget child;

  /// 内部 [IdeButton] 的稳定 key。
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final tooltipText = tooltip?.trim();
    final button = IdeButton(
      key: buttonKey,
      label: label,
      semanticLabel: semanticLabel ?? label,
      variant: open ? IdeButtonVariant.secondary : IdeButtonVariant.ghost,
      focusNode: focusNode,
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          const SizedBox(width: IdeSpacing.space4),
          if (isLoading)
            IdeIconBox.custom(
              key: const ValueKey('ide-toolbar-select-trigger-loading'),
              child: IdeBusySpinner(
                size: 12,
                strokeWidth: 1.5,
                color: colors.textTertiary,
              ),
            )
          else
            IdeIconBox.custom(
              child: AnimatedRotation(
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
            ),
        ],
      ),
    );
    if (tooltipText == null || tooltipText.isEmpty) {
      return button;
    }
    return IdeTooltip(message: tooltipText, enabled: !open, child: button);
  }
}
