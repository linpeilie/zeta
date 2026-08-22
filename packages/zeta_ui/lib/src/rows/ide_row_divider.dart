import 'package:flutter/widgets.dart';

import '../ide_colors.dart';

/// 连续 Row 之间的统一细分隔线。
///
/// 与 Flutter `Divider` 一样支持两端缩进：[indent] / [endIndent]。缩进按书写
/// 方向解析（LTR 下 [indent] 是左侧），因此 RTL 布局不需要额外处理。
///
/// **缩进值不要现拍**：分隔线的起点必须等于所在行的内容左边缘，否则线会从
/// 主标题左侧「支」出去一截。行组件应当把自己的 padding 直接喂给 [indent]
/// （见 `IdeSettingsRow`），让对齐由构造保证，而不是靠两处数字碰巧相等。
class IdeRowDivider extends StatelessWidget {
  const IdeRowDivider({super.key, this.indent = 0, this.endIndent = 0});

  /// 起点缩进（书写方向的前侧，LTR 下为左）。
  final double indent;

  /// 终点缩进（书写方向的后侧，LTR 下为右）。
  ///
  /// 列表分隔线通常只缩进起点、右端贯通到底：左缩进表达「这条线属于下面那些
  /// 内容」，右端拉满则保持行与行之间的连续感。
  final double endIndent;

  @override
  Widget build(BuildContext context) {
    final line = ColoredBox(
      color: IdeColors.of(context).borderSubtle,
      child: const SizedBox(height: 1),
    );
    if (indent == 0 && endIndent == 0) {
      return line;
    }
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent, end: endIndent),
      child: line,
    );
  }
}

/// 并排列之间的统一细分隔线（[IdeRowDivider] 的纵向版本）。
///
/// 高度由父级约束决定，通常放在固定高度的 `SizedBox` 里。
class IdeColumnDivider extends StatelessWidget {
  const IdeColumnDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: IdeColors.of(context).borderSubtle,
      child: const SizedBox(width: 1),
    );
  }
}
