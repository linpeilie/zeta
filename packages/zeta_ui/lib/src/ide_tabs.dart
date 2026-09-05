import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'ide_colors.dart';
import 'ide_effects.dart';
import 'ide_icon_box.dart';
import 'ide_metrics.dart';
import 'ide_motion.dart';
import 'ide_spacing.dart';
import 'ide_text_styles.dart';
import 'pane_widgets.dart';
import 'zeta_ui_text_catalog.dart';

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
    this.loading = false,
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

  /// 是否仅对标签文字展示加载呼吸效果。
  final bool loading;
}

/// 面向桌面 IDE 的紧凑单选 Tab 组。
///
/// 交互结构复用 [sf.Tabs]，视觉层通过 Graphite token 收紧圆角、间距与
/// 层级；选中项由底色、文字主色与字重表达，配合淡入动效。
class IdeTabs<T> extends StatelessWidget {
  /// 创建一个受控的单选 Tab 组。
  const IdeTabs({
    required this.value,
    required this.items,
    required this.onChanged,
    super.key,
    this.expand = false,
    this.controlSize = IdeControlSize.regular,
    this.semanticLabel,
    this.scrollContentAlignment = AlignmentDirectional.centerStart,
  }) : assert(items.length > 0, 'IdeTabs 至少需要一个选项。');

  /// 当前选中的业务值。
  final T value;

  /// 可供选择的 Tab 列表。
  final List<IdeTabItem<T>> items;

  /// 用户选择新 Tab 时触发。
  final ValueChanged<T> onChanged;

  /// 是否让所有 Tab 等宽占满可用宽度。
  final bool expand;

  /// Tab 组外框的密度；设置页和工具栏默认使用常规档。
  final IdeControlSize controlSize;

  /// 整个 Tab 组的无障碍名称。
  final String? semanticLabel;

  /// 未扩展且内容短于视口时，Tab 组在滚动视口中的对齐方式。
  final AlignmentGeometry scrollContentAlignment;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = items.indexWhere((item) => item.value == value);
    if (selectedIndex < 0) {
      throw FlutterError('IdeTabs.value 必须对应 items 中的一个选项。');
    }

    final colors = IdeColors.of(context);
    // Tab 组有两层竖向内边距：外框到选中 pill（containerPadding）、pill 到
    // 文字（tabPadding）。两层加起来必须正好等于这一档的竖向内边距，组的
    // 高度才与 Select / Button 落在同一条公式上。外层固定 4——它是「组边框
    // 与 pill 的呼吸」，与密度档无关；剩下的都给 pill。
    const containerPaddingY = IdeSpacing.space4;
    final tabPaddingY = math.max(
      0.0,
      IdeMetrics.controlPaddingYFor(controlSize) - containerPaddingY,
    );
    final tabs = DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.borderSubtle),
        borderRadius: IdeRadius.allMedium,
      ),
      child: sf.ComponentTheme(
        data: sf.TabsTheme(
          containerPadding: const EdgeInsets.all(containerPaddingY),
          tabPadding: EdgeInsets.symmetric(
            horizontal: IdeSpacing.space10,
            vertical: tabPaddingY,
          ),
          backgroundColor: colors.surfaceElevated,
          // 内层选中态严格小于外框的 medium，遵守圆角递减规则；同时与
          // IdeSwitch 轨道、列表行 hover 底共用同一档「小圆角」。
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
                  loading: items[index].loading,
                  semanticLabel: _loadingSemanticLabel(context, items[index]),
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
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: IdeMetrics.controlMinHeightFor(controlSize),
        ),
        child: expand
            ? tabs
            : LayoutBuilder(
                builder: (context, constraints) {
                  final minWidth = constraints.hasBoundedWidth
                      ? constraints.maxWidth
                      : 0.0;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: minWidth),
                      // heightFactor 1：Align 默认会在竖向撑满可用空间，那会
                      // 让 Tab 组在固定高度的容器里被抻长。这里只借它做横向
                      // 对齐，高度仍然交给内容。
                      child: Align(
                        alignment: scrollContentAlignment,
                        heightFactor: 1,
                        child: tabs,
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  String _loadingSemanticLabel(BuildContext context, IdeTabItem<T> item) {
    final label = item.semanticLabel ?? item.label;
    if (!item.loading) {
      return label;
    }
    return IdeUiText.of(context).tabsLoadingSuffix(label);
  }
}

/// 独立的桌面 Tab 风格动作或状态标签。
///
/// 下拉选择、多选项与只读状态不属于单选 Tab 组，因此使用该组件保留正确
/// 语义，同时与 [IdeTabs] 共享矩形表面、选中态配色与过渡动效。
class IdeTab extends StatelessWidget {
  /// 创建一个独立的 Tab 风格控件。
  const IdeTab({
    required this.label,
    super.key,
    this.leadingIcon,
    this.trailingIcon = Icons.keyboard_arrow_down_rounded,
    this.selected = false,
    this.enabled = true,
    this.controlSize = IdeControlSize.compact,
    this.onPressed,
    this.semanticLabel,
    this.focusNode,
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

  /// 独立 Tab 的密度；Pane 内默认使用紧凑档。
  final IdeControlSize controlSize;

  /// 点击或键盘激活时触发；为空时作为只读标签展示。
  final VoidCallback? onPressed;

  /// 覆盖标签文本的无障碍名称。
  final String? semanticLabel;

  /// 用于关闭弹层后将键盘焦点还给该 Tab。
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    // 独立 Tab 始终有 1px 描边，而 `PaneInteractiveSurface` 的边框画在
    // Container 的 decoration 里、会占掉布局空间（Tab 组的边框走 DecoratedBox
    // 则不占）。把它从内边距里扣掉：文字到外框边缘仍是完整的一档内边距，
    // 外框高度也就落在「2 × controlPaddingY + 内容」上，与同档位的 Button 等高。
    final paddingY = math.max(
      0.0,
      IdeMetrics.controlPaddingYFor(controlSize) - _tabBorderWidth,
    );
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: IdeMetrics.controlMinHeightFor(controlSize),
      ),
      child: PaneInteractiveSurface(
        focusNode: focusNode,
        onPressed: enabled ? onPressed : null,
        enabled: enabled,
        selected: selected,
        button: onPressed != null,
        semanticLabel: semanticLabel,
        // 高度只由内边距和文字决定：放进固定高度的头栏 / 工具条时不跟着抻长。
        expandToConstraints: false,
        padding: EdgeInsets.symmetric(
          horizontal: IdeSpacing.space10,
          vertical: paddingY,
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
      ),
    );
  }
}

/// 独立 [IdeTab] 的描边宽度。
const double _tabBorderWidth = 1;

class _IdeTabContent extends StatelessWidget {
  const _IdeTabContent({
    required this.label,
    required this.selected,
    this.leadingIcon,
    this.trailingIcon,
    this.enabled = true,
    this.semanticLabel,
    this.loading = false,
  });

  final String label;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final bool selected;
  final bool enabled;
  final String? semanticLabel;

  final bool loading;

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
        // 图标一律走等高图标盒。这里的字形只有 13px，比 15px 的文字行盒矮，
        // 今天不会撑高行；套盒是为了拆掉固定高度后，行高只由文字决定，不随
        // 「这个 Tab 有没有图标」抖动。
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leadingIcon != null) ...[
              IdeIconBox.custom(child: Icon(leadingIcon)),
              const SizedBox(width: IdeSpacing.space4),
            ],
            _IdeTabLabel(label: label, loading: loading),
            if (trailingIcon != null) ...[
              const SizedBox(width: IdeSpacing.space4),
              IdeIconBox.custom(
                child: AnimatedRotation(
                  turns:
                      selected &&
                          trailingIcon == Icons.keyboard_arrow_down_rounded
                      ? 0.5
                      : 0,
                  duration: IdeMotion.durationNormal,
                  curve: IdeMotion.curveDefault,
                  child: Icon(trailingIcon),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    // 选中态由底色、文字主色与字重表达，不再画下划线：Tab 组本身已经有选中
    // pill，独立 Tab 有选中底色与描边，再加一条横线属于第三重冗余表达。
    final animatedContent = AnimatedOpacity(
      opacity: enabled ? (selected ? 1 : 0.82) : 0.48,
      duration: IdeMotion.durationNormal,
      curve: IdeMotion.curveDefault,
      child: content,
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

class _IdeTabLabel extends StatefulWidget {
  const _IdeTabLabel({required this.label, required this.loading});

  final String label;
  final bool loading;

  @override
  State<_IdeTabLabel> createState() => _IdeTabLabelState();
}

class _IdeTabLabelState extends State<_IdeTabLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: IdeMotion.durationLoadingPulse,
      value: 1,
    );
    _opacity = Tween<double>(begin: 0.55, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: IdeMotion.curveDefault),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _IdeTabLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loading != widget.loading) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (widget.loading && !_reduceMotion) {
      _controller.repeat(reverse: true);
      return;
    }
    _controller
      ..stop()
      ..value = 1;
  }

  @override
  Widget build(BuildContext context) {
    final label = Text(
      widget.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (!widget.loading) {
      return label;
    }
    if (_reduceMotion) {
      return Opacity(
        key: const ValueKey('ide-tab-loading-label-reduced-motion'),
        opacity: 0.72,
        child: label,
      );
    }
    return FadeTransition(
      key: const ValueKey('ide-tab-loading-label'),
      opacity: _opacity,
      child: label,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
