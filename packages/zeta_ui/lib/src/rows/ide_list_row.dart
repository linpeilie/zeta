import 'package:flutter/widgets.dart';

import '../ide_colors.dart';
import '../ide_metrics.dart';
import '../ide_spacing.dart';
import '../ide_text_styles.dart';
import '../pane_widgets.dart';
import 'ide_row_divider.dart';

/// 统一列表行的密度、文本省略和交互状态。
class IdeListRow extends StatelessWidget {
  const IdeListRow({
    required this.title,
    super.key,
    this.subtitle,
    this.leading,
    this.trailing,
    this.selected = false,
    this.enabled = true,
    this.onPressed,
    this.showDivider = true,
    this.dividerIndent = 0,
    this.semanticLabel,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool selected;
  final bool enabled;
  final VoidCallback? onPressed;
  final bool showDivider;

  /// 行底分隔线的起点缩进。
  ///
  /// 默认 0 表示线贯穿整行。有 [leading] 图标的列表应当把线推到与 [title] 左
  /// 边缘齐平——线从图标下方穿过去时，读起来像是在切割图标，而不是在分隔行。
  ///
  /// 缩进值应由调用方用 token 相加得出（行内边距 + 图标宽 + 图标与文字的间隙），
  /// 不要现拍一个数字，否则改动图标尺寸时对齐会悄悄失效。
  final double dividerIndent;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final styles = IdeTextStyles.of(context);
    final foreground = !enabled
        ? colors.textTertiary
        : selected
        ? colors.textPrimary
        : colors.textSecondary;
    // 分隔线走 IdeRowDivider 而不是行自身的 bottom border：只有把线做成独立
    // 子节点，它才可能被缩进到内容左边缘（见 [dividerIndent]）。
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: IdeMetrics.listRowHeight,
          ),
          child: PaneInteractiveSurface(
            onPressed: onPressed,
            selected: selected,
            enabled: enabled,
            semanticLabel: semanticLabel ?? title,
            padding: IdeSpacing.rowPadding,
            child: Row(
              children: [
                if (leading case final Widget leadingWidget) ...[
                  IconTheme(
                    data: IconThemeData(size: 15, color: foreground),
                    child: leadingWidget,
                  ),
                  const SizedBox(width: IdeSpacing.space8),
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: styles.rowTitle.copyWith(
                          color: enabled
                              ? colors.textPrimary
                              : colors.textTertiary,
                        ),
                      ),
                      if (subtitle case final String subtitleText)
                        Text(
                          subtitleText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: styles.meta.copyWith(color: foreground),
                        ),
                    ],
                  ),
                ),
                if (trailing case final Widget trailingWidget) ...[
                  const SizedBox(width: IdeSpacing.space8),
                  IconTheme.merge(
                    data: IconThemeData(
                      color: enabled ? null : colors.textTertiary,
                    ),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(
                        color: enabled ? null : colors.textTertiary,
                      ),
                      child: trailingWidget,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (showDivider) IdeRowDivider(indent: dividerIndent),
      ],
    );
  }
}
