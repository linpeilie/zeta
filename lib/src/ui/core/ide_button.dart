import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'ide_colors.dart';
import 'ide_effects.dart';
import 'ide_icon_box.dart';
import 'ide_metrics.dart';
import 'ide_text_styles.dart';

/// IDE 紧凑按钮视觉变体，映射到 `shadcn_flutter` 的 [sf.ButtonStyle] 预设。
enum IdeButtonVariant {
  /// 描边按钮，适合工具栏次要操作与筛选触发器。
  outline,

  /// 中性底，适合非主路径操作。
  secondary,

  /// 主色实心，适合页面主行动点。
  primary,

  /// 极轻量，适合内嵌工具操作。
  ghost,

  /// 危险/破坏性操作。
  destructive,

  /// 主色描边 + 浅蓝底：需要被找到、但不该压过页面其余内容的次级主行动点。
  ///
  /// 与 [primary] 的分工：实心主色在工具栏里会抢走搜索框和分段控件的注意力
  /// ——一个筛选条上不该有「唯一亮点」。这一档保留主色的可识别性，把面积
  /// 换成描边和 `primaryMuted` 弱底。
  ///
  /// 生效位置：Agent 管理列表工具条的「自动检测 Agent」。
  accentOutline,

  /// 错误色描边：破坏性操作的次级形态。
  ///
  /// 与 [destructive] 的分工：实心红底适合确认对话框里那个「确定删除」；
  /// 页面头部一个随时可来回切换的开关（禁用/启用 Agent）用满色会长期报警。
  /// 这一档只把文字与描边染红，悬停时底色跟着泛红。
  ///
  /// 生效位置：Agent 管理详情页头部的「禁用 Agent」。
  dangerOutline,
}

/// 统一 IDE 紧凑按钮。
///
/// 默认 `ButtonSize.small` + `ButtonDensity.dense` + [IdeTextStyles.bodySmall]，
/// 并把文案垂直居中，避免 feature 直接拼装 [sf.OutlineButton] 时出现：
/// - 字号偏大（shadcn `typography.small` 14 vs IDE bodySmall 11）
/// - 固定 [IdeMetrics.toolbarHeight] 后文案顶对齐
///
/// 与 [IdeChip] 的分工：
/// - **Button**：动作触发（刷新、打开、确认）与带图标的筛选触发器；
/// - **Chip**：属性标签、可删除 tag、轻量状态胶囊。
class IdeButton extends StatelessWidget {
  /// 创建一个紧凑 IDE 按钮。
  const IdeButton({
    required this.label,
    super.key,
    this.onPressed,
    this.leading,
    this.leadingIcon,
    this.trailingIcon,
    this.enabled = true,
    this.variant = IdeButtonVariant.outline,
    this.controlSize = IdeControlSize.compact,
    this.height,
    this.width,
    this.maxLines = 1,
    this.semanticLabel,
  });

  /// 使用常规控件高度的工具栏按钮。
  const IdeButton.toolbar({
    required this.label,
    super.key,
    this.onPressed,
    this.leading,
    this.leadingIcon,
    this.trailingIcon,
    this.enabled = true,
    this.variant = IdeButtonVariant.outline,
    this.width,
    this.maxLines = 1,
    this.semanticLabel,
  }) : controlSize = IdeControlSize.regular,
       height = null;

  /// 按钮文案。
  final String label;

  /// 点击回调；为 `null` 时按钮禁用。
  final VoidCallback? onPressed;

  /// 文案前的可选自定义前导组件，优先于 [leadingIcon]。
  ///
  /// 存在的理由是加载指示器：按钮进入等待态时需要把图标换成
  /// `IdeLoadingIndicator`，如果只能传 [IconData]，调用方就只好退回裸
  /// `sf.Button` 自己拼——那正是本组件要消除的分叉。自定义组件的着色由调用方
  /// 负责，本组件不再套 [IconTheme]。
  ///
  /// **高度约束**：自定义组件不得高于 [IdeMetrics.controlIconBoxFor] 解析出的
  /// 图标盒，否则它会成为决定按钮高度的那个内容，让这一个按钮比同排的其他
  /// 控件高。拿不准就用 [IdeIconBox.custom] 包一层。
  final Widget? leading;

  /// 文案前可选图标。
  final IconData? leadingIcon;

  /// 文案后可选图标（如下拉箭头）。
  final IconData? trailingIcon;

  /// 是否允许交互；与 [onPressed] 同时为真时才可点。
  final bool enabled;

  /// 视觉变体。
  final IdeButtonVariant variant;

  /// 按钮密度；普通按钮默认紧凑，工具栏构造器使用常规档。
  final IdeControlSize controlSize;

  /// 外层固定高度；工具栏场景通常为 [IdeMetrics.toolbarHeight]。
  final double? height;

  /// 外层固定宽度；为空时由内容决定。
  final double? width;

  /// 文案最大行数。
  final int maxLines;

  /// 覆盖默认文案的无障碍名称。
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final isEnabled = enabled && onPressed != null;
    final foreground = _resolveForeground(
      colors: colors,
      enabled: isEnabled,
      variant: variant,
    );
    // 实心底必须与文字同色，避免「允许」勾号落在灰字/蓝底上。
    // 染色描边档同理：图标退回中性灰会把刚立起来的主色/危险语义拆散。
    final iconColor = switch (variant) {
      IdeButtonVariant.primary ||
      IdeButtonVariant.destructive ||
      IdeButtonVariant.accentOutline ||
      IdeButtonVariant.dangerOutline => foreground,
      IdeButtonVariant.outline ||
      IdeButtonVariant.secondary ||
      IdeButtonVariant.ghost =>
        isEnabled ? colors.textSecondary : colors.textTertiary,
    };

    final labelStyle = textStyles.bodySmall.copyWith(color: foreground);
    final button = sf.Button(
      onPressed: isEnabled ? onPressed : null,
      enabled: isEnabled,
      style: _resolveStyle(variant),
      // 有 leading 时 shadcn 内部 Row 默认顶对齐，alignment 负责垂直居中。
      alignment: Alignment.centerLeft,
      // 图标一律走等高图标盒：拆掉固定高度后，15/16px 的裸图标会比 15px 的
      // 文字行盒高，带图标的按钮就会比纯文字按钮高一截。
      leading:
          leading ??
          (leadingIcon == null
              ? null
              : IdeIconBox(leadingIcon!, style: labelStyle, color: iconColor)),
      trailing: trailingIcon == null
          ? null
          : IdeIconBox(trailingIcon!, style: labelStyle, color: iconColor),
      child: Text(
        label,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: labelStyle,
      ),
    );

    final minHeight = IdeMetrics.controlHeightFor(
      textStyles.bodySmall,
      size: controlSize,
    );
    final minSizedButton = SizedBox(height: minHeight, child: button);
    final content = height != null
        ? SizedBox(height: height, width: width, child: button)
        : width == null
        ? minSizedButton
        : SizedBox(width: width, child: minSizedButton);

    return Semantics(
      button: true,
      enabled: isEnabled,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: content,
    );
  }

  static sf.AbstractButtonStyle _resolveStyle(IdeButtonVariant variant) {
    const size = sf.ButtonSize.normal;
    const density = sf.ButtonDensity.dense;
    return switch (variant) {
      IdeButtonVariant.outline => const sf.ButtonStyle.outline(
        size: size,
        density: density,
      ),
      IdeButtonVariant.secondary => const sf.ButtonStyle.secondary(
        size: size,
        density: density,
      ),
      IdeButtonVariant.primary => const sf.ButtonStyle.primary(
        size: size,
        density: density,
      ),
      IdeButtonVariant.ghost => const sf.ButtonStyle.ghost(
        size: size,
        density: density,
      ),
      IdeButtonVariant.destructive => const sf.ButtonStyle.destructive(
        size: size,
        density: density,
      ),
      IdeButtonVariant.accentOutline => const sf.ButtonStyle(
        variance: _TintedOutlineVariance(_OutlineTint.accent),
        size: size,
        density: density,
      ),
      IdeButtonVariant.dangerOutline => const sf.ButtonStyle(
        variance: _TintedOutlineVariance(_OutlineTint.danger),
        size: size,
        density: density,
      ),
    };
  }

  static Color _resolveForeground({
    required IdeColors colors,
    required bool enabled,
    required IdeButtonVariant variant,
  }) {
    if (!enabled) {
      return colors.textTertiary;
    }
    return switch (variant) {
      IdeButtonVariant.primary => colors.onAccent,
      // 与 app_theme 中 destructiveForeground 一致。
      IdeButtonVariant.destructive => Colors.white,
      IdeButtonVariant.accentOutline => colors.accent,
      IdeButtonVariant.dangerOutline => colors.error,
      IdeButtonVariant.outline ||
      IdeButtonVariant.secondary ||
      IdeButtonVariant.ghost => colors.textPrimary,
    };
  }
}

/// [_TintedOutlineVariance] 的语义色来源。
enum _OutlineTint { accent, danger }

/// 复用 shadcn outline 按钮的全部度量，只把描边与底色换成 Graphite 语义色。
///
/// 除 `decoration` 外的每一项都直接转发给 [sf.ButtonVariance.outline]：内边距、
/// 光标、字号、外边距必须与其他 [IdeButton] 逐像素一致，否则同一个按钮组里
/// 染色的那一颗会比邻居高半个像素。文字与图标颜色由 [IdeButton] 在外层统一
/// 覆盖，这里只负责画框和底。
class _TintedOutlineVariance implements sf.AbstractButtonStyle {
  const _TintedOutlineVariance(this.tint);

  final _OutlineTint tint;

  static const sf.AbstractButtonStyle _base = sf.ButtonVariance.outline;

  @override
  sf.ButtonStateProperty<Decoration> get decoration => _decoration;

  @override
  sf.ButtonStateProperty<MouseCursor> get mouseCursor => _base.mouseCursor;

  @override
  sf.ButtonStateProperty<EdgeInsetsGeometry> get padding => _base.padding;

  @override
  sf.ButtonStateProperty<TextStyle> get textStyle => _base.textStyle;

  @override
  sf.ButtonStateProperty<IconThemeData> get iconTheme => _base.iconTheme;

  @override
  sf.ButtonStateProperty<EdgeInsetsGeometry> get margin => _base.margin;

  Decoration _decoration(BuildContext context, Set<WidgetState> states) {
    final colors = IdeColors.of(context);
    // 禁用态一律退回中性描边：这一档的语义色是「请注意我」，按不动的按钮
    // 继续喊就是噪音。
    if (states.contains(WidgetState.disabled)) {
      return _base.decoration(context, states);
    }
    final accent = switch (tint) {
      _OutlineTint.accent => colors.accent,
      _OutlineTint.danger => colors.error,
    };
    final hovered =
        states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.pressed);
    return BoxDecoration(
      // 静息态就带一层弱底，悬停再加深：只靠描边变化的反馈在 1px 线上看不见。
      color: accent.withValues(alpha: hovered ? 0.16 : 0.08),
      border: Border.all(
        color: accent.withValues(alpha: hovered ? 0.9 : 0.55),
        strokeAlign: BorderSide.strokeAlignCenter,
      ),
      borderRadius: IdeRadius.allSmall,
    );
  }
}
