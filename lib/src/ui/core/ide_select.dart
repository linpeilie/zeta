import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'ide_colors.dart';
import 'ide_metrics.dart';
import 'ide_spacing.dart';
import 'ide_text_styles.dart';

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
/// - 默认最小高度 [IdeMetrics.regularControlHeight]，并随 UI 字号同步增长
/// - small+dense 等效内边距（水平 [IdeSpacing.space6]，垂直 [IdeSpacing.space2]）
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

  /// 与 OutlineButton small+dense 对齐：水平 16×0.75×0.5≈6，垂直 8×0.75×0.5≈3。
  static const EdgeInsets _contentPadding = EdgeInsets.symmetric(
    horizontal: IdeSpacing.space8,
    vertical: IdeSpacing.space2,
  );

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final isEnabled = enabled && onChanged != null && options.isNotEmpty;
    final labelStyle = textStyles.bodySmall.copyWith(
      color: isEnabled ? colors.textPrimary : colors.textTertiary,
    );
    final controlHeight = IdeMetrics.controlHeightFor(
      labelStyle,
      size: controlSize,
    );

    final selected = _resolveSelectedOption();
    final minWidth = math.max(width ?? 0.0, popupMinWidth ?? 0.0);

    return sf.Select<T>(
      value: selected?.value ?? value,
      enabled: isEnabled,
      constraints: BoxConstraints(
        minWidth: width ?? 0,
        maxWidth: width ?? double.infinity,
        minHeight: controlHeight,
        maxHeight: controlHeight,
      ),
      padding: _contentPadding,
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
