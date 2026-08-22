import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'ide_colors.dart';
import 'ide_icon_box.dart';
import 'ide_metrics.dart';
import 'ide_spacing.dart';
import 'ide_text_styles.dart';

/// Select 触发器右侧的展开箭头。
///
/// shadcn 默认的 `SelectExpandIcon` 是一个固定 16px 的 lucide `chevronsUpDown`
/// ——它比 15px 的文字行盒高，是 shadcn 官网 Select（32）比 Button（30）高
/// 2px 的**唯一**原因。本组件把它换成等高图标盒里的 Material `unfold_more`
/// （与项目其余图标同族），保证下拉框拆掉固定高度后不会比按钮高一截。
///
/// 生效位置：[IdeSelect]；以及设置页仍直接使用 [sf.Select] 的字体选择器
/// （通过 `expandIcon:` 传入），让两条路径落在同一个图标尺寸上。
class IdeSelectExpandIcon extends StatelessWidget {
  /// 创建一个等高的展开箭头。
  const IdeSelectExpandIcon({super.key, this.color});

  /// 字形颜色；为空时继承外层 `IconTheme`。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IdeIconBox(Icons.unfold_more_rounded, color: color);
  }
}

/// [IdeSelect] 的单个选项。
@immutable
class IdeSelectOption<T> {
  /// 创建一个值 + 展示文案的选项。
  const IdeSelectOption(
    this.value,
    this.label, {
    this.enabled = true,
    this.key,
  });

  /// 选中后回传的业务值。
  final T value;

  /// 触发器与下拉项显示的文案。
  final String label;

  /// 是否允许选择；`false` 时在弹层中禁用该项。
  final bool enabled;

  /// 选项 Widget 稳定 key（测试与状态保留）。
  final Key? key;
}

/// [IdeSelect] 弹层相对触发器的宽度策略。
enum IdeSelectPopupWidthPolicy {
  /// 弹层宽度严格跟随触发器，保持紧凑选择器的默认行为。
  matchTrigger,

  /// 弹层按选项内容决定宽度，并继续服从显式的最小宽度约束。
  fitContent,
}

/// 统一 IDE 紧凑下拉选择器。
///
/// 封装 [sf.Select] 的默认规格差异，统一为：
/// - 字号 [IdeTextStyles.bodySmall]（对齐工具栏 / [IdeButton]）
/// - 竖向内边距 [IdeMetrics.controlPaddingYFor]，高度由内容自然撑开，
///   低于 [IdeMetrics.controlMinHeightFor] 时才被抬到点击目标下限
/// - 展开箭头走 [IdeSelectExpandIcon]，不让图标决定控件高度
///
/// feature 页面应优先使用本组件，而不是直接拼装 [sf.Select] 细节。
class IdeSelect<T> extends StatelessWidget {
  /// 创建一个受控的单选下拉。
  const IdeSelect({
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
    this.width,
    this.controlSize = IdeControlSize.regular,
    this.popupMaxHeight = 320,
    this.popupMinWidth,
    this.popupWidthPolicy = IdeSelectPopupWidthPolicy.matchTrigger,
    this.enabled = true,
    this.placeholder,
  }) : assert(popupMinWidth == null || popupMinWidth >= 0);

  /// 当前选中值；应能在 [options] 中匹配，否则回退展示第一项。
  final T value;

  /// 可选项；为空时组件仍渲染，但交互禁用。
  final List<IdeSelectOption<T>> options;

  /// 选中变化回调；为 `null` 时禁用。
  final ValueChanged<T?>? onChanged;

  /// 触发器宽度；为空时由 [sf.Select] 内容决定。
  final double? width;

  /// 触发器密度；设置页和工具栏默认使用常规档。
  final IdeControlSize controlSize;

  /// 下拉弹层最大高度。
  final double popupMaxHeight;

  /// 下拉弹层的额外最小宽度。
  ///
  /// 未设置时至少沿用触发器的显式 [width]；配合 [popupWidthPolicy] 的
  /// [IdeSelectPopupWidthPolicy.fitContent] 可让长选项不受紧凑触发器挤压。
  final double? popupMinWidth;

  /// 下拉弹层相对触发器的宽度策略。
  final IdeSelectPopupWidthPolicy popupWidthPolicy;

  /// 是否允许交互。
  final bool enabled;

  /// 无匹配值时的占位文案（当前实现仍要求 [value] 有对应项时优先）。
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final isEnabled = enabled && onChanged != null && options.isNotEmpty;
    final labelStyle = textStyles.bodySmall.copyWith(
      color: isEnabled ? colors.textPrimary : colors.textTertiary,
    );
    final selected = _resolveSelectedOption();
    final minWidth = math.max(width ?? 0.0, popupMinWidth ?? 0.0);

    return sf.Select<T>(
      value: selected?.value ?? value,
      enabled: isEnabled,
      expandIcon: IdeSelectExpandIcon(
        color: isEnabled ? colors.textSecondary : colors.textTertiary,
      ),
      // 高度不再夹死：由下面的竖向内边距 + 内容（文字行盒或等高的展开箭头）
      // 自然撑开，minHeight 只在 UI 字号很小时兜住点击目标。
      constraints: BoxConstraints(
        minWidth: width ?? 0,
        maxWidth: width ?? double.infinity,
        minHeight: IdeMetrics.controlMinHeightFor(controlSize),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: IdeSpacing.space8,
        vertical: IdeMetrics.controlPaddingYFor(controlSize),
      ),
      popupConstraints: BoxConstraints(
        maxHeight: popupMaxHeight,
        minWidth: minWidth,
      ),
      popupWidthConstraint: switch (popupWidthPolicy) {
        IdeSelectPopupWidthPolicy.matchTrigger =>
          sf.PopoverConstraint.anchorFixedSize,
        IdeSelectPopupWidthPolicy.fitContent => sf.PopoverConstraint.intrinsic,
      },
      itemBuilder: (context, selectedValue) {
        final option = _findOption(selectedValue) ?? selected;
        final text = option?.label ?? placeholder ?? '$selectedValue';
        return Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: labelStyle,
        );
      },
      onChanged: isEnabled ? onChanged : null,
      popup: sf.SelectPopup.noVirtualization(
        items: sf.SelectItemList(
          children: [
            for (final option in options)
              sf.SelectItemButton(
                key: option.key,
                value: option.value,
                enabled: option.enabled ? null : false,
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle.copyWith(
                    color: option.enabled
                        ? labelStyle.color
                        : colors.textTertiary,
                  ),
                ),
              ),
          ],
        ),
      ).call,
    );
  }

  IdeSelectOption<T>? _resolveSelectedOption() {
    return _findOption(value) ?? (options.isEmpty ? null : options.first);
  }

  IdeSelectOption<T>? _findOption(T candidate) {
    for (final option in options) {
      if (option.value == candidate) {
        return option;
      }
    }
    return null;
  }
}
