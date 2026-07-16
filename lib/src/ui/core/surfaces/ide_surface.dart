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
    this.clipBehavior = Clip.antiAlias,
  });

  const IdeSurface.canvas({
    required Widget child,
    Key? key,
    EdgeInsetsGeometry? padding,
  }) : this(
         key: key,
         level: IdeSurfaceLevel.canvas,
         padding: padding,
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
          IdeSurfaceLevel.pane => IdeRadius.allMedium,
          IdeSurfaceLevel.popover => IdeRadius.allLarge,
        };
    final showBorder =
        level == IdeSurfaceLevel.pane || level == IdeSurfaceLevel.popover;

    return Container(
      clipBehavior: clipBehavior,
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: resolvedRadius,
        border: showBorder ? Border.all(color: colors.border) : null,
        boxShadow: level == IdeSurfaceLevel.popover
            ? IdeEffects.overlayShadow(brightness)
            : const <BoxShadow>[],
      ),
      child: child,
    );
  }
}
