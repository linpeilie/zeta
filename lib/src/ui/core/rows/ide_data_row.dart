import 'package:flutter/material.dart';

import '../ide_colors.dart';
import '../ide_metrics.dart';
import '../ide_spacing.dart';
import '../ide_text_styles.dart';
import '../pane_widgets.dart';

/// 用于紧凑数据表的统一表头或数据行。
///
/// 单元格始终单行省略；调用方可以把整张表放入受限横向滚动容器，避免窄窗口
/// 挤压统计文本。
class IdeDataRow extends StatelessWidget {
  /// 创建共享列宽的数据表行。
  const IdeDataRow({
    required this.values,
    required this.flexes,
    super.key,
    this.header = false,
    this.onPressed,
    this.showDivider = true,
    this.semanticLabel,
  }) : assert(values.length == flexes.length);

  /// 各列显示的单行文本。
  final List<String> values;

  /// 与 [values] 一一对应的列宽权重。
  final List<int> flexes;

  /// 是否按工具栏表头样式呈现。
  final bool header;

  /// 数据行的可选整行点击回调。
  final VoidCallback? onPressed;

  /// 是否在当前行底部显示分隔线。
  final bool showDivider;

  /// 整行交互的可访问性标签。
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final styles = IdeTextStyles.of(context);
    final textStyle = header
        ? styles.toolbarLabel.copyWith(color: colors.textSecondary)
        : styles.bodySmall.copyWith(color: colors.textPrimary);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: header ? colors.surfaceElevated : Colors.transparent,
        border: showDivider
            ? Border(bottom: BorderSide(color: colors.borderSubtle))
            : null,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: IdeMetrics.compactRowHeight,
        ),
        child: PaneInteractiveSurface(
          onPressed: onPressed,
          button: onPressed != null,
          semanticLabel: semanticLabel,
          padding: const EdgeInsets.symmetric(
            horizontal: IdeSpacing.space8,
            vertical: IdeSpacing.space6,
          ),
          borderRadius: BorderRadius.zero,
          child: Row(
            children: [
              for (var index = 0; index < values.length; index += 1)
                Expanded(
                  flex: flexes[index],
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: index < values.length - 1 ? IdeSpacing.space8 : 0,
                    ),
                    child: Text(
                      values[index],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textStyle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
