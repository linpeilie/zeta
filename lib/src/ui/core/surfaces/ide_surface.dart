import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import '../ide_colors.dart';
import '../ide_effects.dart';

/// IDE 表面层级。
enum IdeSurfaceLevel { canvas, pane, row, popover }

/// 统一 Canvas、Pane、Row 与 Popover 的视觉装饰。
class IdeSurface extends StatelessWidget {
  const IdeSurface({
    required this.level,
    required this.child,
    super.key,
    this.padding,
    this.borderRadius,
    this.showBorder,
    this.clipBehavior = Clip.antiAlias,
  });

  const IdeSurface.canvas({
    required Widget child,
    Key? key,
    EdgeInsetsGeometry? padding,
    bool? showBorder,
  }) : this(
         key: key,
         level: IdeSurfaceLevel.canvas,
         padding: padding,
         showBorder: showBorder,
         child: child,
       );

  const IdeSurface.pane({
    required Widget child,
    Key? key,
    EdgeInsetsGeometry? padding,
  }) : this(
         key: key,
         level: IdeSurfaceLevel.pane,
         padding: padding,
         child: child,
       );

  const IdeSurface.row({
    required Widget child,
    Key? key,
    EdgeInsetsGeometry? padding,
  }) : this(
         key: key,
         level: IdeSurfaceLevel.row,
         padding: padding,
         child: child,
       );

  const IdeSurface.popover({
    required Widget child,
    Key? key,
    EdgeInsetsGeometry? padding,
  }) : this(
         key: key,
         level: IdeSurfaceLevel.popover,
         padding: padding,
         child: child,
       );

  final IdeSurfaceLevel level;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadiusGeometry? borderRadius;

  /// 是否绘制描边；为 null 时按 [level] 默认：pane/popover 有边框，canvas/row 无。
  ///
  /// 工作台中央 Canvas 列会显式传 `true`，与左右 [PanelCard] 对齐。
  final bool? showBorder;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final brightness = sf.Theme.of(context).brightness;
    final background = switch (level) {
      IdeSurfaceLevel.canvas => colors.canvasSurface,
      IdeSurfaceLevel.pane => colors.paneSurface,
      IdeSurfaceLevel.row => Colors.transparent,
      IdeSurfaceLevel.popover => colors.popoverSurface,
    };
    final resolvedRadius =
        borderRadius ??
        switch (level) {
          IdeSurfaceLevel.canvas || IdeSurfaceLevel.row => BorderRadius.zero,
          // 面板与浮层同属「大容器」档：它们是圆角嵌套链路的最外层，
          // 里面的卡片走 medium、代码块走 small，逐层收小。
          IdeSurfaceLevel.pane || IdeSurfaceLevel.popover => IdeRadius.allLarge,
        };
    final resolvedShowBorder =
        showBorder ??
        (level == IdeSurfaceLevel.pane || level == IdeSurfaceLevel.popover);

    // 面板档走平滑圆角（superellipse），控件档保持圆形圆角。
    final isPanelTier = IdeShapes.isPanelTier(resolvedRadius);

    // 边框必须放在 foregroundDecoration：decoration 边框画在 child 之下，
    // Agent 等不透明子树（如内层 IdeSurface.canvas）会盖住圆角四角描边。
    // 与 PanelCard 一致，保证描边始终浮在内容之上。
    // clipBehavior 会自动跟随 decoration 的形状，不需要额外处理。
    return Container(
      clipBehavior: clipBehavior,
      padding: padding,
      decoration: isPanelTier
          ? ShapeDecoration(
              color: background,
              shape: IdeShapes.panel(),
              shadows: level == IdeSurfaceLevel.popover
                  ? IdeEffects.overlayShadow(brightness)
                  : const <BoxShadow>[],
            )
          : BoxDecoration(
              color: background,
              borderRadius: resolvedRadius,
              boxShadow: level == IdeSurfaceLevel.popover
                  ? IdeEffects.overlayShadow(brightness)
                  : const <BoxShadow>[],
            ),
      foregroundDecoration: resolvedShowBorder
          ? (isPanelTier
                ? ShapeDecoration(
                    shape: IdeShapes.panel(
                      side: BorderSide(color: colors.border),
                    ),
                  )
                : BoxDecoration(
                    border: Border.all(color: colors.border),
                    borderRadius: resolvedRadius,
                  ))
          : null,
      child: child,
    );
  }
}
