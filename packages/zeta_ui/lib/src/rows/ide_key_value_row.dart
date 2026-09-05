import 'package:flutter/material.dart';

import '../ide_colors.dart';
import '../ide_metrics.dart';
import '../ide_spacing.dart';
import '../ide_text_styles.dart';

/// [IdeKeyValueRow] 值的排版语义。
///
/// 桌面 IDE 的排版分工：人类文案走 UI 字体，机器数据走等宽字体，让用户一眼
/// 分辨「可读的话」和「可复制的值」。这四档就是把这条分工落到单个字段上——
/// 调用方声明的是**值是什么**，不是它该长什么样。
enum IdeKeyValueTone {
  /// 人类可读文案（厂商名、状态描述）。走 UI 字体。
  text,

  /// 稳定的机器标识符（Provider 名、协议名、模型 ID）。走等宽 + 主色。
  identifier,

  /// 次级技术串（文件路径、命令行）。走等宽 + 次级色。
  code,

  /// 数值与版本号。走等宽 + `tabularFigures`，多行才会按位对齐。
  numeric,
}

/// 密集只读技术数据的键值行：字段名固定宽度，值紧随其后同行左对齐。
///
/// 与 `IdeSettingsRow` 的分工——两者都是「左标签右内容」，但服务的场景相反：
///
/// | | `IdeSettingsRow` | `IdeKeyValueRow` |
/// |---|---|---|
/// | 内容 | 标题 + 描述 + **可操作控件** | 字段名 + **只读技术值** |
/// | 最小高度 | [IdeMetrics.settingsRowMinHeight]（52） | [IdeMetrics.compactRowHeight]（28） |
/// | 值的对齐 | 右对齐，贴住行的右边缘 | 左对齐，紧跟字段名 |
/// | 窄宽度 | 低于 [IdeMetrics.stackedRowBreakpoint] 时上下堆叠 | **永不堆叠** |
///
/// 前者供用户**改配置**，所以控件要推到右边形成一列可点击区；后者供用户
/// **读事实**，值必须紧挨字段名——一旦把值甩到行的另一端，读十个字段就要走十趟
/// 「Z」字形，而这类信息本来就是拿来快速核对的。
///
/// 同理这里不提供 `showDivider`：28px 的行距下逐行画线会立刻退化成表格框。
/// 分组感交给 `IdeRowGroup` 的眉标题与组间分隔线承担。
class IdeKeyValueRow extends StatelessWidget {
  const IdeKeyValueRow({
    required this.label,
    required this.value,
    super.key,
    this.tone = IdeKeyValueTone.text,
    this.valueColor,
    this.trailing,
    this.selectable = false,
    this.maxLines = 2,
  });

  /// 左侧字段名。宽度恒为 [IdeMetrics.keyValueLabelWidth]。
  final String label;

  /// 右侧值。
  final String value;

  /// 值的排版语义。
  final IdeKeyValueTone tone;

  /// 覆盖 [tone] 自带的颜色。
  ///
  /// 只在值本身携带状态时使用（例如「最新版本」可升级时转 `warning`），
  /// 不要拿它做常规的明暗微调——那会让 tone 表达的字体分工失效。
  final Color? valueColor;

  /// 值右侧的可选操作（复制按钮等）。
  final Widget? trailing;

  /// 值是否可选中复制。路径、错误串一类需要外带的内容才打开。
  final bool selectable;

  /// 值的最大行数。
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final styles = IdeTextStyles.of(context);
    final baseStyle = switch (tone) {
      IdeKeyValueTone.text => styles.bodySmall,
      IdeKeyValueTone.identifier => styles.identifier,
      IdeKeyValueTone.code => styles.codeSmall,
      IdeKeyValueTone.numeric => styles.numeric,
    };
    final valueStyle = valueColor == null
        ? baseStyle
        : baseStyle.copyWith(color: valueColor);

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: IdeMetrics.compactRowHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: IdeSpacing.space6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: IdeMetrics.keyValueLabelWidth,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: styles.titleSmall.copyWith(color: colors.textSecondary),
              ),
            ),
            const SizedBox(width: IdeSpacing.space8),
            Expanded(
              child: selectable
                  ? SelectableText(value, maxLines: maxLines, style: valueStyle)
                  : Text(
                      value,
                      maxLines: maxLines,
                      overflow: TextOverflow.ellipsis,
                      style: valueStyle,
                    ),
            ),
            if (trailing case final Widget trailingWidget) ...[
              const SizedBox(width: IdeSpacing.space4),
              trailingWidget,
            ],
          ],
        ),
      ),
    );
  }
}
