import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'ide_colors.dart';
import 'ide_effects.dart';
import 'ide_motion.dart';
import 'ide_spacing.dart';
import 'ide_text_styles.dart';
import 'pane_widgets.dart';

/// [IdeTabs] 中的单个选项。
@immutable
class IdeTabItem<T> {
  /// 创建一个带业务值的 Tab 选项。
  const IdeTabItem({
    required this.value,
    required this.label,
    this.key,
    this.leadingIcon,
    this.semanticLabel,
  });

  /// 选中该项时回传的业务值。
  final T value;

  /// Tab 中显示的短标签。
  final String label;

  /// 用于测试和稳定复用 Element 的键。
  final Key? key;

  /// 标签前的可选图标。
  final IconData? leadingIcon;

  /// 覆盖默认标签的无障碍名称。
  final String? semanticLabel;
}

/// 面向桌面 IDE 的紧凑单选 Tab 组。
///
/// 交互结构复用 [sf.Tabs]，视觉层通过 Graphite token 收紧圆角、间距与
/// 层级；选中项额外使用短下划线和淡入动效，避免移动端胶囊感。
class IdeTabs<T> extends StatelessWidget {
  /// 创建一个受控的单选 Tab 组。
  const IdeTabs({
    required this.value,
    required this.items,
    required this.onChanged,
    super.key,
    this.expand = false,
    this.semanticLabel,
  }) : assert(items.length > 0, 'IdeTabs 至少需要一个选项。');

  /// 当前选中的业务值。
  final T value;

  /// 可供选择的 Tab 列表。
  final List<IdeTabItem<T>> items;

  /// 用户选择新 Tab 时触发。
  final ValueChanged<T> onChanged;

  /// 是否让所有 Tab 等宽占满可用宽度。
  final bool expand;

  /// 整个 Tab 组的无障碍名称。
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = items.indexWhere((item) => item.value == value);
    if (selectedIndex < 0) {
      throw FlutterError('IdeTabs.value 必须对应 items 中的一个选项。');
    }

    final colors = IdeColors.of(context);
    final tabs = DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.borderSubtle),
        borderRadius: IdeRadius.allSmall,
      ),
      child: sf.ComponentTheme(
        data: sf.TabsTheme(
          containerPadding: const EdgeInsets.all(IdeSpacing.space2),
          tabPadding: const EdgeInsets.symmetric(
            horizontal: IdeSpacing.space10,
            vertical: IdeSpacing.space4,
          ),
          backgroundColor: colors.surfaceElevated,
          borderRadius: IdeRadius.allSmall,
        ),
        child: sf.Tabs(
          index: selectedIndex,
          expand: expand,
          onChanged: (index) => onChanged(items[index].value),
          children: [
            for (var index = 0; index < items.length; index++)
              sf.TabItem(
                key: items[index].key,
                child: _IdeTabContent(
                  label: items[index].label,
                  leadingIcon: items[index].leadingIcon,
                  selected: index == selectedIndex,
                  semanticLabel:
                      items[index].semanticLabel ?? items[index].label,
                ),
              ),
          ],
        ),
      ),
    );

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: expand
          ? tabs
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: tabs,
            ),
    );
  }
}

/// 独立的桌面 Tab 风格动作或状态标签。
///
/// 下拉选择、多选项与只读状态不属于单选 Tab 组，因此使用该组件保留正确
/// 语义，同时与 [IdeTabs] 共享矩形表面、选中下划线与过渡动效。
class IdeTab extends StatelessWidget {
  /// 创建一个独立的 Tab 风格控件。
  const IdeTab({
    required this.label,
    super.key,
    this.leadingIcon,
    this.trailingIcon = Icons.keyboard_arrow_down_rounded,
    this.selected = false,
    this.enabled = true,
    this.onPressed,
    this.semanticLabel,
  });

  /// 控件中显示的短标签。
  final String label;

  /// 标签前的可选图标。
  final IconData? leadingIcon;

  /// 标签后的可选图标；默认下拉箭头会随选中态旋转。
  final IconData? trailingIcon;

  /// 是否呈现选中态。
  final bool selected;

  /// 是否允许交互。
  final bool enabled;

  /// 点击或键盘激活时触发；为空时作为只读标签展示。
  final VoidCallback? onPressed;

  /// 覆盖标签文本的无障碍名称。
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return PaneInteractiveSurface(
      onPressed: enabled ? onPressed : null,
      enabled: enabled,
      selected: selected,
      button: onPressed != null,
      semanticLabel: semanticLabel,
      padding: const EdgeInsets.symmetric(
        horizontal: IdeSpacing.space10,
        vertical: IdeSpacing.space4,
      ),
      borderRadius: IdeRadius.allSmall,
      backgroundColor: colors.surfaceElevated,
      hoverBackgroundColor: colors.border.withValues(alpha: 0.28),
      pressedBackgroundColor: colors.border.withValues(alpha: 0.4),
      selectedBackgroundColor: colors.frame,
      borderColor: colors.borderSubtle,
      selectedBorderColor: colors.border,
      child: _IdeTabContent(
        label: label,
        leadingIcon: leadingIcon,
        trailingIcon: trailingIcon,
        selected: selected,
        enabled: enabled,
      ),
    );
  }
}

class _IdeTabContent extends StatelessWidget {
  const _IdeTabContent({
    required this.label,
    required this.selected,
    this.leadingIcon,
    this.trailingIcon,
    this.enabled = true,
    this.semanticLabel,
  });

  final String label;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final bool selected;
  final bool enabled;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final foreground = !enabled
        ? colors.textTertiary
        : selected
        ? colors.textPrimary
        : colors.textSecondary;
    final content = AnimatedDefaultTextStyle(
      duration: IdeMotion.durationNormal,
      curve: IdeMotion.curveDefault,
      style: textStyles.bodySmall.copyWith(
        color: foreground,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
      ),
      child: TweenAnimationBuilder<Color?>(
        duration: IdeMotion.durationNormal,
        curve: IdeMotion.curveDefault,
        tween: ColorTween(end: foreground),
        builder: (context, color, child) {
          return IconTheme(
            data: IconThemeData(color: color ?? foreground, size: 13),
            child: child!,
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leadingIcon != null) ...[
              Icon(leadingIcon),
              const SizedBox(width: IdeSpacing.space4),
            ],
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (trailingIcon != null) ...[
              const SizedBox(width: IdeSpacing.space4),
              AnimatedRotation(
                turns:
                    selected &&
                        trailingIcon == Icons.keyboard_arrow_down_rounded
                    ? 0.5
                    : 0,
                duration: IdeMotion.durationNormal,
                curve: IdeMotion.curveDefault,
                child: Icon(trailingIcon),
              ),
            ],
          ],
        ),
      ),
    );

    final animatedContent = AnimatedOpacity(
      opacity: enabled ? (selected ? 1 : 0.82) : 0.48,
      duration: IdeMotion.durationNormal,
      curve: IdeMotion.curveDefault,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: IdeSpacing.space2),
            child: content,
          ),
          Positioned(
            bottom: -IdeSpacing.space2,
            child: AnimatedContainer(
              duration: IdeMotion.durationNormal,
              curve: IdeMotion.curveDefault,
              width: selected ? 18 : 0,
              height: 2,
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: IdeRadius.allSmall,
              ),
            ),
          ),
        ],
      ),
    );
    if (semanticLabel == null) {
      return animatedContent;
    }
    return Semantics(
      selected: selected,
      label: semanticLabel,
      excludeSemantics: true,
      child: animatedContent,
    );
  }
}
