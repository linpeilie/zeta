import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'ide_metrics.dart';
import 'ide_text_styles.dart';

/// 控件内图标的等高外框。
///
/// **为什么图标不能直接摆进控件的 Row**：控件高度由「最高的那个内容」决定，
/// 图标一旦比文字行盒高，带图标的控件就比纯文字控件高一截。shadcn 官网自己
/// 的 Select（32）比 Button（30）高 2px，原因就是里面那个 16px 的 chevron，
/// 而不是别的设计意图。项目内同样散落着 13 / 15 / 16 三种图标尺寸。
///
/// 本组件把图标套进一个边长为 [IdeMetrics.controlIconBoxFor] 的方框（默认按
/// [IdeTextStyles.bodySmall] 解析，即控件的统一文字档），并把字形本身夹到
/// 不超过方框。于是：
/// - 图标永远不会成为决定控件高度的那个内容；
/// - 有图标 / 没图标的控件严丝合缝等高；
/// - 用户放大 UI 字号时，图标跟着文字一起长，比例不变。
///
/// 图标的**颜色**仍由外层 `IconTheme` 或调用方给的 [color] 决定，本组件不插手。
class IdeIconBox extends StatelessWidget {
  /// 用一个 [IconData] 构造等高图标。
  const IdeIconBox(this.icon, {super.key, this.style, this.size, this.color})
    : child = null;

  /// 用任意子组件构造等高图标框。
  ///
  /// 适用于图标外面还包了动画（如随选中态旋转的箭头）或来自第三方组件、
  /// 无法直接换成 [IconData] 的场景。子组件自身的尺寸由调用方保证不超过
  /// 方框——本构造只负责把它固定在等高的方框里居中。
  const IdeIconBox.custom({required Widget this.child, super.key, this.style})
    : icon = null,
      size = null,
      color = null;

  /// 要绘制的图标。
  final IconData? icon;

  /// 自定义子组件（[IdeIconBox.custom]）。
  final Widget? child;

  /// 解析方框边长所用的文字样式；为空时取 [IdeTextStyles.bodySmall]。
  ///
  /// 只有当控件本身用了别的文字档时才需要显式传入，否则保持默认，
  /// 让所有控件共用同一个图标盒。
  final TextStyle? style;

  /// 字形尺寸；为空时填满方框。超过方框时会被夹到方框边长。
  final double? size;

  /// 字形颜色；为空时继承外层 `IconTheme`。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedStyle = style ?? IdeTextStyles.of(context).bodySmall;
    final box = IdeMetrics.controlIconBoxFor(resolvedStyle);
    return SizedBox.square(
      dimension: box,
      child: Center(
        child:
            child ?? Icon(icon, size: math.min(size ?? box, box), color: color),
      ),
    );
  }
}
